-- ==============================================================================
-- SMARTIFY MIGRATION: 20261020000003_fix_complaint_update_rls_and_atomic_action_rpc.sql
-- 
-- 1. Corrects the 'Complaint update policy' RLS WITH CHECK clause on public.complaints:
--    The previous policy erroneously included `status NOT IN ('RESOLVED', 'REJECTED')`
--    inside the WITH CHECK condition. Because WITH CHECK evaluates the NEW resulting row,
--    updating a complaint to RESOLVED or REJECTED was systematically rejected with RLS 42501.
--    This migration fixes the WITH CHECK clause while preserving 100% of student,
--    department, tier, and personal ownership isolation boundaries.
--
-- 2. Introduces public.authority_update_grievance_status:
--    A secure, transactional, atomic RPC for UNDER_REVIEW, RESOLVE, and REJECT actions.
--    - Fixed search_path = public
--    - Derives caller identity strictly from auth.uid()
--    - Server-authoritative validation of authority role, department, tier, and ownership
--    - Atomic complaint update, resolution notes, and student notification
--    - Automatic immutable audit logging via existing trg_log_complaint_status_change
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
        -- 2. Department matches complaint department (Department isolation)
        -- 3. Authority tier matches complaint current tier (Tier isolation; previous authorities locked out)
        -- 4. Case is assigned to caller OR is unassigned in their department tier queue (Ownership isolation)
        -- 5. Case is not already terminal (RESOLVED / REJECTED)
        -- 6. Case is not frozen by 20-day cutoff policy (CUTOFF_PAUSED)
        OR (
            public.is_authority()
            AND department_id = public.get_user_department_id()
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
            -- Department cannot be tampered with by the authority
            AND department_id = public.get_user_department_id()
            -- Assigned authority must be either the caller or preserved
            AND (assigned_authority_id = auth.uid() OR assigned_authority_id IS NULL)
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
-- 2. CANONICAL ATOMIC GRIEVANCE STATUS ACTION RPC
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
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_profile RECORD;
    v_complaint RECORD;
    v_now TIMESTAMPTZ;
    v_target_status complaint_status;
    v_action_upper TEXT;
    v_notes TEXT;
BEGIN
    v_now := timezone('utc'::text, now());
    v_caller_id := auth.uid();
    v_action_upper := upper(trim(COALESCE(p_action, '')));

    -- 1. Authentication Check
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'AUTH_REQUIRED',
            'message', 'Authentication required to update grievance status.'
        );
    END IF;

    -- Fetch caller profile from database (never trust client-supplied identity)
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

    -- 2. Row Lock Complaint for Update
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
        -- Department isolation check
        IF v_complaint.department_id != v_caller_profile.department_id THEN
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
        -- Idempotency: If already Under Review and assigned to caller, return success
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
            'error_code', 'INVALID_ACTION',
            'message', 'Unsupported redressal action: ' || p_action
        );
    END IF;

    -- 6. Trigger Student Notification
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

GRANT EXECUTE ON FUNCTION public.authority_update_grievance_status(UUID, TEXT, TEXT, TEXT) TO authenticated;
