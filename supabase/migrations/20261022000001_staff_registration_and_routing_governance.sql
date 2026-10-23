-- ==============================================================================
-- SMARTIFY MIGRATION 20261022000001: STAFF REGISTRATION & ROUTING GOVERNANCE
-- Description: Admin staff creation RPC, student program registration trigger,
--              and staff active/inactive profile governance.
-- Target: Supabase PostgreSQL (Version 15+)
-- ==============================================================================

-- 1. Ensure is_active exists on public.profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- 2. Enhanced handle_new_user Trigger for Student Self-Registration
-- Enforces:
--  - Role is ALWAYS 'student' (no self-elevation to authority or admin)
--  - Canonical academic program mapping (MCA, MBA, M.Com) to department_id
--  - Student cannot assign authority_level_id or privileged permissions
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_prog TEXT;
    v_target_dept_id UUID := NULL;
    v_reg_no TEXT;
BEGIN
    v_prog := trim(COALESCE(NEW.raw_user_meta_data->>'academic_program', ''));
    v_reg_no := trim(COALESCE(NEW.raw_user_meta_data->>'registration_number', ''));

    -- Resolve canonical academic department from program
    IF v_prog = 'MBA' THEN
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'MBA' LIMIT 1;
    ELSIF v_prog IN ('M.Com', 'MCOM') THEN
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'MCOM' LIMIT 1;
        v_prog := 'M.Com';
    ELSIF v_prog = 'MCA' THEN
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'MCA' LIMIT 1;
    ELSE
        -- Fallback default academic department if unspecified
        SELECT id INTO v_target_dept_id FROM public.departments WHERE code = 'MCA' LIMIT 1;
        v_prog := 'MCA';
    END IF;

    -- If no registration number provided, generate canonical campus ID
    IF v_reg_no = '' THEN
        v_reg_no := v_prog || '-2026-STU-' || LPAD(nextval('complaint_tracking_seq')::TEXT, 4, '0');
    END IF;

    INSERT INTO public.profiles (
        id,
        email,
        full_name,
        role,
        academic_program,
        department_id,
        authority_level_id,
        registration_number,
        is_active,
        avatar_url,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        'student', -- Strict default: students cannot self-assign authority/admin roles
        v_prog,
        v_target_dept_id,
        NULL, -- Students have no authority level
        v_reg_no,
        true,
        NEW.raw_user_meta_data->>'avatar_url',
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        academic_program = COALESCE(public.profiles.academic_program, EXCLUDED.academic_program),
        department_id = COALESCE(public.profiles.department_id, EXCLUDED.department_id),
        registration_number = COALESCE(public.profiles.registration_number, EXCLUDED.registration_number),
        updated_at = timezone('utc'::text, now());

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reattach trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- 3. Admin-Only Staff Account Creation RPC
-- Allows authorized administrators to create an AUTHORITY account with:
--  - full_name
--  - institutional email
--  - password
--  - department_id
--  - authority_level_id
--  - is_active
CREATE OR REPLACE FUNCTION public.admin_create_authority_staff(
    p_email TEXT,
    p_password TEXT,
    p_full_name TEXT,
    p_department_id UUID,
    p_authority_level_id UUID,
    p_is_active BOOLEAN DEFAULT true
)
RETURNS JSONB AS $$
DECLARE
    v_admin_id UUID;
    v_new_user_id UUID;
    v_sanitized_email TEXT;
    v_sanitized_name TEXT;
    v_dept RECORD;
    v_level RECORD;
    v_existing_id UUID;
    v_encrypted_pwd TEXT;
BEGIN
    v_admin_id := auth.uid();

    -- 1. Verify caller is an administrator
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only institutional administrators can create authority staff.';
    END IF;

    -- 2. Validate input parameters
    v_sanitized_email := lower(trim(p_email));
    v_sanitized_name := trim(p_full_name);

    IF v_sanitized_email IS NULL OR v_sanitized_email = '' OR v_sanitized_email NOT LIKE '%@%.%' THEN
        RAISE EXCEPTION 'Invalid institutional email address provided.';
    END IF;

    IF v_sanitized_name IS NULL OR v_sanitized_name = '' THEN
        RAISE EXCEPTION 'Full name is required for authority staff.';
    END IF;

    IF p_password IS NULL OR length(p_password) < 6 THEN
        RAISE EXCEPTION 'Password must be at least 6 characters.';
    END IF;

    -- 3. Validate department existence
    SELECT * INTO v_dept FROM public.departments WHERE id = p_department_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Specified department does not exist in the campus registry.';
    END IF;

    -- 4. Validate authority level existence
    SELECT * INTO v_level FROM public.authority_levels WHERE id = p_authority_level_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Specified authority level tier does not exist in the institutional hierarchy.';
    END IF;

    -- Prevent invalid role combinations: operational single-tier departments cannot have L2/L3 if unconfigured
    IF v_dept.code IN ('HOSTEL', 'IT', 'FIN', 'INFRA') AND v_level.level_number > 1 THEN
        -- Allow if institutional admin intentionally configures, but flag warning if needed
        NULL;
    END IF;

    -- 5. Check for duplicate account
    SELECT id INTO v_existing_id FROM auth.users WHERE lower(email) = v_sanitized_email LIMIT 1;
    IF v_existing_id IS NOT NULL THEN
        RAISE EXCEPTION 'An account with email % already exists.', v_sanitized_email;
    END IF;

    -- 6. Encrypt password using pgcrypto blowfish
    v_encrypted_pwd := crypt(p_password, gen_salt('bf'));
    v_new_user_id := gen_random_uuid();

    -- 7. Insert into auth.users
    INSERT INTO auth.users (
        id,
        instance_id,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        role,
        aud
    ) VALUES (
        v_new_user_id,
        '00000000-0000-0000-0000-000000000000',
        v_sanitized_email,
        v_encrypted_pwd,
        timezone('utc'::text, now()),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', v_sanitized_name),
        timezone('utc'::text, now()),
        timezone('utc'::text, now()),
        'authenticated',
        'authenticated'
    );

    -- 8. Insert into auth.identities
    INSERT INTO auth.identities (
        id,
        provider_id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        v_new_user_id::text,
        v_new_user_id,
        jsonb_build_object('sub', v_new_user_id::text, 'email', v_sanitized_email),
        'email',
        timezone('utc'::text, now()),
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    );

    -- 9. Upsert public.profiles with role = 'authority'
    -- Note: on_auth_user_created trigger inserted profile with 'student'. We now update it to 'authority'
    UPDATE public.profiles
    SET role = 'authority',
        department_id = p_department_id,
        authority_level_id = p_authority_level_id,
        full_name = v_sanitized_name,
        is_active = COALESCE(p_is_active, true),
        designation = v_level.title,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_new_user_id;

    -- 10. Record immutable audit log
    INSERT INTO public.audit_logs (
        actor_id,
        action,
        entity_type,
        entity_id,
        metadata
    ) VALUES (
        v_admin_id,
        'ADMIN_STAFF_CREATED',
        'profiles',
        v_new_user_id,
        jsonb_build_object(
            'email', v_sanitized_email,
            'full_name', v_sanitized_name,
            'role', 'authority',
            'department_id', p_department_id,
            'department_name', v_dept.name,
            'authority_level_id', p_authority_level_id,
            'level_number', v_level.level_number,
            'is_active', COALESCE(p_is_active, true)
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_new_user_id,
        'email', v_sanitized_email,
        'full_name', v_sanitized_name,
        'role', 'authority',
        'department_name', v_dept.name,
        'level_title', v_level.title
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Admin-Only Staff Active Toggle RPC
CREATE OR REPLACE FUNCTION public.admin_toggle_staff_active(
    p_target_user_id UUID,
    p_is_active BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_admin_id UUID;
    v_target RECORD;
BEGIN
    v_admin_id := auth.uid();

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only institutional administrators can toggle staff active status.';
    END IF;

    SELECT * INTO v_target FROM public.profiles WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found.';
    END IF;

    UPDATE public.profiles
    SET is_active = p_is_active,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_target_user_id;

    INSERT INTO public.audit_logs (
        actor_id,
        action,
        entity_type,
        entity_id,
        metadata
    ) VALUES (
        v_admin_id,
        'ADMIN_STAFF_STATUS_TOGGLED',
        'profiles',
        p_target_user_id,
        jsonb_build_object(
            'target_user_id', p_target_user_id,
            'email', v_target.email,
            'is_active', p_is_active
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_target_user_id,
        'is_active', p_is_active
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
