-- ==============================================================================
-- SMARTIFY MIGRATION 004: AUTOMATIC ESCALATION ENGINE & 20-DAY CUTOFF SCHEDULER
-- Description: Concurrency-safe escalation worker, simulated time testing support,
--              level-4 apex handling, authority notification, and admin resumption RPC
-- Target: Supabase PostgreSQL (Version 15+)
-- ==============================================================================

-- 1. Enhanced Concurrency-Safe Escalation & Cutoff Worker Function
-- Features:
-- - Row-level locking: 'FOR UPDATE SKIP LOCKED' prevents race conditions on concurrent cron executions
-- - Simulation support: Optional p_simulated_now parameter allows safe testing without waiting 20 real days
-- - 20-Day Cutoff Precedence: Freezes complaints at 20 calendar days before tier escalations
-- - Apex Level 4 Handling: Flags complaints at maximum tier for administrative review if breached
-- - Notification Broadcasting: Alerts student, previous authority, next authority, and administrators
-- - Immutable History & Audit: Appends to complaint_status_history, complaint_escalations, and audit_logs

CREATE OR REPLACE FUNCTION public.process_daily_complaint_escalations(
    p_simulated_now TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_paused_count INT := 0;
    v_escalated_count INT := 0;
    v_admin_review_count INT := 0;
    v_complaint RECORD;
    v_next_level RECORD;
    v_next_authority RECORD;
    v_admin RECORD;
    v_new_deadline TIMESTAMPTZ;
    v_tier_days INT;
BEGIN
    -- Strict authorization check: Only administrators, cron, or server automation
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Student accounts cannot trigger automated complaint escalations.';
    END IF;

    -- If simulated timestamp provided, strictly require admin
    IF p_simulated_now IS NOT NULL AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators may provide simulated evaluation timestamps.';
    END IF;

    -- Determine current effective timestamp (Server UTC or simulation)
    v_now := COALESCE(p_simulated_now, timezone('utc'::text, now()));

    -- =========================================================================
    -- STEP 1: ENFORCE 20-CALENDAR-DAY CUTOFF FREEZE (HIGHEST PRECEDENCE)
    -- =========================================================================
    FOR v_complaint IN
        SELECT 
            c.id, 
            c.tracking_number, 
            c.student_id, 
            c.title,
            c.status,
            c.assigned_authority_id,
            c.department_id,
            c.created_at,
            c.cutoff_deadline
        FROM public.complaints c
        WHERE (v_now >= c.cutoff_deadline OR c.created_at <= (v_now - INTERVAL '20 days'))
          AND c.status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')
          AND c.is_cutoff_paused = false
        ORDER BY c.created_at ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        -- Pause the complaint
        UPDATE public.complaints
        SET status = 'CUTOFF_PAUSED',
            is_cutoff_paused = true,
            paused_at = v_now,
            updated_at = v_now
        WHERE id = v_complaint.id;

        -- Record in complaint status history
        INSERT INTO public.complaint_status_history (
            complaint_id,
            changed_by,
            old_status,
            new_status,
            remarks,
            created_at
        ) VALUES (
            v_complaint.id,
            NULL, -- System automation
            v_complaint.status,
            'CUTOFF_PAUSED',
            'Automated 20-calendar-day campus cutoff limit reached. Automated forwarding frozen pending administrative review.',
            v_now
        );

        -- Record in audit log
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
        VALUES (
            NULL,
            'CUTOFF_PAUSED',
            'complaints',
            v_complaint.id,
            jsonb_build_object(
                'tracking_number', v_complaint.tracking_number,
                'paused_at', v_now,
                'created_at', v_complaint.created_at,
                'reason', '20-calendar-day cutoff limit exceeded'
            ),
            v_now
        );

        -- Notify student
        INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
        VALUES (
            v_complaint.student_id,
            v_complaint.id,
            'Automated Escalation Frozen (20-Day Cutoff)',
            'Grievance ' || v_complaint.tracking_number || ' has reached the 20-day campus cutoff limit. Escalation is paused pending administrative sign-off.',
            'DEADLINE_WARNING',
            v_now
        );

        -- Notify assigned authority (if one was assigned)
        IF v_complaint.assigned_authority_id IS NOT NULL THEN
            INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
            VALUES (
                v_complaint.assigned_authority_id,
                v_complaint.id,
                'Action Required: Grievance Cutoff Paused',
                'Grievance ' || v_complaint.tracking_number || ' has reached the 20-day cutoff limit and is frozen.',
                'DEADLINE_WARNING',
                v_now
            );
        END IF;

        -- Notify all active campus administrators
        FOR v_admin IN 
            SELECT id FROM public.profiles WHERE role = 'admin'
        LOOP
            INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
            VALUES (
                v_admin.id,
                v_complaint.id,
                'Admin Review Required: 20-Day Cutoff Freeze',
                'Grievance ' || v_complaint.tracking_number || ' has reached the 20-day cutoff limit and requires formal administrative resumption.',
                'DEADLINE_WARNING',
                v_now
            );
        END LOOP;

        v_paused_count := v_paused_count + 1;
    END LOOP;

    -- =========================================================================
    -- STEP 2: TIER SLA FORWARDING (OVERDUE COMPLAINTS NOT IN CUTOFF PAUSED)
    -- =========================================================================
    FOR v_complaint IN
        SELECT 
            c.id, 
            c.tracking_number, 
            c.student_id, 
            c.department_id,
            c.current_authority_level_id,
            c.assigned_authority_id,
            c.status,
            c.updated_at,
            c.current_tier_deadline,
            al.level_number AS current_level_number,
            al.title AS current_level_title
        FROM public.complaints c
        JOIN public.authority_levels al ON al.id = c.current_authority_level_id
        WHERE v_now >= c.current_tier_deadline
          AND c.status IN ('PENDING', 'UNDER_REVIEW', 'IN_PROGRESS', 'ESCALATED')
          AND c.is_cutoff_paused = false
        ORDER BY c.current_tier_deadline ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        -- Look up next level in authority hierarchy
        SELECT id, level_number, title, sla_days INTO v_next_level
        FROM public.authority_levels
        WHERE level_number = v_complaint.current_level_number + 1;

        IF FOUND THEN
            -- Calculate new tier deadline
            v_new_deadline := v_now + (v_next_level.sla_days || ' days')::INTERVAL;
            v_tier_days := GREATEST(1, EXTRACT(DAY FROM (v_now - v_complaint.updated_at))::INT);

            -- Select next authority: Find active authority user assigned to this department and level
            SELECT id, full_name INTO v_next_authority
            FROM public.profiles
            WHERE department_id = v_complaint.department_id
              AND authority_level_id = v_next_level.id
              AND role IN ('authority', 'admin')
            LIMIT 1;

            -- Update complaint to next tier
            UPDATE public.complaints
            SET current_authority_level_id = v_next_level.id,
                assigned_authority_id = v_next_authority.id, -- May be NULL if department pool intake
                status = 'ESCALATED',
                current_tier_deadline = v_new_deadline,
                updated_at = v_now
            WHERE id = v_complaint.id;

            -- Record status history
            INSERT INTO public.complaint_status_history (
                complaint_id,
                changed_by,
                old_status,
                new_status,
                remarks,
                created_at
            ) VALUES (
                v_complaint.id,
                NULL,
                v_complaint.status,
                'ESCALATED',
                'Automated escalation: Tier SLA deadline breached at Level ' || v_complaint.current_level_number || ' (' || v_complaint.current_level_title || '). Escalated to ' || v_next_level.title || '.',
                v_now
            );

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
                'Automated escalation: Tier SLA deadline breached at Level ' || v_complaint.current_level_number,
                v_tier_days,
                v_now
            );

            -- Record in audit logs
            INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
            VALUES (
                NULL,
                'AUTOMATED_TIER_ESCALATION',
                'complaints',
                v_complaint.id,
                jsonb_build_object(
                    'tracking_number', v_complaint.tracking_number,
                    'from_level', v_complaint.current_level_number,
                    'to_level', v_next_level.level_number,
                    'new_deadline', v_new_deadline
                ),
                v_now
            );

            -- Notify complainant
            INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
            VALUES (
                v_complaint.student_id,
                v_complaint.id,
                'Grievance Escalated to ' || v_next_level.title,
                'Grievance ' || v_complaint.tracking_number || ' has been automatically forwarded to ' || v_next_level.title || ' due to SLA expiration.',
                'ESCALATION',
                v_now
            );

            -- Notify previous authority (if assigned)
            IF v_complaint.assigned_authority_id IS NOT NULL THEN
                INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
                VALUES (
                    v_complaint.assigned_authority_id,
                    v_complaint.id,
                    'Grievance Escalated Away (SLA Expired)',
                    'Grievance ' || v_complaint.tracking_number || ' was escalated to ' || v_next_level.title || ' because the tier SLA deadline passed.',
                    'ESCALATION',
                    v_now
                );
            END IF;

            -- Notify next assigned authority (if identified)
            IF v_next_authority.id IS NOT NULL THEN
                INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
                VALUES (
                    v_next_authority.id,
                    v_complaint.id,
                    'New Escalated Grievance Assigned',
                    'Grievance ' || v_complaint.tracking_number || ' has been escalated to your tier (' || v_next_level.title || '). SLA deadline: ' || v_new_deadline::date,
                    'ESCALATION',
                    v_now
                );
            END IF;

            v_escalated_count := v_escalated_count + 1;

        ELSE
            -- Level 4 Apex Authority Reached (No next level configured)
            -- Rather than inventing an assignee, flag for administrative review
            INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata, created_at)
            VALUES (
                NULL,
                'APEX_TIER_SLA_BREACHED',
                'complaints',
                v_complaint.id,
                jsonb_build_object(
                    'tracking_number', v_complaint.tracking_number,
                    'level_number', v_complaint.current_level_number,
                    'reason', 'Apex authority SLA breached; no next tier available.'
                ),
                v_now
            );

            -- Notify campus administrators of apex breach
            FOR v_admin IN 
                SELECT id FROM public.profiles WHERE role = 'admin'
            LOOP
                INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
                VALUES (
                    v_admin.id,
                    v_complaint.id,
                    'URGENT: Level 4 Apex SLA Breached',
                    'Grievance ' || v_complaint.tracking_number || ' has breached its Level 4 Ombudsman deadline with no higher tier available. Immediate administrative intervention required.',
                    'DEADLINE_WARNING',
                    v_now
                );
            END LOOP;

            v_admin_review_count := v_admin_review_count + 1;
        END IF;

    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'effective_timestamp', v_now,
        'cutoff_paused_count', v_paused_count,
        'escalated_count', v_escalated_count,
        'apex_admin_review_count', v_admin_review_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Enhanced Authorized Administrative Resumption Function
-- Allows approved Administrators and Deans to unfreeze a CUTOFF_PAUSED grievance,
-- establishing a fresh valid deadline and logging immutable audit notes.

DROP FUNCTION IF EXISTS public.resume_paused_complaint(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.resume_paused_complaint(
    p_complaint_id UUID,
    p_resumption_notes TEXT,
    p_simulated_now TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_complaint RECORD;
    v_sla_days INT;
    v_new_deadline TIMESTAMPTZ;
    v_new_cutoff TIMESTAMPTZ;
BEGIN
    v_now := COALESCE(p_simulated_now, timezone('utc'::text, now()));

    -- Strict Permission Check: Only Admins / Authorized Deans
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only an administrator or designated Dean can resume a paused grievance.';
    END IF;

    -- Validate Mandatory Resumption Reason
    IF p_resumption_notes IS NULL OR char_length(trim(p_resumption_notes)) < 10 THEN
        RAISE EXCEPTION 'A comprehensive resumption note (at least 10 characters) is required.';
    END IF;

    -- Fetch complaint and verify paused state
    SELECT c.*, al.sla_days INTO v_complaint
    FROM public.complaints c
    JOIN public.authority_levels al ON al.id = c.current_authority_level_id
    WHERE c.id = p_complaint_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Complaint with ID % not found.', p_complaint_id;
    END IF;

    IF NOT v_complaint.is_cutoff_paused AND v_complaint.status != 'CUTOFF_PAUSED' THEN
        RAISE EXCEPTION 'Complaint % is not currently paused.', v_complaint.tracking_number;
    END IF;

    -- Compute refreshed tier deadline and extend cutoff boundary
    v_new_deadline := v_now + (v_complaint.sla_days || ' days')::INTERVAL;
    v_new_cutoff := v_now + INTERVAL '20 days';

    -- Resume Complaint
    UPDATE public.complaints
    SET status = 'UNDER_REVIEW',
        is_cutoff_paused = false,
        resumed_at = v_now,
        resumed_by = auth.uid(),
        current_tier_deadline = v_new_deadline,
        cutoff_deadline = v_new_cutoff,
        updated_at = v_now
    WHERE id = p_complaint_id;

    -- Status history trail
    INSERT INTO public.complaint_status_history (
        complaint_id,
        changed_by,
        old_status,
        new_status,
        remarks,
        created_at
    ) VALUES (
        p_complaint_id,
        auth.uid(),
        'CUTOFF_PAUSED',
        'UNDER_REVIEW',
        'Administrative resumption authorized: ' || trim(p_resumption_notes),
        v_now
    );

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
        'Grievance Resumed by Administration',
        'Grievance ' || v_complaint.tracking_number || ' has been formally resumed: ' || trim(p_resumption_notes),
        'RESUMPTION',
        v_now
    );

    -- Notify Assigned Authority (if present)
    IF v_complaint.assigned_authority_id IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type, created_at)
        VALUES (
            v_complaint.assigned_authority_id,
            p_complaint_id,
            'Paused Grievance Resumed',
            'Grievance ' || v_complaint.tracking_number || ' has been resumed with notes: ' || trim(p_resumption_notes),
            'RESUMPTION',
            v_now
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'tracking_number', v_complaint.tracking_number,
        'new_status', 'UNDER_REVIEW',
        'new_tier_deadline', v_new_deadline,
        'resumed_at', v_now
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. Administrative Cutoff & Escalation Views (For Flutter Admin Dashboard)
CREATE OR REPLACE VIEW public.cutoff_paused_complaints_view AS
SELECT 
    c.id,
    c.tracking_number,
    c.student_id,
    sp.full_name AS student_name,
    sp.email AS student_email,
    c.department_id,
    d.name AS department_name,
    d.code AS department_code,
    c.current_authority_level_id,
    al.level_number AS current_authority_level_number,
    al.title AS current_authority_level_title,
    c.assigned_authority_id,
    ap.full_name AS assigned_authority_name,
    c.title,
    c.category,
    c.priority,
    c.created_at,
    c.paused_at,
    c.cutoff_deadline,
    ROUND(EXTRACT(EPOCH FROM (COALESCE(c.paused_at, timezone('utc'::text, now())) - c.created_at)) / 86400.0, 1) AS total_days_elapsed
FROM public.complaints c
JOIN public.departments d ON d.id = c.department_id
JOIN public.authority_levels al ON al.id = c.current_authority_level_id
LEFT JOIN public.profiles sp ON sp.id = c.student_id
LEFT JOIN public.profiles ap ON ap.id = c.assigned_authority_id
WHERE c.status = 'CUTOFF_PAUSED' OR c.is_cutoff_paused = true;


-- 4. Scheduler Configuration Instructions & Safeguards
-- NOTE: In Supabase, pg_cron is enabled via SQL or Dashboard.
-- When activating the remote scheduler (subject to administrator sign-off), run:
--
-- CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
-- SELECT cron.schedule(
--     'smartify_process_escalations_job',
--     '*/15 * * * *', -- Runs every 15 minutes
--     'SELECT public.process_daily_complaint_escalations();'
-- );
