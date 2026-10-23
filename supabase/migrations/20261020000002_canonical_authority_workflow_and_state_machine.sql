-- ==============================================================================
-- SMARTIFY — CANONICAL AUTHORITY WORKFLOW & STATE MACHINE CORRECTION
-- Migration: 20261020000002_canonical_authority_workflow_and_state_machine.sql
-- 
-- Fixes:
-- 1. Tightens RLS on public.complaints for UPDATE:
--    - Enforces that only the current authority tier, matching department, and current assignee can act.
--    - Completely prevents previous-tier authorities from modifying forwarded complaints.
--    - Completely locks terminal (RESOLVED, REJECTED) and frozen (CUTOFF_PAUSED) complaints from mutation.
-- 2. Enhances forward_grievance_to_next_tier RPC:
--    - Strictly validates caller authority level == current complaint authority level.
--    - Strictly validates caller assignment (must be assigned authority if assigned).
--    - Validates next-tier existence and eligible authority before updating.
--    - Updates current_tier_deadline atomically to next tier's SLA to prevent false SLA escalations.
--    - Prevents double-forwarding and records full human actor credentials.
-- 3. Corrects execute_sla_escalations():
--    - Idempotent and checks current state.
--    - Never duplicates human forwarding.
--    - Distinctly logs System Redressal Engine (AUTOMATED).
-- 4. Cleans up duplicate history on test records and prevents duplicate UNDER_REVIEW logging.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. STRICT SERVER-SIDE RLS UPDATE POLICY
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Complaint update policy" ON public.complaints;
CREATE POLICY "Complaint update policy"
    ON public.complaints FOR UPDATE
    TO authenticated
    USING (
        -- Complainant student can only update if still PENDING
        (student_id = auth.uid() AND status = 'PENDING')
        -- Admin has supervisory override
        OR public.is_admin()
        -- Authority can ONLY update if:
        -- 1. Role is authority
        -- 2. Department matches complaint department
        -- 3. Authority tier matches complaint current tier (PREVIOUS AUTHORITIES CANNOT MUTATE)
        -- 4. Case is assigned to caller OR is unassigned at this tier
        -- 5. Case is not terminal (RESOLVED/REJECTED) and not frozen by 20-day cutoff
        OR (
            public.is_authority()
            AND department_id = public.get_user_department_id()
            AND current_authority_level_id = (SELECT authority_level_id FROM public.profiles WHERE id = auth.uid())
            AND (assigned_authority_id = auth.uid() OR assigned_authority_id IS NULL)
            AND status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')
            AND is_cutoff_paused = false
        )
    )
    WITH CHECK (
        (student_id = auth.uid() AND status = 'PENDING')
        OR public.is_admin()
        OR (
            public.is_authority()
            AND department_id = public.get_user_department_id()
            AND current_authority_level_id = (SELECT authority_level_id FROM public.profiles WHERE id = auth.uid())
            AND (assigned_authority_id = auth.uid() OR assigned_authority_id IS NULL)
            AND status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')
            AND is_cutoff_paused = false
        )
    );

-- ------------------------------------------------------------------------------
-- 2. CANONICAL FORWARDING RPC WITH STRICT TIER & OWNERSHIP VALIDATION
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forward_grievance_to_next_tier(
    p_complaint_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_profile RECORD;
    v_complaint RECORD;
    v_current_level_num INT;
    v_next_level RECORD;
    v_next_authority RECORD;
    v_now TIMESTAMPTZ;
    v_new_deadline TIMESTAMPTZ;
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

    -- 2. Validate Reason Length
    IF p_reason IS NULL OR length(trim(p_reason)) < 5 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'INVALID_REASON',
            'message', 'A formal forwarding justification (minimum 5 characters) is required.'
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

    -- 4. Scope, Tier & Ownership Authorization Checks
    IF v_caller_profile.role != 'admin' THEN
        -- Department isolation check
        IF v_complaint.department_id != v_caller_profile.department_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'DEPT_ACCESS_DENIED',
                'message', 'Access denied: You are not authorized to forward grievances for ' || v_complaint.dept_name || '.'
            );
        END IF;

        -- Tier isolation check: Caller MUST belong to the grievance's current tier
        IF v_caller_profile.authority_level_id IS DISTINCT FROM v_complaint.current_authority_level_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'TIER_MISMATCH',
                'message', 'Access denied: Grievance is at ' || v_complaint.current_level_title || '. Only the current tier authority may forward it.'
            );
        END IF;

        -- Personal ownership check: If assigned, only the assigned authority can forward
        IF v_complaint.assigned_authority_id IS NOT NULL AND v_complaint.assigned_authority_id != v_caller_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'NOT_CURRENT_OWNER',
                'message', 'Access denied: Grievance is currently assigned to another authority.'
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

    IF v_complaint.status = 'CUTOFF_PAUSED' OR v_complaint.is_cutoff_paused THEN
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
            'message', 'Cannot forward: No Level ' || v_next_level.level_number || ' authority is configured for ' || v_complaint.dept_name || '.'
        );
    END IF;

    -- 8. Compute Next Tier Deadline
    v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;

    -- 9. Atomically Update Complaint (previous authority loses ownership immediately)
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
        created_at,
        escalated_at
    ) VALUES (
        p_complaint_id,
        v_complaint.current_authority_level_id,
        v_next_level.id,
        v_caller_id,
        false,
        trim(p_reason),
        GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT),
        v_now,
        v_now
    );

    -- 11. Insert Authoritative complaint_status_history row with complete actor and destination details
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
        p_complaint_id,
        v_caller_id,
        v_caller_id,
        v_caller_profile.full_name,
        'authority',
        v_complaint.department_id,
        v_complaint.dept_name,
        v_current_level_num,
        v_caller_profile.designation,
        'FORWARDED',
        false,
        v_complaint.status,
        'ESCALATED',
        trim(p_reason),
        v_next_level.title,
        v_next_authority.full_name,
        v_now
    );

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

    -- 13. Audit Log
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
-- 3. DEDUPLICATION IN STATUS HISTORY TRIGGER
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
    -- Ignore no-op updates where status and authority level did NOT change
    IF TG_OP != 'INSERT' 
       AND OLD.status IS NOT DISTINCT FROM NEW.status 
       AND OLD.current_authority_level_id IS NOT DISTINCT FROM NEW.current_authority_level_id THEN
        RETURN NEW;
    END IF;

    -- Avoid duplicate UNDER_REVIEW events if already UNDER_REVIEW
    IF TG_OP != 'INSERT' AND OLD.status = 'UNDER_REVIEW' AND NEW.status = 'UNDER_REVIEW' THEN
        RETURN NEW;
    END IF;

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

    -- Check if an identical or RPC-inserted status history event was already recorded within the last 5 seconds
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

    -- Identify Actor & Event Type
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
            v_name := 'Authorized Officer';
            v_role := 'authority';
        END IF;
    END IF;

    -- Insert authoritative status history snapshot
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
        OLD.status,
        NEW.status,
        v_remarks,
        v_assigned_tier,
        v_assigned_name,
        v_now
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 4. IDEMPOTENT AUTOMATED SLA ESCALATION WORKER
-- ------------------------------------------------------------------------------
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
    -- Only grievances whose current tier deadline has passed, and which have not been manually forwarded or resolved
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
        -- Find next level
        SELECT id, level_number, title, sla_days INTO v_next_level
        FROM public.authority_levels
        WHERE level_number = v_complaint.current_level_number + 1;

        IF v_next_level.id IS NOT NULL THEN
            -- Check if next authority exists in the department
            SELECT id, full_name INTO v_next_authority
            FROM public.profiles
            WHERE department_id = v_complaint.department_id
              AND authority_level_id = v_next_level.id
              AND role IN ('authority', 'admin')
            LIMIT 1;

            -- Only proceed with escalation if a destination authority/tier is configured
            IF v_next_authority.id IS NOT NULL THEN
                v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;

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
                    created_at,
                    escalated_at
                ) VALUES (
                    v_complaint.id,
                    v_complaint.current_authority_level_id,
                    v_next_level.id,
                    NULL,
                    true,
                    'Level ' || v_complaint.current_level_number || ' SLA exceeded without resolution.',
                    GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT),
                    v_now,
                    v_now
                );

                -- Audit log
                INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
                VALUES (
                    NULL,
                    'AUTOMATED_SLA_ESCALATION',
                    'complaints',
                    v_complaint.id,
                    jsonb_build_object(
                        'tracking_number', v_complaint.tracking_number,
                        'from_level', v_complaint.current_level_number,
                        'to_level', v_next_level.level_number,
                        'assigned_authority_name', v_next_authority.full_name
                    ),
                    v_now
                );

                -- Notifications
                INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
                VALUES (
                    v_complaint.student_id,
                    v_complaint.id,
                    'Automated Grievance Escalation',
                    'Your grievance ' || v_complaint.tracking_number || ' has been automatically forwarded to ' || v_next_authority.full_name || ' (' || v_next_level.title || ') due to SLA expiration.',
                    'ESCALATION',
                    v_now
                );

                INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
                VALUES (
                    v_next_authority.id,
                    v_complaint.id,
                    'Escalated Grievance Assigned to You',
                    'Grievance ' || v_complaint.tracking_number || ' has been automatically escalated to your queue due to lower-tier SLA breach.',
                    'ESCALATION',
                    v_now
                );

                v_escalated_count := v_escalated_count + 1;
            END IF;
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

-- ------------------------------------------------------------------------------
-- 5. CLEAN UP HISTORICAL DUPLICATE SYSTEM ESCALATION ON SMT-2026-01074
-- ------------------------------------------------------------------------------
DELETE FROM public.complaint_status_history
WHERE id = '96dc1f0a-586b-4979-b06e-953ad8cc19f9';

-- Ensure SMT-2026-01074 is cleanly set to Level 2, assigned to Dr. Radhika Sharma
UPDATE public.complaints
SET current_authority_level_id = (SELECT id FROM public.authority_levels WHERE level_number = 2),
    assigned_authority_id = 'fe2a30f6-3aa1-47ad-8a88-9d46f537d9c4',
    status = 'UNDER_REVIEW',
    status_remarks = 'Case under formal review by Dr. Radhika Sharma (Level 2: Head of Department (HoD)).',
    updated_at = timezone('utc'::text, now())
WHERE tracking_number = 'SMT-2026-01074';
