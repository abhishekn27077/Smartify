-- ==============================================================================
-- SMARTIFY — MIGRATION: TRANSACTIONAL GRIEVANCE FORWARDING RPC & RLS REPAIR
-- Migration File: 20261019000001_fix_grievance_forwarding_rpc.sql
-- ==============================================================================

-- 1. Restore Clean & Secure RLS on public.complaints
DROP POLICY IF EXISTS "Students can view only their own complaints" ON public.complaints;
CREATE POLICY "Students can view only their own complaints"
    ON public.complaints FOR SELECT
    TO authenticated
    USING (
        student_id = auth.uid()
        OR (
            public.is_authority() AND (
                department_id = public.get_user_department_id()
                OR assigned_authority_id = auth.uid()
                OR public.is_admin()
            )
        )
    );

DROP POLICY IF EXISTS "Complaint update policy" ON public.complaints;
CREATE POLICY "Complaint update policy"
    ON public.complaints FOR UPDATE
    TO authenticated
    USING (
        (student_id = auth.uid() AND status = 'PENDING')
        OR (
            public.is_authority() AND (
                department_id = public.get_user_department_id()
                OR assigned_authority_id = auth.uid()
                OR public.is_admin()
            )
        )
    )
    WITH CHECK (
        (student_id = auth.uid() AND status = 'PENDING')
        OR (
            public.is_authority() AND (
                department_id = public.get_user_department_id()
                OR assigned_authority_id = auth.uid()
                OR public.is_admin()
            )
        )
    );

-- 2. Server-Authoritative Transactional Forwarding RPC
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
        RAISE EXCEPTION 'Authentication required to forward grievances';
    END IF;

    -- Fetch caller profile
    SELECT id, full_name, role, department_id, authority_level_id, designation
    INTO v_caller_profile
    FROM public.profiles
    WHERE id = v_caller_id;

    IF NOT FOUND OR v_caller_profile.role NOT IN ('authority', 'admin') THEN
        RAISE EXCEPTION 'Only authorized authorities or administrators can forward grievances';
    END IF;

    -- 2. Validate Forwarding Justification
    IF p_reason IS NULL OR length(trim(p_reason)) < 5 THEN
        RAISE EXCEPTION 'A forwarding justification of at least 5 characters is mandatory';
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
        RAISE EXCEPTION 'Grievance % not found', p_complaint_id;
    END IF;

    -- 4. Scope & Department Authorization Check
    IF v_caller_profile.role != 'admin' THEN
        IF v_complaint.department_id != v_caller_profile.department_id
           AND (v_complaint.assigned_authority_id IS DISTINCT FROM v_caller_id) THEN
            RAISE EXCEPTION 'Access denied: You are not authorized to forward grievances for %', v_complaint.dept_name;
        END IF;
    END IF;

    -- 5. Status Transition Checks
    IF v_complaint.status IN ('RESOLVED', 'REJECTED') THEN
        RAISE EXCEPTION 'Cannot forward: Grievance % is in terminal state %', v_complaint.tracking_number, v_complaint.status;
    END IF;

    IF v_complaint.status = 'CUTOFF_PAUSED' THEN
        RAISE EXCEPTION 'Cannot forward: Grievance % is under 20-day cutoff freeze. Requires administrative resumption.', v_complaint.tracking_number;
    END IF;

    -- 6. Resolve Next Authority Tier
    v_current_level_num := v_complaint.current_level_number;
    IF v_current_level_num >= 4 THEN
        RAISE EXCEPTION 'Cannot forward: Grievance % is already at the highest authority level (Level %)', v_complaint.tracking_number, v_current_level_num;
    END IF;

    SELECT id, level_number, title, sla_days
    INTO v_next_level
    FROM public.authority_levels
    WHERE level_number = v_current_level_num + 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Next authority tier Level % is not configured in the system', v_current_level_num + 1;
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
        RAISE EXCEPTION 'No active Level % authority configured for %', v_next_level.level_number, v_complaint.dept_name;
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
      AND created_at >= (v_now - INTERVAL '3 seconds');

    -- 12. Create In-App Notifications
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

    -- 14. Return Result Object
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
