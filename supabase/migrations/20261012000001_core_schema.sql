-- ==============================================================================
-- SMARTIFY MIGRATION 001: CORE SCHEMA
-- Description: Core tables, enums, constraints, indexes and audit triggers
-- Target: Supabase PostgreSQL (Version 15+)
-- ==============================================================================

-- 1. Custom Enum Types
DO $$ BEGIN
    CREATE TYPE app_role AS ENUM ('student', 'authority', 'admin');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE complaint_status AS ENUM (
        'PENDING',
        'UNDER_REVIEW',
        'IN_PROGRESS',
        'ESCALATED',
        'CUTOFF_PAUSED',
        'RESOLVED',
        'REJECTED'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE complaint_priority AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'URGENT');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE notification_type AS ENUM (
        'STATUS_CHANGE',
        'ESCALATION',
        'DEADLINE_WARNING',
        'RESUMPTION',
        'GENERAL'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Sequence for Complaint Tracking Numbers
CREATE SEQUENCE IF NOT EXISTS complaint_tracking_seq START 1001;

-- 3. Departments Table
CREATE TABLE IF NOT EXISTS public.departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    code TEXT NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 4. Authority Levels Table (Hierarchy Tiers & Deadlines)
CREATE TABLE IF NOT EXISTS public.authority_levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    level_number INT NOT NULL UNIQUE CHECK (level_number >= 1 AND level_number <= 4),
    title TEXT NOT NULL,
    sla_days INT NOT NULL CHECK (sla_days > 0),
    can_resolve BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 5. Profiles Table (Extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    role app_role NOT NULL DEFAULT 'student',
    department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    authority_level_id UUID REFERENCES public.authority_levels(id) ON DELETE SET NULL,
    registration_number TEXT,
    phone TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 6. Complaints Table
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tracking_number TEXT NOT NULL UNIQUE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES public.departments(id),
    current_authority_level_id UUID NOT NULL REFERENCES public.authority_levels(id),
    assigned_authority_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    title TEXT NOT NULL CHECK (char_length(trim(title)) >= 5 AND char_length(title) <= 200),
    description TEXT NOT NULL CHECK (char_length(trim(description)) >= 20),
    category TEXT NOT NULL,
    incident_date DATE NOT NULL,
    status complaint_status NOT NULL DEFAULT 'PENDING',
    priority complaint_priority NOT NULL DEFAULT 'MEDIUM',
    current_tier_deadline TIMESTAMPTZ NOT NULL,
    cutoff_deadline TIMESTAMPTZ NOT NULL,
    is_cutoff_paused BOOLEAN NOT NULL DEFAULT false,
    paused_at TIMESTAMPTZ,
    resumed_at TIMESTAMPTZ,
    resumed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    resolution_notes TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 7. Complaint Attachments Table
CREATE TABLE IF NOT EXISTS public.complaint_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id UUID NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
    uploader_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes > 0 AND file_size_bytes <= 10485760),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 8. Complaint Escalations Table
CREATE TABLE IF NOT EXISTS public.complaint_escalations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id UUID NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
    from_level_id UUID NOT NULL REFERENCES public.authority_levels(id),
    to_level_id UUID NOT NULL REFERENCES public.authority_levels(id),
    escalated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    is_automated BOOLEAN NOT NULL DEFAULT true,
    reason TEXT NOT NULL,
    tier_days_spent INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 9. Complaint Status History Table
CREATE TABLE IF NOT EXISTS public.complaint_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id UUID NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
    changed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    old_status complaint_status,
    new_status complaint_status NOT NULL,
    remarks TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 10. Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    complaint_id UUID REFERENCES public.complaints(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    notification_type notification_type NOT NULL DEFAULT 'STATUS_CHANGE',
    is_read BOOLEAN NOT NULL DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 11. Audit Logs Table (Immutable Append-Only Security Trail)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 12. Strategic Performance Indexes (Per postgres-best-practices)
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_department ON public.profiles(department_id);
CREATE INDEX IF NOT EXISTS idx_profiles_authority_level ON public.profiles(authority_level_id);

CREATE INDEX IF NOT EXISTS idx_complaints_student ON public.complaints(student_id);
CREATE INDEX IF NOT EXISTS idx_complaints_dept_status ON public.complaints(department_id, status);
CREATE INDEX IF NOT EXISTS idx_complaints_assigned_authority ON public.complaints(assigned_authority_id);
CREATE INDEX IF NOT EXISTS idx_complaints_current_level ON public.complaints(current_authority_level_id);
CREATE INDEX IF NOT EXISTS idx_complaints_cutoff_deadline ON public.complaints(cutoff_deadline) WHERE status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED');
CREATE INDEX IF NOT EXISTS idx_complaints_tier_deadline ON public.complaints(current_tier_deadline) WHERE status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED');

CREATE INDEX IF NOT EXISTS idx_attachments_complaint ON public.complaint_attachments(complaint_id);
CREATE INDEX IF NOT EXISTS idx_escalations_complaint ON public.complaint_escalations(complaint_id);
CREATE INDEX IF NOT EXISTS idx_status_history_complaint ON public.complaint_status_history(complaint_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON public.notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);

-- 13. Constraint Enforcement Triggers

-- A. 7-Calendar-Day Retrospective Incident Date Rule
CREATE OR REPLACE FUNCTION public.validate_complaint_incident_date()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.incident_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'Incident date cannot be in the future. Selected: %, Current Date: %', 
            NEW.incident_date, CURRENT_DATE;
    END IF;

    IF NEW.incident_date < (CURRENT_DATE - INTERVAL '7 days')::date THEN
        RAISE EXCEPTION 'Incident date cannot be older than 7 calendar days. Selected: %, Minimum Allowed: %', 
            NEW.incident_date, (CURRENT_DATE - INTERVAL '7 days')::date;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_complaint_incident_date ON public.complaints;
CREATE TRIGGER trg_validate_complaint_incident_date
    BEFORE INSERT OR UPDATE OF incident_date ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_complaint_incident_date();

-- B. Default Timestamps, Tracking Number & Deadline Calculation on Insert
CREATE OR REPLACE FUNCTION public.initialize_complaint_defaults()
RETURNS TRIGGER AS $$
DECLARE
    v_sla_days INT;
BEGIN
    -- Assign tracking number if absent: SMT-YYYY-XXXXX
    IF NEW.tracking_number IS NULL OR trim(NEW.tracking_number) = '' THEN
        NEW.tracking_number := 'SMT-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' || LPAD(nextval('complaint_tracking_seq')::TEXT, 5, '0');
    END IF;

    -- Fetch SLA days for the starting authority level
    SELECT sla_days INTO v_sla_days FROM public.authority_levels WHERE id = NEW.current_authority_level_id;
    IF v_sla_days IS NULL THEN
        v_sla_days := 3; -- Default fallback to 3 days
    END IF;

    -- Set initial tier deadline and immutable 20-day cutoff
    NEW.current_tier_deadline := timezone('utc'::text, now()) + (v_sla_days || ' days')::INTERVAL;
    NEW.cutoff_deadline := timezone('utc'::text, now()) + INTERVAL '20 days';

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_initialize_complaint_defaults ON public.complaints;
CREATE TRIGGER trg_initialize_complaint_defaults
    BEFORE INSERT ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.initialize_complaint_defaults();

-- C. Automatic Status History Logging Trigger
CREATE OR REPLACE FUNCTION public.log_complaint_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') OR (OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO public.complaint_status_history (
            complaint_id,
            changed_by,
            old_status,
            new_status,
            remarks
        ) VALUES (
            NEW.id,
            auth.uid(),
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
            NEW.status,
            CASE 
                WHEN NEW.status = 'CUTOFF_PAUSED' THEN 'Automation paused: Reached 20-calendar-day campus cutoff limit.'
                WHEN NEW.status = 'ESCALATED' THEN 'Escalated to next authority tier due to SLA breach or manual referral.'
                WHEN NEW.status = 'RESOLVED' THEN COALESCE(NEW.resolution_notes, 'Grievance marked as resolved.')
                ELSE 'Status updated to ' || NEW.status::TEXT
            END
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_log_complaint_status_change ON public.complaints;
CREATE TRIGGER trg_log_complaint_status_change
    AFTER INSERT OR UPDATE OF status ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.log_complaint_status_change();
