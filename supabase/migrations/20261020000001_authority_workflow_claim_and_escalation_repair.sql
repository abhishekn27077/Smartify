-- ==============================================================================
-- SMARTIFY — ESCALATED AUTHORITY WORKFLOW REPAIR MIGRATION
-- Migration: 20261020000001_authority_workflow_claim_and_escalation_repair.sql
-- 
-- Fixes:
-- 1. Introduces claim_grievance RPC for deterministic case acceptance by authorities.
-- 2. Ensures automatic deterministic assignment for tier escalations when 1 authority exists.
-- 3. Backfills unassigned escalated grievances (like SMT-2026-01074) to their tier authority.
-- 4. Preserves department scoping strictly across all tiers (MCA stays MCA, etc.).
-- ==============================================================================

-- 1. Deterministic Authority Claim RPC
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
    v_result JSONB;
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

    IF NOT FOUND OR v_caller_profile.role NOT IN ('authority', 'admin') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'Only authorized authorities or administrators can accept grievances.'
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
    IF v_caller_profile.role != 'admin' THEN
        IF v_complaint.department_id != v_caller_profile.department_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'DEPT_ACCESS_DENIED',
                'message', 'Access denied: You are not authorized to accept grievances for ' || v_complaint.dept_name || '.'
            );
        END IF;

        IF v_caller_profile.authority_level_id IS NOT NULL 
           AND v_complaint.current_authority_level_id != v_caller_profile.authority_level_id THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_code', 'LEVEL_MISMATCH',
                'message', 'Access denied: Grievance is at ' || v_complaint.current_level_title || ', but your assigned tier differs.'
            );
        END IF;
    END IF;

    -- 4. Status Checks
    IF v_complaint.status IN ('RESOLVED', 'REJECTED') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'TERMINAL_STATE',
            'message', 'Cannot accept: Grievance ' || v_complaint.tracking_number || ' is already ' || v_complaint.status::TEXT || '.'
        );
    END IF;

    IF v_complaint.status = 'CUTOFF_PAUSED' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'CUTOFF_PAUSED',
            'message', 'Cannot accept: Grievance ' || v_complaint.tracking_number || ' is under 20-day cutoff freeze. Requires administrative resumption.'
        );
    END IF;

    -- 5. Atomically Assign Complaint and Move to UNDER_REVIEW
    UPDATE public.complaints
    SET 
        assigned_authority_id = v_caller_id,
        status = 'UNDER_REVIEW',
        status_remarks = 'Case accepted by ' || v_caller_profile.full_name || ' (' || v_caller_profile.designation || ').',
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
        v_caller_profile.role::TEXT,
        v_complaint.department_id,
        v_complaint.dept_name,
        v_complaint.current_level_number,
        v_caller_profile.designation,
        'UNDER_REVIEW',
        false,
        v_complaint.status,
        'UNDER_REVIEW',
        'Case accepted by ' || v_caller_profile.full_name || ' (' || v_caller_profile.designation || ').',
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
        'Your grievance ' || v_complaint.tracking_number || ' has been accepted and is now under review by ' || v_caller_profile.full_name || ' (' || v_caller_profile.designation || ').',
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
            'department', v_complaint.dept_name,
            'tier', v_complaint.current_level_title,
            'authority_name', v_caller_profile.full_name
        ),
        v_now
    );

    -- 9. Return Structured Result
    v_result := jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'assigned_authority_id', v_caller_id,
        'assigned_authority_name', v_caller_profile.full_name,
        'new_status', 'UNDER_REVIEW',
        'message', 'Grievance ' || v_complaint.tracking_number || ' successfully accepted and assigned to you.'
    );

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_grievance(UUID) TO authenticated;

-- 2. Update trigger to automatically assign deterministic single authority on escalation
CREATE OR REPLACE FUNCTION public.fn_preserve_complaint_authority_ownership()
RETURNS TRIGGER AS $$
DECLARE
    v_single_auth RECORD;
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

    -- If a grievance is at a tier and assigned_authority_id is NULL,
    -- deterministically check if exactly ONE active authority exists for (department_id, current_authority_level_id)
    IF NEW.assigned_authority_id IS NULL AND NEW.current_authority_level_id IS NOT NULL THEN
        SELECT p.id INTO v_single_auth
        FROM public.profiles p
        WHERE p.department_id = NEW.department_id
          AND p.authority_level_id = NEW.current_authority_level_id
          AND p.role IN ('authority', 'admin')
        LIMIT 2; -- Check if unique

        -- If exactly one found, deterministic auto-assignment applies
        IF FOUND THEN
            NEW.assigned_authority_id := v_single_auth.id;
        END IF;
    END IF;

    -- Prevent accidental loss of ownership on other updates
    IF NEW.assigned_authority_id IS NULL AND OLD.assigned_authority_id IS NOT NULL AND NEW.status != 'ESCALATED' THEN
        NEW.assigned_authority_id := OLD.assigned_authority_id;
    END IF;

    NEW.updated_at := timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Backfill any active grievances currently lacking assigned authority where a unique authority exists
DO $$
DECLARE
    rec RECORD;
    v_auth_id UUID;
    v_auth_name TEXT;
    v_auth_title TEXT;
BEGIN
    FOR rec IN 
        SELECT c.id, c.tracking_number, c.department_id, c.current_authority_level_id, al.title as level_title
        FROM public.complaints c
        JOIN public.authority_levels al ON c.current_authority_level_id = al.id
        WHERE c.assigned_authority_id IS NULL
          AND c.status NOT IN ('RESOLVED', 'REJECTED')
    LOOP
        SELECT p.id, p.full_name INTO v_auth_id, v_auth_name
        FROM public.profiles p
        WHERE p.department_id = rec.department_id
          AND p.authority_level_id = rec.current_authority_level_id
          AND p.role IN ('authority', 'admin')
        LIMIT 1;

        IF v_auth_id IS NOT NULL THEN
            UPDATE public.complaints
            SET assigned_authority_id = v_auth_id,
                updated_at = timezone('utc'::text, now())
            WHERE id = rec.id;

            -- Also update status history assigned_to_name if blank
            UPDATE public.complaint_status_history
            SET assigned_to_name = v_auth_name
            WHERE complaint_id = rec.id
              AND assigned_to_name IS NULL
              AND assigned_to_tier = rec.level_title;
        END IF;
    END LOOP;
END $$;
