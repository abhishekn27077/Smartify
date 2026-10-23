-- ==============================================================================
-- SMARTIFY MIGRATION 003: STORAGE BUCKET & ESCALATION ENGINE FOUNDATION
-- Description: Private attachment bucket policies, escalation function, and seed tiers
-- Target: Supabase PostgreSQL (Version 15+)
-- ==============================================================================

-- 1. Seed Core Departments
INSERT INTO public.departments (name, code, description) VALUES
    ('Academic Affairs', 'ACAD', 'Curriculum, lectures, examinations, evaluation and faculty grievances'),
    ('Hostel & Residential', 'HOSTEL', 'Hostel accommodation, hygiene, mess food quality and warden concerns'),
    ('Infrastructure & Campus Facilities', 'INFRA', 'Classrooms, labs, water supply, electricity and campus upkeep'),
    ('Accounts & Finance', 'FIN', 'Tuition fees, scholarships, refunds and student billing'),
    ('Library & IT Services', 'IT', 'Campus Wi-Fi, computer labs, library books and digital portal access')
ON CONFLICT (code) DO NOTHING;

-- 2. Seed Authority Hierarchy Levels (Level 1 through Level 4 with SLAs)
INSERT INTO public.authority_levels (level_number, title, sla_days, can_resolve) VALUES
    (1, 'Level 1: Faculty Advisor / Hostel Warden', 3, true),
    (2, 'Level 2: Head of Department (HoD)', 4, true),
    (3, 'Level 3: Dean of Student Welfare / Grievance Cell', 5, true),
    (4, 'Level 4: Principal / Campus Ombudsman Board', 5, true)
ON CONFLICT (level_number) DO NOTHING;

-- 3. Supabase Private Storage Bucket: complaint-attachments
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'complaint-attachments',
    'complaint-attachments',
    false, -- Strictly private bucket (no public unauthenticated URLs)
    10485760, -- Max 10MB per file
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 10485760;

-- 4. Storage Row Level Security Policies
-- Folder Structure Convention: {complaint_id}/{filename}

CREATE POLICY "Storage: Authorized users can read complaint attachments"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'complaint-attachments'
        AND EXISTS (
            SELECT 1 FROM public.complaints c
            WHERE c.id::text = (storage.foldername(name))[1]
            AND (
                c.student_id = auth.uid()
                OR (
                    public.is_authority() AND (
                        c.department_id = public.get_user_department_id()
                        OR c.assigned_authority_id = auth.uid()
                        OR public.is_admin()
                    )
                )
            )
        )
    );

CREATE POLICY "Storage: Complainants and assigned authorities can upload attachments"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'complaint-attachments'
        AND (
            public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.complaints c
                WHERE c.id::text = (storage.foldername(name))[1]
                AND (
                    c.student_id = auth.uid()
                    OR c.assigned_authority_id = auth.uid()
                )
            )
        )
    );

CREATE POLICY "Storage: Only admins can delete attachments"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'complaint-attachments'
        AND public.is_admin()
    );

-- 5. Server-Authoritative Escalation & 20-Day Cutoff Function
-- Intended to be executed idempotently via pg_cron or Supabase Edge Function
CREATE OR REPLACE FUNCTION public.process_daily_complaint_escalations()
RETURNS JSONB AS $$
DECLARE
    v_paused_count INT := 0;
    v_escalated_count INT := 0;
    v_complaint RECORD;
    v_next_level RECORD;
BEGIN
    -- STEP 1: Enforce the 20-Calendar-Day Cutoff Freeze
    -- Any active grievance that has reached 20 calendar days from creation must pause.
    FOR v_complaint IN
        SELECT id, tracking_number, student_id, title
        FROM public.complaints
        WHERE created_at <= (timezone('utc'::text, now()) - INTERVAL '20 days')
          AND status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')
          AND is_cutoff_paused = false
    LOOP
        UPDATE public.complaints
        SET status = 'CUTOFF_PAUSED',
            is_cutoff_paused = true,
            paused_at = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_complaint.id;

        -- Create notification for student
        INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type)
        VALUES (
            v_complaint.student_id,
            v_complaint.id,
            'Automated Escalation Frozen (20-Day Cutoff)',
            'Grievance ' || v_complaint.tracking_number || ' has reached the 20-day campus cutoff limit. Escalation is paused pending administrative sign-off.',
            'DEADLINE_WARNING'
        );

        -- Audit log entry
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            NULL, -- System automated event
            'CUTOFF_PAUSED',
            'complaints',
            v_complaint.id,
            jsonb_build_object('reason', '20-day cutoff exceeded', 'tracking_number', v_complaint.tracking_number)
        );

        v_paused_count := v_paused_count + 1;
    END LOOP;

    -- STEP 2: Enforce Tier SLA Escalation for unpaused complaints past their tier deadline
    FOR v_complaint IN
        SELECT 
            c.id, 
            c.tracking_number, 
            c.student_id, 
            c.current_authority_level_id,
            al.level_number AS current_level_number
        FROM public.complaints c
        JOIN public.authority_levels al ON al.id = c.current_authority_level_id
        WHERE c.current_tier_deadline <= timezone('utc'::text, now())
          AND c.status IN ('PENDING', 'UNDER_REVIEW', 'IN_PROGRESS', 'ESCALATED')
          AND c.is_cutoff_paused = false
    LOOP
        -- Look up next level in hierarchy
        SELECT id, level_number, title, sla_days INTO v_next_level
        FROM public.authority_levels
        WHERE level_number = v_complaint.current_level_number + 1;

        IF FOUND THEN
            -- Escalate to next tier
            UPDATE public.complaints
            SET current_authority_level_id = v_next_level.id,
                status = 'ESCALATED',
                current_tier_deadline = timezone('utc'::text, now()) + (v_next_level.sla_days || ' days')::INTERVAL,
                assigned_authority_id = NULL, -- Reopens for next tier intake
                updated_at = timezone('utc'::text, now())
            WHERE id = v_complaint.id;

            -- Record escalation log
            INSERT INTO public.complaint_escalations (
                complaint_id,
                from_level_id,
                to_level_id,
                is_automated,
                reason
            ) VALUES (
                v_complaint.id,
                v_complaint.current_authority_level_id,
                v_next_level.id,
                true,
                'Automated escalation: Tier SLA deadline breached at Level ' || v_complaint.current_level_number
            );

            -- Notify student of tier escalation
            INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type)
            VALUES (
                v_complaint.student_id,
                v_complaint.id,
                'Grievance Escalated to ' || v_next_level.title,
                'Your grievance ' || v_complaint.tracking_number || ' has been escalated to ' || v_next_level.title || ' due to SLA expiration.',
                'ESCALATION'
            );

            v_escalated_count := v_escalated_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'cutoff_paused_count', v_paused_count,
        'escalated_count', v_escalated_count,
        'processed_at', timezone('utc'::text, now())
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Authorized Resumption Function (Admin/Dean Sign-Off Only)
CREATE OR REPLACE FUNCTION public.resume_paused_complaint(
    p_complaint_id UUID,
    p_resumption_notes TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_complaint RECORD;
    v_sla_days INT;
BEGIN
    -- Strict security: Only administrators can authorize resumption
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only an administrator or designated Dean can resume a paused grievance.';
    END IF;

    SELECT c.*, al.sla_days INTO v_complaint
    FROM public.complaints c
    JOIN public.authority_levels al ON al.id = c.current_authority_level_id
    WHERE c.id = p_complaint_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Complaint with ID % not found.', p_complaint_id;
    END IF;

    IF NOT v_complaint.is_cutoff_paused THEN
        RAISE EXCEPTION 'Complaint % is not in CUTOFF_PAUSED status.', v_complaint.tracking_number;
    END IF;

    -- Resume the complaint: unfreeze, provide refreshed tier window
    UPDATE public.complaints
    SET status = 'UNDER_REVIEW',
        is_cutoff_paused = false,
        resumed_at = timezone('utc'::text, now()),
        resumed_by = auth.uid(),
        current_tier_deadline = timezone('utc'::text, now()) + (v_complaint.sla_days || ' days')::INTERVAL,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_complaint_id;

    -- Record in audit log
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        auth.uid(),
        'RESUMPTION_AUTHORIZED',
        'complaints',
        p_complaint_id,
        jsonb_build_object(
            'tracking_number', v_complaint.tracking_number,
            'notes', p_resumption_notes
        )
    );

    -- Notify student of resumption
    INSERT INTO public.notifications (user_id, complaint_id, title, message, notification_type)
    VALUES (
        v_complaint.student_id,
        p_complaint_id,
        'Grievance Resumed by Administration',
        'Grievance ' || v_complaint.tracking_number || ' has been formally resumed with remarks: ' || p_resumption_notes,
        'RESUMPTION'
    );

    RETURN jsonb_build_object(
        'success', true,
        'complaint_id', p_complaint_id,
        'resumed_at', timezone('utc'::text, now())
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
