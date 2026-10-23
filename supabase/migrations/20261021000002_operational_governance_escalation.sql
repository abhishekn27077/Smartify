-- ==============================================================================
-- SMARTIFY MIGRATION 016: OPERATIONAL GOVERNANCE ESCALATION & DEDUPLICATION
-- Description:
-- 1. Updates forward_grievance_to_next_tier for Operational Departments
--    (HOSTEL, IT, FIN, INFRA) to escalate directly to Level 4 Governance & Admin Review
--    without requiring nonexistent Level 2/3 authorities.
-- 2. Preserves 100% 3-tier academic forwarding for MCA, MBA, MCOM, ACAD.
-- 3. Hardens send_deduped_notification against duplicate unread alerts.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. HARDEN send_deduped_notification TO PREVENT DUPLICATE UNREAD ALERTS
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_deduped_notification(
    p_user_id UUID,
    p_complaint_id UUID,
    p_type notification_type,
    p_title TEXT,
    p_message TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_existing_id UUID;
    v_new_id UUID;
BEGIN
    -- Check if an unread notification with identical title and complaint already exists for this user
    SELECT id INTO v_existing_id
    FROM public.notifications
    WHERE user_id = p_user_id
      AND (complaint_id = p_complaint_id OR (complaint_id IS NULL AND p_complaint_id IS NULL))
      AND title = p_title
      AND is_read = false
    LIMIT 1;

    IF FOUND THEN
        -- Refresh existing unread notification message and timestamp without cluttering with duplicate rows
        UPDATE public.notifications
        SET message = p_message,
            created_at = timezone('utc'::text, now())
        WHERE id = v_existing_id;
        RETURN v_existing_id;
    END IF;

    -- Insert new notification
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        title,
        message,
        notification_type,
        is_read,
        created_at
    ) VALUES (
        p_user_id,
        p_complaint_id,
        p_title,
        p_message,
        p_type,
        false,
        timezone('utc'::text, now())
    ) RETURNING id INTO v_new_id;

    RETURN v_new_id;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- Also support 6-arg signature cleanly
CREATE OR REPLACE FUNCTION public.send_deduped_notification(
    p_user_id UUID,
    p_complaint_id UUID,
    p_title TEXT,
    p_message TEXT,
    p_type notification_type,
    p_window_minutes INT DEFAULT 60
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
    RETURN public.send_deduped_notification(p_user_id, p_complaint_id, p_type, p_title, p_message);
END;
$$;

-- ------------------------------------------------------------------------------
-- 2. CANONICAL FORWARDING RPC WITH OPERATIONAL GOVERNANCE BRANCHING
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
    v_next_authority_id UUID := NULL;
    v_next_authority_name TEXT := 'Higher Authority Tier';
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_new_deadline TIMESTAMPTZ;
    v_tier_days INT;
    v_is_operational BOOLEAN := false;
    v_admin RECORD;
BEGIN
    -- 1. Identify Caller
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNAUTHENTICATED',
            'message', 'Authentication required to forward grievances.'
        );
    END IF;

    SELECT id, role, authority_level_id, department_id, full_name, email
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
        -- Department isolation check (skip for campus-wide authorities with department_id IS NULL)
        IF v_caller_profile.department_id IS NOT NULL AND v_complaint.department_id != v_caller_profile.department_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'DEPT_ACCESS_DENIED',
                'message', 'Access denied: You are not authorized to forward grievances for ' || v_complaint.dept_name || '.'
            );
        END IF;

        -- Tier isolation check: Caller MUST belong to the grievance''s current tier
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

    -- 6. Resolve Next Authority Tier & Target
    v_current_level_num := v_complaint.current_level_number;
    IF v_current_level_num >= 4 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'MAX_TIER_REACHED',
            'message', 'Cannot forward: Grievance ' || v_complaint.tracking_number || ' is already at the highest authority level (Level ' || v_current_level_num || ').'
        );
    END IF;

    -- Check if complaint belongs to an Operational Department with single responsible authority (Level 1)
    IF v_complaint.dept_code IN ('HOSTEL', 'IT', 'FIN', 'INFRA') THEN
        v_is_operational := true;

        -- Operational complaints route directly to Apex Governance / Admin Review (Level 4)
        SELECT id, level_number, title, sla_days
        INTO v_next_level
        FROM public.authority_levels
        WHERE level_number = 4;

        -- Unassigned in the Governance / Admin review queue
        v_next_authority_id := NULL;
        v_next_authority_name := 'Institutional Governance & Admin Review';
    ELSE
        -- Academic departments (MCA, MBA, MCOM, ACAD): Standard sequential progression (L1 -> L2 -> L3 -> L4)
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

        -- Query Next Active Academic Authority
        SELECT p.id, p.full_name, p.email, p.designation
        INTO v_next_authority
        FROM public.profiles p
        WHERE (p.department_id = v_complaint.department_id OR p.department_id IS NULL)
          AND p.authority_level_id = v_next_level.id
          AND p.role IN ('authority', 'admin')
        ORDER BY (p.department_id = v_complaint.department_id) DESC, (p.role = 'authority') DESC
        LIMIT 1;

        IF FOUND THEN
            v_next_authority_id := v_next_authority.id;
            v_next_authority_name := v_next_authority.full_name;
        ELSE
            IF v_next_level.level_number = 4 THEN
                v_next_authority_id := NULL;
                v_next_authority_name := 'Campus Ombudsman Board';
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'error_code', 'NO_ELIGIBLE_AUTHORITY',
                    'message', 'Cannot forward: No Level ' || v_next_level.level_number || ' authority is configured for ' || v_complaint.dept_name || '.'
                );
            END IF;
        END IF;
    END IF;

    -- 7. Compute Next Tier Deadline & Days Spent
    v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;
    v_tier_days := GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT);

    -- 8. Atomically Update Complaint (previous authority loses ownership immediately)
    UPDATE public.complaints
    SET 
        current_authority_level_id = v_next_level.id,
        assigned_authority_id = v_next_authority_id,
        status = 'ESCALATED',
        status_remarks = CASE 
            WHEN v_is_operational THEN 'Escalated to Institutional Governance & Admin Review. Reason: ' || trim(p_reason)
            ELSE 'Forwarded to ' || v_next_level.title || '. Reason: ' || trim(p_reason)
        END,
        current_tier_deadline = v_new_deadline,
        updated_at = v_now
    WHERE id = p_complaint_id;

    -- 9. Record in complaint_escalations using CANONICAL columns
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
        v_tier_days,
        v_now,
        v_now
    );

    -- 10. Create Student Notification
    PERFORM public.send_deduped_notification(
        v_complaint.student_id,
        p_complaint_id,
        'ESCALATION'::notification_type,
        CASE 
            WHEN v_is_operational THEN 'Grievance Escalated to Governance — ' || v_complaint.tracking_number
            ELSE 'Grievance Forwarded — ' || v_complaint.tracking_number
        END,
        CASE
            WHEN v_is_operational THEN 'Your grievance has been escalated to Institutional Governance & Admin Review for resolution.'
            ELSE 'Your grievance has been escalated to ' || v_next_level.title || ' (' || v_next_authority_name || ') for higher-tier review.'
        END
    );

    -- 11. Create In-App Notification for Next Authority or Administrators
    IF v_next_authority_id IS NOT NULL THEN
        PERFORM public.send_deduped_notification(
            v_next_authority_id,
            p_complaint_id,
            'ESCALATION'::notification_type,
            'New Case Escalated — ' || v_complaint.tracking_number,
            'Case forwarded by ' || COALESCE(v_caller_profile.full_name, 'Previous Tier') || ': ' || trim(p_reason)
        );
    ELSIF v_is_operational THEN
        -- Notify all Administrators about operational grievance escalation
        FOR v_admin IN 
            SELECT id FROM public.profiles WHERE role = 'admin'
        LOOP
            PERFORM public.send_deduped_notification(
                v_admin.id,
                p_complaint_id,
                'ESCALATION'::notification_type,
                'Operational Case Escalated to Governance — ' || v_complaint.tracking_number,
                v_complaint.dept_name || ' case escalated to Governance by ' || COALESCE(v_caller_profile.full_name, 'Authority') || ': ' || trim(p_reason)
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'from_level_number', v_current_level_num,
        'to_level_number', v_next_level.level_number,
        'to_level_title', v_next_level.title,
        'assigned_authority_id', v_next_authority_id,
        'assigned_authority_name', v_next_authority_name,
        'department_name', v_complaint.dept_name,
        'is_governance_escalation', v_is_operational,
        'message', CASE 
            WHEN v_is_operational THEN 'Grievance ' || v_complaint.tracking_number || ' successfully escalated to Institutional Governance & Admin Review.'
            ELSE 'Grievance ' || v_complaint.tracking_number || ' successfully forwarded to ' || v_next_authority_name || ' (' || v_next_level.title || ').'
        END
    );
END;
$$;
