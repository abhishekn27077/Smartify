-- ==============================================================================
-- SMARTIFY — MIGRATION 20261023000002
-- ESCALATION, L1 ACCOUNTABILITY, 20-DAY CUTOFF & GOVERNANCE ENFORCEMENT
-- ==============================================================================
--
-- Core Invariants:
-- 1. L1 faculty cannot ignore a student indefinitely:
--    If unclaimed or unacted within the L1 SLA window, execute_sla_escalations()
--    automatically advances the grievance to Level 2 with:
--    "Level 1 authority did not accept the grievance within the Level 1 action window."
--    "By: System Redressal Engine (AUTOMATED)".
-- 2. Explicit Claiming / Acceptance Workflow:
--    Grievances at any tier (L1 or escalated L2/L3) must be explicitly claimed/accepted
--    before any triage actions (Resolve, Reject, Forward) are permitted.
-- 3. Strict L1 Rejection Policy:
--    Level 1 authorities are strictly prohibited from rejecting grievances.
--    Genuine grievances must be resolved or forwarded to Level 2.
--    Rejection is only permitted for Level >= 2 with mandatory justification (min 5 chars).
-- 4. Admin Role Separation:
--    Admin is a governance/audit role and cannot claim or review grievances as an authority.
-- 5. Tier & Department Scoping:
--    Authorities can only accept and act on grievances within their assigned department and tier.
--    When forwarded or escalated, the previous authority loses ownership immediately.
-- 6. 20-Day Cutoff Governance:
--    Freezes automated progression without altering historical records.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CLAIM GRIEVANCE RPC (Atomic Case Acceptance)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_grievance(
    p_complaint_id UUID
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
    v_now TIMESTAMPTZ;
BEGIN
    v_now := timezone('utc'::text, now());
    v_caller_id := auth.uid();

    -- 1. Authentication Check
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'AUTH_REQUIRED',
            'message', 'Authentication required to accept grievances.'
        );
    END IF;

    -- Fetch caller profile
    SELECT id, full_name, role, department_id, authority_level_id, designation
    INTO v_caller_profile
    FROM public.profiles
    WHERE id = v_caller_id;

    -- Admin is a governance role, NOT a grievance reviewer
    IF NOT FOUND OR v_caller_profile.role != 'authority' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'Only departmental authorities can accept grievances. Administrative review is governance-only.'
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

    -- 3. Scope & Department Authorization Check
    IF v_caller_profile.department_id IS NOT NULL AND v_complaint.department_id != v_caller_profile.department_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'DEPT_ACCESS_DENIED',
            'message', 'Access denied: You are not authorized to accept grievances for ' || v_complaint.dept_name || '.'
        );
    END IF;

    -- Tier isolation check: Caller MUST belong to the grievance's active tier
    IF v_caller_profile.authority_level_id IS NOT NULL 
       AND v_complaint.current_authority_level_id != v_caller_profile.authority_level_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'LEVEL_MISMATCH',
            'message', 'Access denied: Grievance is at ' || v_complaint.current_level_title || ', but your assigned tier differs.'
        );
    END IF;

    -- 4. Status Checks
    IF v_complaint.status IN ('RESOLVED', 'REJECTED') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'TERMINAL_STATE',
            'message', 'Cannot accept: Grievance ' || v_complaint.tracking_number || ' is already ' || v_complaint.status::TEXT || '.'
        );
    END IF;

    IF v_complaint.status = 'CUTOFF_PAUSED' OR v_complaint.is_cutoff_paused THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'CUTOFF_PAUSED',
            'message', 'Cannot accept: Grievance ' || v_complaint.tracking_number || ' is under 20-day cutoff freeze. Requires administrative review.'
        );
    END IF;

    -- Already claimed by another authority check
    IF v_complaint.status = 'UNDER_REVIEW' 
       AND v_complaint.assigned_authority_id IS NOT NULL 
       AND v_complaint.assigned_authority_id != v_caller_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'ALREADY_ASSIGNED',
            'message', 'This grievance has already been accepted by another authority in your department.'
        );
    END IF;

    -- Already claimed by caller
    IF v_complaint.status = 'UNDER_REVIEW' AND v_complaint.assigned_authority_id = v_caller_id THEN
        RETURN jsonb_build_object(
            'success', true,
            'complaint_id', p_complaint_id,
            'tracking_number', v_complaint.tracking_number,
            'message', 'Grievance is already accepted and under review by you.'
        );
    END IF;

    -- 5. Atomically Assign Complaint and Move to UNDER_REVIEW
    UPDATE public.complaints
    SET 
        assigned_authority_id = v_caller_id,
        status = 'UNDER_REVIEW',
        status_remarks = 'Case accepted by ' || v_caller_profile.full_name || ' (' || COALESCE(v_caller_profile.designation, v_complaint.current_level_title) || ').',
        updated_at = v_now
    WHERE id = p_complaint_id;

    -- 6. Insert Authoritative Timeline Record
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
        v_complaint.current_level_number,
        v_caller_profile.designation,
        'UNDER_REVIEW',
        false,
        v_complaint.status,
        'UNDER_REVIEW',
        'Case accepted by ' || v_caller_profile.full_name || ' (' || COALESCE(v_caller_profile.designation, v_complaint.current_level_title) || ').',
        v_complaint.current_level_title,
        v_caller_profile.full_name,
        v_now
    );

    -- 7. Notify Student
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
        'Grievance Accepted by Authority',
        'Your grievance ' || v_complaint.tracking_number || ' has been accepted and is now under review by ' || v_caller_profile.full_name || ' (' || COALESCE(v_caller_profile.designation, v_complaint.current_level_title) || ').',
        'STATUS_CHANGE',
        false,
        v_now
    );

    -- 8. Audit Log
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
    VALUES (
        v_caller_id,
        'AUTHORITY_CASE_CLAIM',
        'complaints',
        p_complaint_id,
        jsonb_build_object(
            'tracking_number', v_complaint.tracking_number,
            'authority_name', v_caller_profile.full_name,
            'tier', v_complaint.current_level_title
        ),
        v_now
    );

    RETURN jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'message', 'Grievance ' || v_complaint.tracking_number || ' successfully accepted. You are now assigned to this case.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 2. AUTHORITY UPDATE GRIEVANCE STATUS RPC (With L1 Rejection Prohibition)
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

    -- Only authorities can triage grievances
    IF NOT FOUND OR v_caller_profile.role != 'authority' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'Only departmental authorities can perform redressal actions.'
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

    -- Case must be accepted first
    IF v_complaint.status IN ('PENDING', 'ESCALATED') AND v_action_upper NOT IN ('UNDER_REVIEW', 'CLAIM') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'NOT_YET_ACCEPTED',
            'message', 'Please accept/claim this case before performing redressal actions.'
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
        -- Level 1 authorities are strictly prohibited from rejecting grievances
        IF v_complaint.current_level_number = 1 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'L1_REJECT_PROHIBITED',
                'message', 'Level 1 authorities cannot reject grievances. Genuine cases must be resolved or forwarded to Level 2.'
            );
        END IF;

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

-- ------------------------------------------------------------------------------
-- 3. FORWARD GRIEVANCE TO NEXT TIER RPC
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
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_new_deadline TIMESTAMPTZ;
    v_tier_days INT;
    v_is_operational BOOLEAN := false;
    v_admin RECORD;
    v_next_auth RECORD;
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

    SELECT id, role, authority_level_id, department_id, full_name, email, designation
    INTO v_caller_profile
    FROM public.profiles
    WHERE id = v_caller_id;

    IF NOT FOUND OR v_caller_profile.role != 'authority' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'Only departmental authorities can forward grievances.'
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
            'message', 'Cannot forward: Grievance ' || v_complaint.tracking_number || ' is under 20-day cutoff freeze. Requires administrative review.'
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

    IF v_complaint.dept_code IN ('HOSTEL', 'IT', 'FIN', 'INFRA') THEN
        v_is_operational := true;
        SELECT id, level_number, title, sla_days
        INTO v_next_level
        FROM public.authority_levels
        WHERE level_number = 4;
    ELSE
        SELECT id, level_number, title, sla_days
        INTO v_next_level
        FROM public.authority_levels
        WHERE level_number = v_current_level_num + 1;
    END IF;

    IF v_next_level.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'NEXT_TIER_MISSING',
            'message', 'Next authority tier Level ' || (v_current_level_num + 1) || ' is not configured.'
        );
    END IF;

    -- 7. Compute Next Tier Deadline & Days Spent
    v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;
    v_tier_days := GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT);

    -- 8. Atomically Update Complaint:
    -- Previous authority loses ownership immediately; status is ESCALATED (awaiting acceptance in next tier queue)
    UPDATE public.complaints
    SET 
        current_authority_level_id = v_next_level.id,
        assigned_authority_id = NULL,
        status = 'ESCALATED',
        status_remarks = CASE 
            WHEN v_is_operational THEN 'Escalated to Institutional Governance & Admin Review. Reason: ' || trim(p_reason)
            ELSE 'Forwarded to ' || v_next_level.title || '. Reason: ' || trim(p_reason)
        END,
        current_tier_deadline = v_new_deadline,
        updated_at = v_now
    WHERE id = p_complaint_id;

    -- 9. Record in complaint_escalations
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

    -- 10. Notifications
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        notification_type,
        title,
        message,
        is_read,
        created_at
    ) VALUES (
        v_complaint.student_id,
        p_complaint_id,
        'ESCALATION'::notification_type,
        'Grievance Forwarded — ' || v_complaint.tracking_number,
        CASE 
            WHEN v_is_operational THEN 'Your grievance has been escalated to Institutional Governance & Admin Review.'
            ELSE 'Your grievance has been forwarded to ' || v_next_level.title || ' for higher-tier review.'
        END,
        false,
        v_now
    );

    -- Notify next tier authorities in this department
    FOR v_next_auth IN
        SELECT id FROM public.profiles
        WHERE department_id = v_complaint.department_id
          AND authority_level_id = v_next_level.id
          AND role = 'authority'
    LOOP
        INSERT INTO public.notifications (
            user_id,
            complaint_id,
            notification_type,
            title,
            message,
            is_read,
            created_at
        ) VALUES (
            v_next_auth.id,
            p_complaint_id,
            'ESCALATION'::notification_type,
            'New Escalated Case in Queue — ' || v_complaint.tracking_number,
            'Grievance forwarded from ' || v_complaint.current_level_title || ' by ' || v_caller_profile.full_name || ': ' || trim(p_reason),
            false,
            v_now
        );
    END LOOP;

    -- If operational, also notify campus administrators
    IF v_is_operational THEN
        FOR v_admin IN SELECT id FROM public.profiles WHERE role = 'admin' LOOP
            INSERT INTO public.notifications (
                user_id,
                complaint_id,
                notification_type,
                title,
                message,
                is_read,
                created_at
            ) VALUES (
                v_admin.id,
                p_complaint_id,
                'ESCALATION'::notification_type,
                'Operational Case Escalated to Governance — ' || v_complaint.tracking_number,
                v_complaint.dept_name || ' case escalated to Governance by ' || v_caller_profile.full_name || ': ' || trim(p_reason),
                false,
                v_now
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'from_level', v_complaint.current_level_title,
        'to_level', v_next_level.title,
        'is_governance_escalation', v_is_operational,
        'message', 'Grievance ' || v_complaint.tracking_number || ' forwarded to ' || v_next_level.title || '.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. EXECUTE SLA ESCALATIONS ENGINE (Automated L1 Timeout -> L2 Escalation)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.execute_sla_escalations()
RETURNS JSONB AS $$
DECLARE
    v_complaint RECORD;
    v_next_level RECORD;
    v_now TIMESTAMPTZ;
    v_new_deadline TIMESTAMPTZ;
    v_escalated_count INT := 0;
    v_paused_count INT := 0;
    v_reason TEXT;
    v_next_auth RECORD;
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
               c.current_authority_level_id, c.updated_at, c.created_at,
               d.code AS dept_code, d.name AS dept_name,
               al.level_number AS current_level_number,
               al.title AS current_level_title
        FROM public.complaints c
        JOIN public.departments d ON c.department_id = d.id
        JOIN public.authority_levels al ON c.current_authority_level_id = al.id
        WHERE v_now >= c.current_tier_deadline
          AND c.status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')
          AND c.is_cutoff_paused = false
          AND al.level_number < 4
        ORDER BY c.current_tier_deadline ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        -- Determine Next Tier (Operational goes to L4, Academic goes to current + 1)
        IF v_complaint.dept_code IN ('HOSTEL', 'IT', 'FIN', 'INFRA') THEN
            SELECT id, level_number, title, sla_days INTO v_next_level
            FROM public.authority_levels
            WHERE level_number = 4;
        ELSE
            SELECT id, level_number, title, sla_days INTO v_next_level
            FROM public.authority_levels
            WHERE level_number = v_complaint.current_level_number + 1;
        END IF;

        IF v_next_level.id IS NOT NULL THEN
            v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;

            -- Exact automated escalation reason
            IF v_complaint.current_level_number = 1 THEN
                v_reason := 'Level 1 authority did not accept the grievance within the Level 1 action window.';
            ELSE
                v_reason := 'Level ' || v_complaint.current_level_number || ' action deadline exceeded without resolution.';
            END IF;

            -- Atomically escalate complaint into next tier queue
            UPDATE public.complaints
            SET current_authority_level_id = v_next_level.id,
                assigned_authority_id = NULL,
                status = 'ESCALATED',
                status_remarks = v_reason,
                current_tier_deadline = v_new_deadline,
                updated_at = v_now
            WHERE id = v_complaint.id;

            -- Record in canonical complaint_escalations table
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
                v_reason,
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
                    'reason', v_reason
                ),
                v_now
            );

            -- Student Notification
            INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
            VALUES (
                v_complaint.student_id,
                v_complaint.id,
                'Automated Escalation',
                'Your grievance ' || v_complaint.tracking_number || ' has been automatically forwarded to ' || v_next_level.title || ' because the Level ' || v_complaint.current_level_number || ' action deadline expired.',
                'ESCALATION',
                v_now
            );

            -- Next Tier Authorities Notification
            FOR v_next_auth IN
                SELECT id FROM public.profiles
                WHERE department_id = v_complaint.department_id
                  AND authority_level_id = v_next_level.id
                  AND role = 'authority'
            LOOP
                INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
                VALUES (
                    v_next_auth.id,
                    v_complaint.id,
                    'Escalated Grievance in Queue',
                    'Grievance ' || v_complaint.tracking_number || ' has been automatically escalated to your queue due to Level ' || v_complaint.current_level_number || ' SLA expiration.',
                    'ESCALATION',
                    v_now
                );
            END LOOP;

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

-- ------------------------------------------------------------------------------
-- 5. PERMISSIONS
-- ------------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.claim_grievance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.authority_update_grievance_status(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.forward_grievance_to_next_tier(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.execute_sla_escalations() TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 6. TRIGGER FUNCTION SYNCHRONIZATION (Queue Claiming & Status Remarks)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_preserve_complaint_authority_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- For PENDING and ESCALATED, complaints are in the unassigned queue awaiting explicit acceptance
    IF NEW.status IN ('PENDING', 'ESCALATED') THEN
        RETURN NEW;
    END IF;

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

    -- Prevent accidental loss of ownership on other updates if already assigned
    IF NEW.assigned_authority_id IS NULL AND OLD.assigned_authority_id IS NOT NULL THEN
        NEW.assigned_authority_id := OLD.assigned_authority_id;
    END IF;

    NEW.updated_at := timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_complaint_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
            v_remarks := COALESCE(NEW.status_remarks, 'Automation paused: Reached 20-calendar-day campus cutoff limit.');
        ELSIF NEW.status = 'ESCALATED' AND v_actor_id IS NULL THEN
            v_remarks := COALESCE(NEW.status_remarks, 'Escalated to next authority tier due to SLA breach.');
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
$$;

