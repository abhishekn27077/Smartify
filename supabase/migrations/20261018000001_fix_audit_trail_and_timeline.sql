-- ==============================================================================
-- SMARTIFY Migration: Fix Audit Trail, Actor Snapshots & Timeline Integrity
-- Migration ID: 20261018000001_fix_audit_trail_and_timeline.sql
-- ==============================================================================

-- 1. Add status remarks and snapshot columns
ALTER TABLE public.complaints 
    ADD COLUMN IF NOT EXISTS status_remarks TEXT;

ALTER TABLE public.complaint_status_history 
    ADD COLUMN IF NOT EXISTS actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS actor_display_name TEXT,
    ADD COLUMN IF NOT EXISTS actor_role TEXT,
    ADD COLUMN IF NOT EXISTS actor_department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS actor_department_name TEXT,
    ADD COLUMN IF NOT EXISTS actor_authority_level INT,
    ADD COLUMN IF NOT EXISTS actor_designation TEXT,
    ADD COLUMN IF NOT EXISTS event_type TEXT DEFAULT 'STATUS_CHANGE',
    ADD COLUMN IF NOT EXISTS is_system_event BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS assigned_to_tier TEXT,
    ADD COLUMN IF NOT EXISTS assigned_to_name TEXT;

-- 2. Clean up demo artifacts from profiles: standard full names and normalized designations
UPDATE public.profiles 
SET full_name = regexp_replace(full_name, '\s*\([^)]*\)$', '')
WHERE full_name ~ '\s*\([^)]*\)$';

UPDATE public.profiles
SET designation = replace(designation, ': ', ' — ')
WHERE designation LIKE '%: %';

-- 3. Automatic Status History Logging Trigger Function (With Actor Snapshot)
CREATE OR REPLACE FUNCTION public.log_complaint_status_change()
RETURNS TRIGGER AS $$
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
BEGIN
    IF (TG_OP = 'INSERT') OR (OLD.status IS DISTINCT FROM NEW.status) THEN
        v_actor_id := auth.uid();
        
        -- Identify Actor
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
                v_remarks := 'Automation paused: Reached 20-calendar-day campus cutoff limit.';
            ELSIF NEW.status = 'ESCALATED' AND v_actor_id IS NULL THEN
                v_remarks := 'Escalated to next authority tier due to SLA breach.';
            ELSE
                v_remarks := COALESCE(NEW.status_remarks, 'Status updated to ' || NEW.status::TEXT);
            END IF;
        END IF;

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
                -- Fail-safe for unmapped user ID
                v_name := 'Authenticated Campus Member';
                v_role := 'MEMBER';
            END IF;
        END IF;

        -- Insert single authoritative status history snapshot
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
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
            NEW.status,
            v_remarks,
            v_assigned_tier,
            v_assigned_name,
            timezone('utc'::text, now())
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on complaints
DROP TRIGGER IF EXISTS trg_log_complaint_status_change ON public.complaints;
CREATE TRIGGER trg_log_complaint_status_change
    AFTER INSERT OR UPDATE OF status ON public.complaints
    FOR EACH ROW
    EXECUTE FUNCTION public.log_complaint_status_change();

-- 4. Deduplication & Snapshot Trigger for Direct Inserts on complaint_status_history
CREATE OR REPLACE FUNCTION public.fn_complaint_status_history_dedup_and_snapshot()
RETURNS TRIGGER AS $$
DECLARE
    v_existing_id UUID;
    v_profile RECORD;
    v_actor_candidate UUID;
BEGIN
    v_actor_candidate := COALESCE(NEW.actor_user_id, NEW.changed_by, auth.uid());

    -- Check if an identical duplicate write was recorded within the last 5 seconds.
    -- A true duplicate write shares:
    -- 1. Same complaint_id
    -- 2. Same new_status
    -- 3. Same old_status
    -- 4. Same actor (or both system)
    SELECT id INTO v_existing_id
    FROM public.complaint_status_history
    WHERE complaint_id = NEW.complaint_id
      AND new_status = NEW.new_status
      AND (old_status IS NOT DISTINCT FROM NEW.old_status)
      AND (
          actor_user_id IS NOT DISTINCT FROM v_actor_candidate
          OR (is_system_event = true AND NEW.is_system_event = true)
      )
      AND created_at >= (timezone('utc'::text, now()) - interval '5 seconds')
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        -- Merge custom remarks and assigned info into existing authoritative event
        UPDATE public.complaint_status_history
        SET 
            remarks = COALESCE(NULLIF(NEW.remarks, ''), remarks),
            assigned_to_tier = COALESCE(NEW.assigned_to_tier, assigned_to_tier),
            assigned_to_name = COALESCE(NEW.assigned_to_name, assigned_to_name),
            actor_display_name = COALESCE(NEW.actor_display_name, actor_display_name)
        WHERE id = v_existing_id;
        
        -- Cancel duplicate insert
        RETURN NULL;
    END IF;

    -- If snapshot fields are missing, populate them
    IF NEW.actor_display_name IS NULL THEN
        NEW.actor_user_id := COALESCE(NEW.actor_user_id, NEW.changed_by, auth.uid());
        NEW.changed_by := NEW.actor_user_id;

        IF NEW.actor_user_id IS NULL THEN
            NEW.is_system_event := true;
            NEW.actor_display_name := 'System Redressal Engine (AUTOMATED)';
            NEW.actor_role := 'SYSTEM';
            NEW.actor_designation := 'Automated System';
        ELSE
            SELECT p.full_name, p.role, p.department_id, d.name AS dept_name,
                   p.designation, p.academic_program, al.level_number
            INTO v_profile
            FROM public.profiles p
            LEFT JOIN public.departments d ON d.id = p.department_id
            LEFT JOIN public.authority_levels al ON al.id = p.authority_level_id
            WHERE p.id = NEW.actor_user_id;

            IF FOUND THEN
                NEW.actor_display_name := v_profile.full_name;
                NEW.actor_role := v_profile.role::TEXT;
                NEW.actor_department_id := v_profile.department_id;
                NEW.actor_department_name := v_profile.dept_name;
                NEW.actor_authority_level := v_profile.level_number;
                IF v_profile.role = 'student' THEN
                    NEW.actor_designation := COALESCE(v_profile.academic_program || ' Student', 'Student');
                ELSE
                    NEW.actor_designation := v_profile.designation;
                END IF;
            END IF;
        END IF;
    END IF;

    IF NEW.event_type IS NULL THEN
        NEW.event_type := CASE 
            WHEN NEW.new_status = 'PENDING' THEN 'SUBMITTED'
            WHEN NEW.new_status = 'UNDER_REVIEW' THEN 'UNDER_REVIEW'
            WHEN NEW.new_status = 'RESOLVED' THEN 'RESOLVED'
            WHEN NEW.new_status = 'REJECTED' THEN 'REJECTED'
            WHEN NEW.new_status = 'ESCALATED' AND NEW.is_system_event THEN 'SYSTEM_ESCALATION'
            WHEN NEW.new_status = 'ESCALATED' THEN 'FORWARDED'
            WHEN NEW.new_status = 'CUTOFF_PAUSED' THEN 'PAUSED'
            ELSE 'STATUS_CHANGE'
        END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_dedup_and_snapshot_status_history ON public.complaint_status_history;
CREATE TRIGGER trg_dedup_and_snapshot_status_history
    BEFORE INSERT ON public.complaint_status_history
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_complaint_status_history_dedup_and_snapshot();

-- 5. Row Level Security: Allow authenticated users to view profiles
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
CREATE POLICY "Profiles are viewable by authenticated users"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

-- 6. Backfill existing complaint_status_history records
UPDATE public.complaint_status_history h
SET 
    actor_user_id = h.changed_by,
    actor_display_name = CASE 
        WHEN h.changed_by IS NULL THEN 'System Redressal Engine (AUTOMATED)'
        ELSE p.full_name
    END,
    actor_role = CASE 
        WHEN h.changed_by IS NULL THEN 'SYSTEM'
        ELSE p.role::TEXT
    END,
    actor_department_id = p.department_id,
    actor_department_name = d.name,
    actor_authority_level = al.level_number,
    actor_designation = CASE 
        WHEN h.changed_by IS NULL THEN 'Automated System'
        WHEN p.role = 'student' THEN COALESCE(p.academic_program || ' Student', 'Student')
        ELSE p.designation
    END,
    event_type = CASE 
        WHEN h.new_status = 'PENDING' THEN 'SUBMITTED'
        WHEN h.new_status = 'UNDER_REVIEW' THEN 'UNDER_REVIEW'
        WHEN h.new_status = 'RESOLVED' THEN 'RESOLVED'
        WHEN h.new_status = 'REJECTED' THEN 'REJECTED'
        WHEN h.new_status = 'ESCALATED' AND h.changed_by IS NULL THEN 'SYSTEM_ESCALATION'
        WHEN h.new_status = 'ESCALATED' THEN 'FORWARDED'
        WHEN h.new_status = 'CUTOFF_PAUSED' THEN 'PAUSED'
        ELSE 'STATUS_CHANGE'
    END,
    is_system_event = (h.changed_by IS NULL)
FROM public.complaint_status_history h2
LEFT JOIN public.profiles p ON p.id = h2.changed_by
LEFT JOIN public.departments d ON d.id = p.department_id
LEFT JOIN public.authority_levels al ON al.id = p.authority_level_id
WHERE h.id = h2.id
  AND (h.actor_display_name IS NULL OR h.actor_designation IS NULL);
