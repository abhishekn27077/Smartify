-- ==============================================================================
-- SMARTIFY — MIGRATION: PHASE 1 BACKEND, ROUTING, FORWARDING & DEDUP REPAIR
-- Migration File: 20261019000003_phase1_backend_workflow_repair.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. SERVER-AUTHORITATIVE CANONICAL ROUTING & DEFAULTS TRIGGER
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.initialize_complaint_defaults()
RETURNS TRIGGER AS $$
DECLARE
    v_sla_days INT;
    v_student_program TEXT;
    v_target_dept_id UUID;
    v_l1_level_id UUID;
    v_cat_lower TEXT;
BEGIN
    -- 1. Fetch Level 1 Authority Tier
    SELECT id, sla_days INTO v_l1_level_id, v_sla_days 
    FROM public.authority_levels 
    WHERE level_number = 1 
    LIMIT 1;

    IF v_sla_days IS NULL THEN
        v_sla_days := 3;
    END IF;

    IF NEW.current_authority_level_id IS NULL THEN
        NEW.current_authority_level_id := v_l1_level_id;
    END IF;

    -- 2. Lookup student academic program from profile
    SELECT academic_program INTO v_student_program
    FROM public.profiles
    WHERE id = NEW.student_id;

    IF v_student_program IS NOT NULL AND (NEW.academic_program IS NULL OR trim(NEW.academic_program) = '') THEN
        NEW.academic_program := v_student_program;
    END IF;

    -- 3. Resolve Canonical Department based on Category & Program
    v_cat_lower := lower(COALESCE(NEW.category, ''));

    IF v_cat_lower LIKE '%wi-fi%' OR v_cat_lower LIKE '%wifi%' OR v_cat_lower LIKE '%internet%' OR v_cat_lower LIKE '%network%' OR v_cat_lower LIKE '%library%' OR v_cat_lower LIKE '%it service%' THEN
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'IT' LIMIT 1;
    ELSIF v_cat_lower LIKE '%hostel%' OR v_cat_lower LIKE '%mess%' OR v_cat_lower LIKE '%residential%' OR v_cat_lower LIKE '%warden%' OR v_cat_lower LIKE '%room%' THEN
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'HOSTEL' LIMIT 1;
    ELSIF v_cat_lower LIKE '%fee%' OR v_cat_lower LIKE '%scholarship%' OR v_cat_lower LIKE '%finance%' OR v_cat_lower LIKE '%account%' OR v_cat_lower LIKE '%dues%' THEN
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'FIN' LIMIT 1;
    ELSIF v_cat_lower LIKE '%infra%' OR v_cat_lower LIKE '%classroom%' OR v_cat_lower LIKE '%projector%' OR v_cat_lower LIKE '%facility%' OR v_cat_lower LIKE '%campus%' OR v_cat_lower LIKE '%maintenance%' THEN
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'INFRA' LIMIT 1;
    ELSE
        -- Academic Affairs / Program-Specific Routing
        IF v_student_program = 'MBA' THEN
            SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'MBA' LIMIT 1;
        ELSIF v_student_program IN ('M.Com', 'MCOM') THEN
            SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'MCOM' LIMIT 1;
        ELSE
            SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'MCA' LIMIT 1;
        END IF;
    END IF;

    IF v_target_dept_id IS NOT NULL THEN
        NEW.department_id := v_target_dept_id;
    END IF;

    -- 4. Assign Tracking Number if absent: SMT-YYYY-XXXXX
    IF NEW.tracking_number IS NULL OR trim(NEW.tracking_number) = '' THEN
        NEW.tracking_number := 'SMT-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' || LPAD(nextval('complaint_tracking_seq')::TEXT, 5, '0');
    END IF;

    -- 5. Set Initial SLA Deadlines (UTC)
    NEW.status := 'PENDING';
    NEW.current_tier_deadline := timezone('utc'::text, now()) + (v_sla_days || ' days')::INTERVAL;
    NEW.cutoff_deadline := timezone('utc'::text, now()) + INTERVAL '20 days';
    NEW.is_cutoff_paused := false;
    NEW.created_at := timezone('utc'::text, now());
    NEW.updated_at := timezone('utc'::text, now());

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_initialize_complaint_defaults ON public.complaints;
CREATE TRIGGER trg_initialize_complaint_defaults
    BEFORE INSERT ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.initialize_complaint_defaults();

-- ------------------------------------------------------------------------------
-- 2. AUTHORITY OWNERSHIP & ASSIGNMENT PRESERVATION TRIGGER
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_preserve_complaint_authority_ownership()
RETURNS TRIGGER AS $$
BEGIN
    -- When moving to UNDER_REVIEW, assign to acting authority if unassigned
    IF NEW.status = 'UNDER_REVIEW' AND NEW.assigned_authority_id IS NULL THEN
        NEW.assigned_authority_id := auth.uid();
    END IF;

    -- When resolving or rejecting, preserve assigned authority; fallback to actor if unassigned
    IF NEW.status IN ('RESOLVED', 'REJECTED') THEN
        IF NEW.assigned_authority_id IS NULL THEN
            NEW.assigned_authority_id := COALESCE(OLD.assigned_authority_id, auth.uid());
        END IF;
    END IF;

    -- Prevent accidental loss of ownership on other non-forwarding updates
    IF NEW.assigned_authority_id IS NULL AND OLD.assigned_authority_id IS NOT NULL AND NEW.status != 'ESCALATED' THEN
        NEW.assigned_authority_id := OLD.assigned_authority_id;
    END IF;

    NEW.updated_at := timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_preserve_complaint_authority_ownership ON public.complaints;
CREATE TRIGGER trg_preserve_complaint_authority_ownership
    BEFORE UPDATE ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_preserve_complaint_authority_ownership();

-- ------------------------------------------------------------------------------
-- 3. DEDUPLICATION & AUTHORITATIVE STATUS HISTORY LOGGING
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_complaint_status_change()
RETURNS TRIGGER AS $$
DECLARE
    v_actor_id UUID;
    v_profile RECORD;
    v_name TEXT;
    v_role TEXT;
    v_dept_id UUID;
    v_dept_name TEXT;
    v_level_num INT;
    v_designation TEXT;
    v_event_type TEXT;
    v_remarks TEXT;
    v_is_system BOOLEAN := false;
    v_assigned_tier TEXT;
    v_assigned_name TEXT;
    v_existing_id UUID;
    v_now TIMESTAMPTZ;
BEGIN
    IF (TG_OP = 'INSERT') 
       OR (OLD.status IS DISTINCT FROM NEW.status) 
       OR (OLD.current_authority_level_id IS DISTINCT FROM NEW.current_authority_level_id) THEN
        v_now := timezone('utc'::text, now());
        v_actor_id := auth.uid();

        -- Capture assigned tier info if escalated or routed
        IF NEW.current_authority_level_id IS NOT NULL THEN
            SELECT al.title INTO v_assigned_tier
            FROM public.authority_levels al
            WHERE al.id = NEW.current_authority_level_id;
        END IF;

        IF NEW.assigned_authority_id IS NOT NULL THEN
            SELECT p.full_name INTO v_assigned_name
            FROM public.profiles p
            WHERE p.id = NEW.assigned_authority_id;
        END IF;
        
        -- Check if an identical status history event was already recorded within the last 5 seconds
        -- for the same complaint, same status, AND same assigned tier to prevent duplicate history records
        IF TG_OP != 'INSERT' THEN
            SELECT id INTO v_existing_id
            FROM public.complaint_status_history
            WHERE complaint_id = NEW.id
              AND new_status = NEW.status
              AND (assigned_to_tier IS NOT DISTINCT FROM v_assigned_tier)
              AND created_at >= (v_now - INTERVAL '5 seconds')
            ORDER BY created_at DESC
            LIMIT 1;

            IF v_existing_id IS NOT NULL THEN
                -- Update remarks on existing row if custom remarks supplied
                IF NEW.status_remarks IS NOT NULL AND length(trim(NEW.status_remarks)) > 0 THEN
                    UPDATE public.complaint_status_history
                    SET remarks = NEW.status_remarks,
                        assigned_to_tier = COALESCE(v_assigned_tier, assigned_to_tier),
                        assigned_to_name = COALESCE(v_assigned_name, assigned_to_name)
                    WHERE id = v_existing_id;
                END IF;
                RETURN NEW;
            END IF;
        END IF;

        -- Identify Actor
        IF TG_OP = 'INSERT' THEN
            v_actor_id := COALESCE(v_actor_id, NEW.student_id);
            v_event_type := 'SUBMITTED';
            v_remarks := 'Grievance registered and placed in Intake Queue.';
        ELSE
            -- Map event type based on new status
            v_event_type := CASE 
                WHEN NEW.status = 'UNDER_REVIEW' THEN 'UNDER_REVIEW'
                WHEN NEW.status = 'RESOLVED' THEN 'RESOLVED'
                WHEN NEW.status = 'REJECTED' THEN 'REJECTED'
                WHEN NEW.status = 'ESCALATED' AND v_actor_id IS NULL THEN 'SYSTEM_ESCALATION'
                WHEN NEW.status = 'ESCALATED' THEN 'FORWARDED'
                WHEN NEW.status = 'CUTOFF_PAUSED' THEN 'PAUSED'
                WHEN NEW.status = 'UNDER_REVIEW' AND OLD.status = 'CUTOFF_PAUSED' THEN 'RESUMED'
                ELSE 'STATUS_CHANGE'
            END;

            -- Remarks
            IF NEW.status = 'RESOLVED' THEN
                v_remarks := COALESCE(NEW.resolution_notes, NEW.status_remarks, 'Grievance marked as resolved.');
            ELSIF NEW.status = 'CUTOFF_PAUSED' THEN
                v_remarks := 'Automation paused: Reached 20-calendar-day campus cutoff limit.';
            ELSIF NEW.status = 'ESCALATED' AND v_actor_id IS NULL THEN
                v_remarks := 'Escalated to next authority tier due to SLA breach.';
            ELSE
                v_remarks := COALESCE(NEW.status_remarks, 'Status updated to ' || NEW.status::TEXT);
            END IF;
        END IF;

        -- Snapshot Actor Identity
        IF v_actor_id IS NULL THEN
            v_is_system := true;
            v_name := 'System Redressal Engine (AUTOMATED)';
            v_role := 'SYSTEM';
            v_designation := 'Automated System';
        ELSE
            SELECT p.id, p.full_name, p.role, p.department_id, d.name AS dept_name,
                   p.designation, p.academic_program, al.level_number
            INTO v_profile
            FROM public.profiles p
            LEFT JOIN public.departments d ON d.id = p.department_id
            LEFT JOIN public.authority_levels al ON al.id = p.authority_level_id
            WHERE p.id = v_actor_id;

            IF FOUND THEN
                v_name := v_profile.full_name;
                v_role := v_profile.role::TEXT;
                v_dept_id := v_profile.department_id;
                v_dept_name := v_profile.dept_name;
                v_level_num := v_profile.level_number;
                
                IF v_profile.role = 'student' THEN
                    v_designation := COALESCE(v_profile.academic_program || ' Student', 'Student');
                ELSE
                    v_designation := v_profile.designation;
                END IF;
            ELSE
                -- Fail-safe for unmapped user ID
                v_name := 'Authenticated Campus Member';
                v_role := 'MEMBER';
            END IF;
        END IF;

        -- Insert single authoritative status history snapshot
        INSERT INTO public.complaint_status_history (
            complaint_id,
            changed_by,
            actor_user_id,
            actor_display_name,
            actor_role,
            actor_department_id,
            actor_department_name,
            actor_authority_level,
            actor_designation,
            event_type,
            is_system_event,
            old_status,
            new_status,
            remarks,
            assigned_to_tier,
            assigned_to_name,
            created_at
        ) VALUES (
            NEW.id,
            v_actor_id,
            v_actor_id,
            v_name,
            v_role,
            v_dept_id,
            v_dept_name,
            v_level_num,
            v_designation,
            v_event_type,
            v_is_system,
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
            NEW.status,
            v_remarks,
            v_assigned_tier,
            v_assigned_name,
            v_now
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach trigger on complaints
DROP TRIGGER IF EXISTS trg_log_complaint_status_change ON public.complaints;
CREATE TRIGGER trg_log_complaint_status_change
    AFTER INSERT OR UPDATE OF status, current_authority_level_id ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.log_complaint_status_change();

-- ------------------------------------------------------------------------------
-- 4. REAL INTAKE NOTIFICATION TRIGGER
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_notify_complaint_intake()
RETURNS TRIGGER AS $$
DECLARE
    v_l1_auth RECORD;
BEGIN
    -- 1. Notify Student: Grievance Successfully Registered
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        title,
        message,
        notification_type,
        is_read,
        created_at
    ) VALUES (
        NEW.student_id,
        NEW.id,
        'Grievance Registered: ' || NEW.tracking_number,
        'Your grievance "' || NEW.title || '" has been registered and placed in the Level 1 Intake Queue.',
        'STATUS_CHANGE',
        false,
        timezone('utc'::text, now())
    );

    -- 2. Notify Receiving Level 1 Authority for this Department
    SELECT p.id INTO v_l1_auth
    FROM public.profiles p
    JOIN public.authority_levels al ON p.authority_level_id = al.id
    WHERE p.department_id = NEW.department_id
      AND al.level_number = 1
      AND p.role IN ('authority', 'admin')
    LIMIT 1;

    IF v_l1_auth.id IS NOT NULL THEN
        INSERT INTO public.notifications (
            user_id,
            complaint_id,
            title,
            message,
            notification_type,
            is_read,
            created_at
        ) VALUES (
            v_l1_auth.id,
            NEW.id,
            'New Grievance in Intake Queue',
            'New grievance ' || NEW.tracking_number || ' registered under ' || NEW.category || ' requiring Level 1 review.',
            'STATUS_CHANGE',
            false,
            timezone('utc'::text, now())
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_complaint_intake ON public.complaints;
CREATE TRIGGER trg_notify_complaint_intake
    AFTER INSERT ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_notify_complaint_intake();

-- ------------------------------------------------------------------------------
-- 5. TRANSACTIONAL FORWARDING RPC WITH STRUCTURED CONTROLLED ERROR (NO PGRST116)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forward_grievance_to_next_tier(
    p_complaint_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_profile RECORD;
    v_complaint RECORD;
    v_current_level_num INT;
    v_next_level RECORD;
    v_next_authority RECORD;
    v_new_deadline TIMESTAMPTZ;
    v_now TIMESTAMPTZ;
    v_result JSONB;
BEGIN
    v_now := timezone('utc'::text, now());
    v_caller_id := auth.uid();

    -- 1. Authentication Check
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'AUTH_REQUIRED',
            'message', 'Authentication required to forward grievances.'
        );
    END IF;

    -- Fetch caller profile
    SELECT id, full_name, role, department_id, authority_level_id, designation
    INTO v_caller_profile
    FROM public.profiles
    WHERE id = v_caller_id;

    IF NOT FOUND OR v_caller_profile.role NOT IN ('authority', 'admin') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'Only authorized authorities or administrators can forward grievances.'
        );
    END IF;

    -- 2. Validate Forwarding Justification
    IF p_reason IS NULL OR length(trim(p_reason)) < 5 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'JUSTIFICATION_REQUIRED',
            'message', 'A forwarding justification of at least 5 characters is mandatory.'
        );
    END IF;

    -- 3. Lock Complaint for Update
    SELECT c.*, d.name AS dept_name, d.code AS dept_code,
           al.level_number AS current_level_number, al.title AS current_level_title
    INTO v_complaint
    FROM public.complaints c
    JOIN public.departments d ON c.department_id = d.id
    JOIN public.authority_levels al ON c.current_authority_level_id = al.id
    WHERE c.id = p_complaint_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'NOT_FOUND',
            'message', 'Grievance not found.'
        );
    END IF;

    -- 4. Scope & Department Authorization Check
    IF v_caller_profile.role != 'admin' THEN
        IF v_complaint.department_id != v_caller_profile.department_id
           AND (v_complaint.assigned_authority_id IS DISTINCT FROM v_caller_id) THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'DEPT_ACCESS_DENIED',
                'message', 'Access denied: You are not authorized to forward grievances for ' || v_complaint.dept_name || '.'
            );
        END IF;
    END IF;

    -- 5. Status Transition Checks
    IF v_complaint.status IN ('RESOLVED', 'REJECTED') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'TERMINAL_STATE',
            'message', 'Cannot forward: Grievance ' || v_complaint.tracking_number || ' is already ' || v_complaint.status::TEXT || '.'
        );
    END IF;

    IF v_complaint.status = 'CUTOFF_PAUSED' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'CUTOFF_PAUSED',
            'message', 'Cannot forward: Grievance ' || v_complaint.tracking_number || ' is under 20-day cutoff freeze. Requires administrative resumption.'
        );
    END IF;

    -- 6. Resolve Next Authority Tier
    v_current_level_num := v_complaint.current_level_number;
    IF v_current_level_num >= 4 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'MAX_TIER_REACHED',
            'message', 'Cannot forward: Grievance ' || v_complaint.tracking_number || ' is already at the highest authority level (Level ' || v_current_level_num || ').'
        );
    END IF;

    SELECT id, level_number, title, sla_days
    INTO v_next_level
    FROM public.authority_levels
    WHERE level_number = v_current_level_num + 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'NEXT_TIER_MISSING',
            'message', 'Next authority tier Level ' || (v_current_level_num + 1) || ' is not configured in the system.'
        );
    END IF;

    -- 7. Query Next Active Authority within Canonical Department Scope
    SELECT p.id, p.full_name, p.email, p.designation
    INTO v_next_authority
    FROM public.profiles p
    WHERE p.department_id = v_complaint.department_id
      AND p.authority_level_id = v_next_level.id
      AND p.role IN ('authority', 'admin')
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'NO_ELIGIBLE_AUTHORITY',
            'message', 'No eligible Level ' || v_next_level.level_number || ' authority is configured for ' || v_complaint.dept_name || '.'
        );
    END IF;

    -- 8. Compute Next Tier Deadline
    v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;

    -- 9. Atomically Update Complaint
    UPDATE public.complaints
    SET 
        current_authority_level_id = v_next_level.id,
        assigned_authority_id = v_next_authority.id,
        status = 'ESCALATED',
        status_remarks = 'Forwarded to ' || v_next_level.title || '. Reason: ' || trim(p_reason),
        current_tier_deadline = v_new_deadline,
        updated_at = v_now
    WHERE id = p_complaint_id;

    -- 10. Record in complaint_escalations
    INSERT INTO public.complaint_escalations (
        complaint_id,
        from_level_id,
        to_level_id,
        escalated_by,
        is_automated,
        reason,
        tier_days_spent,
        created_at
    ) VALUES (
        p_complaint_id,
        v_complaint.current_authority_level_id,
        v_next_level.id,
        v_caller_id,
        false,
        trim(p_reason),
        GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT),
        v_now
    );

    -- 11. Ensure assigned_to_tier and assigned_to_name on complaint_status_history
    UPDATE public.complaint_status_history
    SET 
        assigned_to_tier = v_next_level.title,
        assigned_to_name = v_next_authority.full_name
    WHERE complaint_id = p_complaint_id
      AND new_status = 'ESCALATED'
      AND created_at >= (v_now - INTERVAL '5 seconds');

    -- 12. Create Real In-App Notifications
    -- Notification to Student
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        title,
        message,
        notification_type,
        is_read,
        created_at
    ) VALUES (
        v_complaint.student_id,
        p_complaint_id,
        'Grievance Forwarded to Level ' || v_next_level.level_number,
        'Your grievance ' || v_complaint.tracking_number || ' has been forwarded to ' || v_next_authority.full_name || ' (' || v_next_level.title || ').',
        'ESCALATION',
        false,
        v_now
    );

    -- Notification to Next Authority
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        title,
        message,
        notification_type,
        is_read,
        created_at
    ) VALUES (
        v_next_authority.id,
        p_complaint_id,
        'Grievance Forwarded to Your Queue',
        'Grievance ' || v_complaint.tracking_number || ' from ' || v_complaint.dept_name || ' has been forwarded to you for Level ' || v_next_level.level_number || ' review.',
        'ESCALATION',
        false,
        v_now
    );

    -- 13. Append-Only Audit Trail Log
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
    VALUES (
        v_caller_id,
        'MANUAL_TIER_FORWARDING',
        'complaints',
        p_complaint_id,
        jsonb_build_object(
            'tracking_number', v_complaint.tracking_number,
            'department', v_complaint.dept_name,
            'from_level', v_current_level_num,
            'to_level', v_next_level.level_number,
            'forwarded_by', v_caller_profile.full_name,
            'forwarded_to', v_next_authority.full_name,
            'reason', trim(p_reason)
        ),
        v_now
    );

    -- 14. Return Deterministic Structured Success Object
    v_result := jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'department_name', v_complaint.dept_name,
        'from_level_number', v_current_level_num,
        'to_level_number', v_next_level.level_number,
        'to_level_title', v_next_level.title,
        'assigned_authority_id', v_next_authority.id,
        'assigned_authority_name', v_next_authority.full_name,
        'message', 'Grievance ' || v_complaint.tracking_number || ' successfully forwarded to ' || v_next_authority.full_name || ' (' || v_next_level.title || ').'
    );

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.forward_grievance_to_next_tier(UUID, TEXT) TO authenticated;

-- ------------------------------------------------------------------------------
-- 6. REMOVE REDUNDANT MANUAL INSERTS FROM SCHEDULER & RESUMPTION FUNCTIONS
-- ------------------------------------------------------------------------------
-- Clean execute_sla_escalations: Let complaints trigger handle complaint_status_history
CREATE OR REPLACE FUNCTION public.execute_sla_escalations()
RETURNS JSONB AS $$
DECLARE
    v_complaint RECORD;
    v_next_level RECORD;
    v_next_authority RECORD;
    v_now TIMESTAMPTZ;
    v_new_deadline TIMESTAMPTZ;
    v_escalated_count INT := 0;
    v_paused_count INT := 0;
BEGIN
    v_now := timezone('utc'::text, now());

    -- Phase 1: 20-Day Cutoff Freeze
    FOR v_complaint IN
        SELECT c.id, c.tracking_number, c.status, c.student_id, c.current_authority_level_id
        FROM public.complaints c
        WHERE (v_now >= c.cutoff_deadline OR c.created_at <= (v_now - INTERVAL '20 days'))
          AND c.status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')
          AND c.is_cutoff_paused = false
        ORDER BY c.created_at ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.complaints
        SET status = 'CUTOFF_PAUSED',
            status_remarks = 'Automated 20-calendar-day campus cutoff limit reached. Automated forwarding frozen pending administrative review.',
            is_cutoff_paused = true,
            paused_at = v_now,
            updated_at = v_now
        WHERE id = v_complaint.id;

        -- Audit log
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
        VALUES (
            NULL,
            'AUTOMATED_CUTOFF_PAUSE',
            'complaints',
            v_complaint.id,
            jsonb_build_object('tracking_number', v_complaint.tracking_number, 'cutoff_at', v_now),
            v_now
        );

        -- Notification to Complainant
        INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
        VALUES (
            v_complaint.student_id,
            v_complaint.id,
            'Grievance Processing Paused: 20-Day Limit',
            'Your grievance ' || v_complaint.tracking_number || ' has reached the 20-calendar-day campus cutoff limit. Automated forwarding is paused pending Administrative review.',
            'DEADLINE_WARNING',
            v_now
        );

        v_paused_count := v_paused_count + 1;
    END LOOP;

    -- Phase 2: SLA Escalations for Active Grievances (Levels 1 to 3)
    FOR v_complaint IN
        SELECT c.id, c.tracking_number, c.status, c.student_id, c.department_id,
               c.current_authority_level_id, c.updated_at,
               al.level_number AS current_level_number,
               al.title AS current_level_title
        FROM public.complaints c
        JOIN public.authority_levels al ON c.current_authority_level_id = al.id
        WHERE v_now >= c.current_tier_deadline
          AND c.status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')
          AND c.is_cutoff_paused = false
          AND al.level_number < 4
        ORDER BY c.current_tier_deadline ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        SELECT id, level_number, title, sla_days INTO v_next_level
        FROM public.authority_levels
        WHERE level_number = v_complaint.current_level_number + 1;

        IF v_next_level.id IS NOT NULL THEN
            v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;

            SELECT id, full_name INTO v_next_authority
            FROM public.profiles
            WHERE department_id = v_complaint.department_id
              AND authority_level_id = v_next_level.id
              AND role IN ('authority', 'admin')
            LIMIT 1;

            UPDATE public.complaints
            SET current_authority_level_id = v_next_level.id,
                assigned_authority_id = v_next_authority.id,
                status = 'ESCALATED',
                status_remarks = 'Auto-forwarded to ' || v_next_level.title || ' due to SLA expiration.',
                current_tier_deadline = v_new_deadline,
                updated_at = v_now
            WHERE id = v_complaint.id;

            -- Record in complaint escalations
            INSERT INTO public.complaint_escalations (
                complaint_id,
                from_level_id,
                to_level_id,
                escalated_by,
                is_automated,
                reason,
                tier_days_spent,
                created_at
            ) VALUES (
                v_complaint.id,
                v_complaint.current_authority_level_id,
                v_next_level.id,
                NULL,
                true,
                'Automated escalation: SLA breached at Level ' || v_complaint.current_level_number,
                GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT),
                v_now
            );

            -- Ensure assigned info on status history
            UPDATE public.complaint_status_history
            SET assigned_to_tier = v_next_level.title,
                assigned_to_name = v_next_authority.full_name
            WHERE complaint_id = v_complaint.id
              AND new_status = 'ESCALATED'
              AND created_at >= (v_now - INTERVAL '5 seconds');

            -- Audit log
            INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
            VALUES (
                NULL,
                'AUTOMATED_ESCALATION',
                'complaints',
                v_complaint.id,
                jsonb_build_object(
                    'tracking_number', v_complaint.tracking_number,
                    'from_level', v_complaint.current_level_number,
                    'to_level', v_next_level.level_number
                ),
                v_now
            );

            -- Notifications
            INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
            VALUES (
                v_complaint.student_id,
                v_complaint.id,
                'Grievance Escalated: SLA Breached',
                'Your grievance ' || v_complaint.tracking_number || ' was escalated to ' || v_next_level.title || ' due to SLA expiration.',
                'ESCALATION',
                v_now
            );

            IF v_next_authority.id IS NOT NULL THEN
                INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
                VALUES (
                    v_next_authority.id,
                    v_complaint.id,
                    'Action Required: Escalated Grievance',
                    'Grievance ' || v_complaint.tracking_number || ' has been escalated to your queue due to tier SLA breach.',
                    'ESCALATION',
                    v_now
                );
            END IF;

            v_escalated_count := v_escalated_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'escalated_count', v_escalated_count,
        'paused_count', v_paused_count,
        'executed_at', v_now
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clean resume_cutoff_grievance: Let complaints trigger handle complaint_status_history
CREATE OR REPLACE FUNCTION public.resume_cutoff_grievance(
    p_complaint_id UUID,
    p_extension_days INT DEFAULT 5,
    p_resumption_notes TEXT DEFAULT 'Administrative review complete. SLA extended.'
)
RETURNS JSONB AS $$
DECLARE
    v_complaint RECORD;
    v_now TIMESTAMPTZ;
    v_new_deadline TIMESTAMPTZ;
    v_new_cutoff TIMESTAMPTZ;
BEGIN
    v_now := timezone('utc'::text, now());

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Only Campus Administrators can resume cutoff-paused grievances.';
    END IF;

    IF p_extension_days < 1 OR p_extension_days > 14 THEN
        RAISE EXCEPTION 'Extension days must be between 1 and 14 days.';
    END IF;

    SELECT id, tracking_number, status, student_id, is_cutoff_paused
    INTO v_complaint
    FROM public.complaints
    WHERE id = p_complaint_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Grievance % not found.', p_complaint_id;
    END IF;

    IF v_complaint.status != 'CUTOFF_PAUSED' THEN
        RAISE EXCEPTION 'Cannot resume: Grievance % is not currently in CUTOFF_PAUSED state (Status: %).',
            v_complaint.tracking_number, v_complaint.status;
    END IF;

    v_new_deadline := v_now + (p_extension_days || ' days')::INTERVAL;
    v_new_cutoff := v_now + (p_extension_days + 7 || ' days')::INTERVAL;

    UPDATE public.complaints
    SET status = 'UNDER_REVIEW',
        status_remarks = 'Administrative resumption authorized: ' || trim(p_resumption_notes),
        is_cutoff_paused = false,
        resumed_at = v_now,
        resumed_by = auth.uid(),
        current_tier_deadline = v_new_deadline,
        cutoff_deadline = v_new_cutoff,
        updated_at = v_now
    WHERE id = p_complaint_id;

    -- Immutable Audit Log
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
    VALUES (
        auth.uid(),
        'RESUMPTION_AUTHORIZED',
        'complaints',
        p_complaint_id,
        jsonb_build_object(
            'tracking_number', v_complaint.tracking_number,
            'resumption_notes', trim(p_resumption_notes),
            'resumed_at', v_now,
            'new_tier_deadline', v_new_deadline,
            'new_cutoff_deadline', v_new_cutoff
        ),
        v_now
    );

    -- Notify Complainant
    INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
    VALUES (
        v_complaint.student_id,
        p_complaint_id,
        'Grievance Resumed: Administrative Sign-Off',
        'Your grievance ' || v_complaint.tracking_number || ' has been administratively resumed for investigation. Deadline extended by ' || p_extension_days || ' days.',
        'RESUMPTION',
        v_now
    );

    RETURN jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'new_status', 'UNDER_REVIEW',
        'extended_days', p_extension_days,
        'new_deadline', v_new_deadline,
        'resumed_at', v_now
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
