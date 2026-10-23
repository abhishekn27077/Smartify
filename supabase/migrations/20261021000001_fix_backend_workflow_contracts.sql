-- ==============================================================================
-- SMARTIFY CANONICAL MIGRATION: 20261021000001_fix_backend_workflow_contracts.sql
-- 
-- Comprehensive fix for database contracts and RLS:
-- 1. Corrects forward_grievance_to_next_tier RPC:
--    - Uses canonical complaint_escalations columns:
--      (complaint_id, from_level_id, to_level_id, escalated_by, is_automated, reason, tier_days_spent, created_at, escalated_at)
--    - Uses canonical notifications columns:
--      (user_id, complaint_id, title, message, notification_type, is_read, created_at)
--    - Removes references to non-existent complaint_timeline_events table
--    - Atomic state transition with ownership transfer and deadline updates
--
-- 2. Corrects authority_update_grievance_status RPC:
--    - Removes references to non-existent complaint_timeline_events table
--    - Delegates history recording to existing trg_log_complaint_status_change
--    - Uses send_deduped_notification for clean student notification
--    - Idempotent UNDER_REVIEW handling
--
-- 3. Corrects Complaint update policy on public.complaints:
--    - WITH CHECK permits legal target statuses (UNDER_REVIEW, IN_PROGRESS, ESCALATED, RESOLVED, REJECTED)
--    - Department isolation preserved for department-scoped authorities
--    - Campus-wide authority (Level 4 Ombudsman) supported with department_id IS NULL
--    - 20-day cutoff freeze strictly enforced in both USING and WITH CHECK
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. REPAIR COMPLAINTS UPDATE RLS POLICY
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Complaint update policy" ON public.complaints;

CREATE POLICY "Complaint update policy"
    ON public.complaints FOR UPDATE
    TO authenticated
    USING (
        -- Complainant student can only update if still in PENDING status
        (student_id = auth.uid() AND status = 'PENDING'::complaint_status)
        -- Institutional Administrator has governance override
        OR public.is_admin()
        -- Authorized authority can only update if:
        -- 1. Role is authority
        -- 2. Department matches complaint department (OR authority is campus-wide with department_id IS NULL)
        -- 3. Authority tier matches complaint current tier (Tier isolation; previous authorities locked out)
        -- 4. Case is assigned to caller OR is unassigned in their department tier queue (Ownership isolation)
        -- 5. Case is not already terminal (RESOLVED / REJECTED)
        -- 6. Case is not frozen by 20-day cutoff policy (CUTOFF_PAUSED)
        OR (
            public.is_authority()
            AND (department_id = public.get_user_department_id() OR public.get_user_department_id() IS NULL)
            AND current_authority_level_id = (SELECT authority_level_id FROM public.profiles WHERE id = auth.uid())
            AND (assigned_authority_id = auth.uid() OR assigned_authority_id IS NULL)
            AND status NOT IN ('RESOLVED'::complaint_status, 'REJECTED'::complaint_status, 'CUTOFF_PAUSED'::complaint_status)
            AND is_cutoff_paused = false
        )
    )
    WITH CHECK (
        -- Complainant student can only keep their own complaint in PENDING status
        (student_id = auth.uid() AND status = 'PENDING'::complaint_status)
        -- Institutional Administrator allowed
        OR public.is_admin()
        -- Validation on resulting row for authority updates:
        OR (
            public.is_authority()
            -- Department cannot be altered
            AND (department_id = public.get_user_department_id() OR public.get_user_department_id() IS NULL)
            -- 20-day cutoff freeze cannot be bypassed
            AND is_cutoff_paused = false
            -- New status must be a legal active or terminal redressal status (never PENDING or CUTOFF_PAUSED)
            AND status IN (
                'UNDER_REVIEW'::complaint_status,
                'IN_PROGRESS'::complaint_status,
                'ESCALATED'::complaint_status,
                'RESOLVED'::complaint_status,
                'REJECTED'::complaint_status
            )
        )
    );

-- ------------------------------------------------------------------------------
-- 2. CANONICAL FORWARD GRIEVANCE RPC
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
    v_next_authority_name TEXT := 'Department Queue';
    v_now TIMESTAMPTZ;
    v_new_deadline TIMESTAMPTZ;
    v_tier_days INT;
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
        -- Department isolation check (skip for campus-wide authorities with department_id IS NULL)
        IF v_caller_profile.department_id IS NOT NULL AND v_complaint.department_id != v_caller_profile.department_id THEN
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

    -- 7. Query Next Active Authority:
    -- Check for department-specific officer first, or campus-wide officer (e.g. Level 4 Ombudsman)
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
        -- If Level 4 is reached and no specific officer exists, transition to Level 4 Board queue
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

    -- 8. Compute Next Tier Deadline & Days Spent
    v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;
    v_tier_days := GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT);

    -- 9. Atomically Update Complaint (previous authority loses ownership immediately)
    UPDATE public.complaints
    SET 
        current_authority_level_id = v_next_level.id,
        assigned_authority_id = v_next_authority_id,
        status = 'ESCALATED',
        status_remarks = 'Forwarded to ' || v_next_level.title || '. Reason: ' || trim(p_reason),
        current_tier_deadline = v_new_deadline,
        updated_at = v_now
    WHERE id = p_complaint_id;

    -- 10. Record in complaint_escalations using CANONICAL columns
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

    -- 11. Create High-Priority Student Notification using CANONICAL columns
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
        'Grievance Forwarded — ' || v_complaint.tracking_number,
        'Your grievance has been escalated to ' || v_next_level.title || ' (' || v_next_authority_name || ') for higher-tier review.',
        'ESCALATION',
        false,
        v_now
    );

    -- 12. Create In-App Notification for Next Authority (if assigned)
    IF v_next_authority_id IS NOT NULL THEN
        INSERT INTO public.notifications (
            user_id,
            complaint_id,
            title,
            message,
            notification_type,
            is_read,
            created_at
        ) VALUES (
            v_next_authority_id,
            p_complaint_id,
            'New Case Escalated — ' || v_complaint.tracking_number,
            'Case forwarded by ' || COALESCE(v_caller_profile.full_name, 'Previous Tier') || ': ' || trim(p_reason),
            'ESCALATION',
            false,
            v_now
        );
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
        'message', 'Grievance ' || v_complaint.tracking_number || ' successfully forwarded to ' || v_next_authority_name || ' (' || v_next_level.title || ').'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. CANONICAL ATOMIC GRIEVANCE STATUS ACTION RPC
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.authority_update_grievance_status(
    p_complaint_id UUID,
    p_action TEXT,
    p_remarks TEXT,
    p_resolution_notes TEXT DEFAULT NULL
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
    v_action_upper TEXT;
    v_now TIMESTAMPTZ;
    v_target_status complaint_status;
    v_notes TEXT;
BEGIN
    v_now := timezone('utc'::text, now());
    v_caller_id := auth.uid();
    v_action_upper := upper(trim(p_action));

    -- 1. Authentication Check
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'AUTH_REQUIRED',
            'message', 'Authentication required to perform grievance actions.'
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
            'message', 'Only authorized authorities or administrators can update grievances.'
        );
    END IF;

    -- 2. Lock Complaint for Update
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

    -- 3. Scope, Tier & Ownership Authorization Checks
    IF v_caller_profile.role != 'admin' THEN
        -- Department isolation check (skip for campus-wide authorities with department_id IS NULL)
        IF v_caller_profile.department_id IS NOT NULL AND v_complaint.department_id != v_caller_profile.department_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'DEPT_ACCESS_DENIED',
                'message', 'Access denied: You are not authorized for ' || v_complaint.dept_name || '.'
            );
        END IF;

        -- Tier isolation check: Caller MUST belong to the grievance's active tier
        IF v_caller_profile.authority_level_id IS DISTINCT FROM v_complaint.current_authority_level_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'TIER_MISMATCH',
                'message', 'Access denied: Grievance is at ' || v_complaint.current_level_title || '. Only the current tier authority may act.'
            );
        END IF;

        -- Personal ownership check: If assigned, only assigned authority may act
        IF v_complaint.assigned_authority_id IS NOT NULL AND v_complaint.assigned_authority_id != v_caller_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'NOT_CURRENT_OWNER',
                'message', 'Access denied: Grievance is currently assigned to another authority.'
            );
        END IF;
    END IF;

    -- 4. Terminal and Freeze State Checks
    IF v_complaint.status IN ('RESOLVED', 'REJECTED') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'TERMINAL_STATE',
            'message', 'Cannot update: Grievance ' || v_complaint.tracking_number || ' is already ' || v_complaint.status::TEXT || '.'
        );
    END IF;

    IF v_complaint.status = 'CUTOFF_PAUSED' OR v_complaint.is_cutoff_paused THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'CUTOFF_PAUSED',
            'message', 'Cannot update: Grievance ' || v_complaint.tracking_number || ' is under 20-day cutoff freeze. Requires administrative review.'
        );
    END IF;

    -- 5. Process Requested Redressal Action
    IF v_action_upper = 'RESOLVE' THEN
        v_target_status := 'RESOLVED'::complaint_status;
        v_notes := trim(COALESCE(p_resolution_notes, p_remarks, ''));
        IF length(v_notes) < 5 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'INVALID_NOTES',
                'message', 'Resolution notes are mandatory (minimum 5 characters).'
            );
        END IF;

        UPDATE public.complaints
        SET 
            status = v_target_status,
            status_remarks = v_notes,
            resolution_notes = v_notes,
            resolved_at = v_now,
            assigned_authority_id = COALESCE(v_complaint.assigned_authority_id, v_caller_id),
            updated_at = v_now
        WHERE id = p_complaint_id;

    ELSIF v_action_upper = 'REJECT' THEN
        v_target_status := 'REJECTED'::complaint_status;
        v_notes := trim(COALESCE(p_remarks, ''));
        IF length(v_notes) < 5 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'INVALID_REMARKS',
                'message', 'Rejection reason remarks are mandatory (minimum 5 characters).'
            );
        END IF;

        UPDATE public.complaints
        SET 
            status = v_target_status,
            status_remarks = v_notes,
            assigned_authority_id = COALESCE(v_complaint.assigned_authority_id, v_caller_id),
            updated_at = v_now
        WHERE id = p_complaint_id;

    ELSIF v_action_upper IN ('UNDER_REVIEW', 'CLAIM') THEN
        IF v_complaint.status = 'UNDER_REVIEW' AND v_complaint.assigned_authority_id = v_caller_id THEN
            RETURN jsonb_build_object(
                'success', true,
                'complaint_id', p_complaint_id,
                'tracking_number', v_complaint.tracking_number,
                'new_status', 'UNDER_REVIEW',
                'message', 'Grievance is already Under Review and assigned to you.'
            );
        END IF;

        v_target_status := 'UNDER_REVIEW'::complaint_status;
        v_notes := COALESCE(nullif(trim(p_remarks), ''), 'Case accepted for departmental review.');

        UPDATE public.complaints
        SET 
            status = v_target_status,
            status_remarks = v_notes,
            assigned_authority_id = v_caller_id,
            updated_at = v_now
        WHERE id = p_complaint_id;

    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNSUPPORTED_ACTION',
            'message', 'Action ' || p_action || ' is not recognized. Use UNDER_REVIEW, RESOLVE, or REJECT.'
        );
    END IF;

    -- 6. Trigger Student Notification using public.send_deduped_notification
    PERFORM public.send_deduped_notification(
        v_complaint.student_id,
        p_complaint_id,
        'STATUS_CHANGE',
        'Status Updated: ' || v_target_status::TEXT,
        'Your grievance ' || v_complaint.tracking_number || ' has been updated to ' || v_target_status::TEXT || ' by ' || v_caller_profile.full_name || '.'
    );

    RETURN jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'new_status', v_target_status::TEXT,
        'message', 'Grievance ' || v_complaint.tracking_number || ' successfully updated to ' || v_target_status::TEXT || '.'
    );
END;
$$;

-- Permissions
GRANT EXECUTE ON FUNCTION public.forward_grievance_to_next_tier(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.authority_update_grievance_status(UUID, TEXT, TEXT, TEXT) TO authenticated;
