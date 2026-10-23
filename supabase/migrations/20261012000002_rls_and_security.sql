-- ==============================================================================
-- SMARTIFY MIGRATION 002: ROW LEVEL SECURITY & ACCESS CONTROL
-- Description: Helper functions, triggers, and strict least-privilege RLS policies
-- Target: Supabase PostgreSQL (Version 15+)
-- ==============================================================================

-- 1. Security Definer Helper Functions (Fast, non-recursive role resolution)
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS app_role AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'admin'
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_authority()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('authority', 'admin')
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_user_department_id()
RETURNS UUID AS $$
    SELECT department_id FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 2. New User Registration Trigger on auth.users
-- Enforces that all public signups are created as 'student' by default.
-- Privileged roles can only be granted by existing administrators.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (
        id,
        email,
        full_name,
        role,
        avatar_url,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        'student', -- Strict default: students cannot self-assign authority/admin roles
        NEW.raw_user_meta_data->>'avatar_url',
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- 3. Prevent Self-Escalation on Profile Updates
CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Only administrators may alter role, department_id, or authority_level_id
    IF NOT public.is_admin() THEN
        IF NEW.role IS DISTINCT FROM OLD.role THEN
            RAISE EXCEPTION 'Unauthorized: Only administrators can modify user roles.';
        END IF;
        IF NEW.department_id IS DISTINCT FROM OLD.department_id THEN
            RAISE EXCEPTION 'Unauthorized: Only administrators can reassign user departments.';
        END IF;
        IF NEW.authority_level_id IS DISTINCT FROM OLD.authority_level_id THEN
            RAISE EXCEPTION 'Unauthorized: Only administrators can alter authority levels.';
        END IF;
    END IF;

    NEW.updated_at := timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_protect_profile_fields ON public.profiles;
CREATE TRIGGER trg_protect_profile_fields
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_profile_privileged_fields();

-- 4. Enable Row Level Security (RLS) on all 9 tables
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.authority_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- 5. Strict RLS Policies

-- A. Departments Table
CREATE POLICY "Departments are viewable by authenticated users"
    ON public.departments FOR SELECT
    TO authenticated
    USING (is_active = true OR public.is_admin());

CREATE POLICY "Departments can only be modified by admins"
    ON public.departments FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- B. Authority Levels Table
CREATE POLICY "Authority levels are viewable by authenticated users"
    ON public.authority_levels FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authority levels can only be modified by admins"
    ON public.authority_levels FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- C. Profiles Table
CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        id = auth.uid() 
        OR public.is_authority()
    );

CREATE POLICY "Users can update their own personal profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid() OR public.is_admin())
    WITH CHECK (id = auth.uid() OR public.is_admin());

-- D. Complaints Table
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

CREATE POLICY "Students can submit complaints for themselves"
    ON public.complaints FOR INSERT
    TO authenticated
    WITH CHECK (
        student_id = auth.uid()
        AND status = 'PENDING'
    );

CREATE POLICY "Complaint update policy"
    ON public.complaints FOR UPDATE
    TO authenticated
    USING (
        -- Students can only modify a complaint while still PENDING
        (student_id = auth.uid() AND status = 'PENDING')
        -- Authorities can update complaints assigned to their scope
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

-- E. Complaint Attachments Table
CREATE POLICY "Attachment select policy"
    ON public.complaint_attachments FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.complaints c
            WHERE c.id = complaint_id
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

CREATE POLICY "Attachment insert policy"
    ON public.complaint_attachments FOR INSERT
    TO authenticated
    WITH CHECK (
        uploader_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.complaints c
            WHERE c.id = complaint_id
            AND (
                c.student_id = auth.uid()
                OR c.assigned_authority_id = auth.uid()
                OR public.is_admin()
            )
        )
    );

-- F. Complaint Escalations Table
CREATE POLICY "Escalation select policy"
    ON public.complaint_escalations FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.complaints c
            WHERE c.id = complaint_id
            AND (
                c.student_id = auth.uid()
                OR public.is_authority()
            )
        )
    );

CREATE POLICY "Escalation insert policy (Authorities and Admins only)"
    ON public.complaint_escalations FOR INSERT
    TO authenticated
    WITH CHECK (public.is_authority());

-- G. Complaint Status History Table
CREATE POLICY "Status history select policy"
    ON public.complaint_status_history FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.complaints c
            WHERE c.id = complaint_id
            AND (
                c.student_id = auth.uid()
                OR public.is_authority()
            )
        )
    );

-- Status history is append-only via triggers. Direct client inserts restricted to authorized roles.
CREATE POLICY "Status history insert policy"
    ON public.complaint_status_history FOR INSERT
    TO authenticated
    WITH CHECK (public.is_authority());

-- H. Notifications Table
CREATE POLICY "Users can select their own notifications"
    ON public.notifications FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "Users can update their own notification read status"
    ON public.notifications FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Notifications insert policy"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid() OR public.is_authority());

CREATE POLICY "Users can delete their own notifications"
    ON public.notifications FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

-- I. Audit Logs Table (Immutable Append-Only Security Log)
CREATE POLICY "Only admins can view audit logs"
    ON public.audit_logs FOR SELECT
    TO authenticated
    USING (public.is_admin());

CREATE POLICY "Authenticated users can record audit log events"
    ON public.audit_logs FOR INSERT
    TO authenticated
    WITH CHECK (actor_id = auth.uid() OR actor_id IS NULL);

-- Strict no-update and no-delete: NO policies created for UPDATE or DELETE on audit_logs.
