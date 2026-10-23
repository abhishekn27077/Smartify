-- ==============================================================================
-- SMARTIFY Migration: Authority Queue Polish, Deterministic Server-Side Ordering,
-- Title Normalization & Exact Queue Summaries
-- Migration ID: 20261019000002_authority_queue_polish.sql
-- ==============================================================================

-- 1. Clean up authority level titles: Remove misleading "Faculty Advisor / Hostel Warden"
UPDATE public.authority_levels
SET title = 'Level 1: Faculty / Department Officer'
WHERE level_number = 1;

UPDATE public.authority_levels
SET title = 'Level 2: Head of Department (HoD)'
WHERE level_number = 2;

UPDATE public.authority_levels
SET title = 'Level 3: Dean / Academic Dean'
WHERE level_number = 3;

-- 2. Clean up profile designations across all real authority accounts
-- Academic MCA
UPDATE public.profiles
SET designation = 'Level 1 — Faculty / Department Officer'
WHERE email = 'faculty.demo@campus.edu';

UPDATE public.profiles
SET designation = 'Level 2 — Head of Department (HoD)'
WHERE email = 'hod.demo@campus.edu';

UPDATE public.profiles
SET designation = 'Level 3 — MCA Dean'
WHERE email = 'dean.demo@campus.edu';

-- Academic MBA
UPDATE public.profiles
SET designation = 'Level 1 — Faculty / Department Officer'
WHERE email = 'mba.faculty@campus.edu';

UPDATE public.profiles
SET designation = 'Level 2 — Head of Department (HoD)'
WHERE email = 'mba.hod@campus.edu';

UPDATE public.profiles
SET designation = 'Level 3 — MBA Dean'
WHERE email = 'mba.dean@campus.edu';

-- Academic M.Com
UPDATE public.profiles
SET designation = 'Level 1 — Faculty / Department Officer'
WHERE email = 'mcom.faculty@campus.edu';

UPDATE public.profiles
SET designation = 'Level 2 — Head of Department (HoD)'
WHERE email = 'mcom.hod@campus.edu';

UPDATE public.profiles
SET designation = 'Level 3 — M.Com Dean'
WHERE email = 'mcom.dean@campus.edu';

-- Operational Authorities
UPDATE public.profiles
SET designation = 'Level 1 — Hostel Warden'
WHERE email IN ('warden.demo@campus.edu', 'authority.demo@campus.edu');

UPDATE public.profiles
SET designation = 'Level 1 — IT Officer'
WHERE email = 'it.demo@campus.edu';

UPDATE public.profiles
SET designation = 'Level 1 — Accounts Officer'
WHERE email = 'finance.demo@campus.edu';

UPDATE public.profiles
SET designation = 'Level 1 — Campus Facility Officer'
WHERE email = 'infra.demo@campus.edu';

UPDATE public.profiles
SET designation = 'Campus Administrator'
WHERE email = 'admin.demo@campus.edu';

-- 3. Deterministic Server-Side Authority Queue RPC
CREATE OR REPLACE FUNCTION public.get_authority_redressal_queue(
    p_status_filter TEXT DEFAULT 'ALL',
    p_sort_option TEXT DEFAULT 'PRIORITY_SLA',
    p_search_query TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_user_role TEXT;
    v_user_dept_id UUID;
    v_user_level_id UUID;
    v_is_admin BOOLEAN;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT role::TEXT, department_id, authority_level_id
    INTO v_user_role, v_user_dept_id, v_user_level_id
    FROM public.profiles
    WHERE id = v_user_id;

    IF v_user_role IS NULL OR v_user_role NOT IN ('authority', 'admin') THEN
        RAISE EXCEPTION 'Access denied: caller does not hold an authority role.';
    END IF;

    v_is_admin := (v_user_role = 'admin');

    SELECT COALESCE(jsonb_agg(q_row), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT 
            c.id,
            c.tracking_number,
            c.student_id,
            c.department_id,
            c.current_authority_level_id,
            c.assigned_authority_id,
            c.title,
            c.description,
            c.category,
            c.incident_date,
            c.status::TEXT AS status,
            c.priority::TEXT AS priority,
            c.current_tier_deadline,
            c.cutoff_deadline,
            c.is_cutoff_paused,
            c.paused_at,
            c.resumed_at,
            c.resolution_notes,
            c.resolved_at,
            c.created_at,
            c.updated_at,
            jsonb_build_object('name', d.name, 'code', d.code) AS departments,
            jsonb_build_object('level_number', al.level_number, 'title', al.title, 'sla_days', al.sla_days) AS authority_levels,
            CASE WHEN p_stud.id IS NOT NULL THEN jsonb_build_object('full_name', p_stud.full_name) ELSE NULL END AS student_profile,
            CASE WHEN p_auth.id IS NOT NULL THEN jsonb_build_object('full_name', p_auth.full_name) ELSE NULL END AS authority_profile,
            COALESCE(
                (SELECT jsonb_agg(jsonb_build_object('file_path', att.file_path))
                 FROM public.complaint_attachments att
                 WHERE att.complaint_id = c.id),
                '[]'::jsonb
            ) AS complaint_attachments
        FROM public.complaints c
        JOIN public.departments d ON c.department_id = d.id
        JOIN public.authority_levels al ON c.current_authority_level_id = al.id
        LEFT JOIN public.profiles p_stud ON c.student_id = p_stud.id
        LEFT JOIN public.profiles p_auth ON c.assigned_authority_id = p_auth.id
        WHERE 
            -- Role & Department / Tier Scoping
            (
                v_is_admin 
                OR (
                    c.department_id = v_user_dept_id 
                    AND (
                        c.current_authority_level_id = v_user_level_id 
                        OR c.assigned_authority_id = v_user_id
                        OR v_user_level_id IS NULL
                    )
                )
                OR c.assigned_authority_id = v_user_id
            )
            -- Status Filter
            AND (
                CASE 
                    WHEN p_status_filter IS NULL OR p_status_filter = 'ALL' 
                        THEN c.status NOT IN ('RESOLVED', 'REJECTED')
                    WHEN p_status_filter = 'PENDING' 
                        THEN c.status = 'PENDING'
                    WHEN p_status_filter = 'UNDER_REVIEW' 
                        THEN c.status = 'UNDER_REVIEW'
                    WHEN p_status_filter = 'IN_PROGRESS' 
                        THEN c.status = 'IN_PROGRESS'
                    WHEN p_status_filter = 'ESCALATED' 
                        THEN c.status = 'ESCALATED'
                    WHEN p_status_filter = 'DUE_SOON' 
                        THEN c.status NOT IN ('RESOLVED', 'REJECTED') 
                             AND c.current_tier_deadline > timezone('utc'::text, now()) 
                             AND c.current_tier_deadline <= (timezone('utc'::text, now()) + interval '24 hours')
                    WHEN p_status_filter = 'OVERDUE' 
                        THEN c.status NOT IN ('RESOLVED', 'REJECTED') 
                             AND c.current_tier_deadline < timezone('utc'::text, now())
                    WHEN p_status_filter = 'RESOLVED' 
                        THEN c.status = 'RESOLVED'
                    WHEN p_status_filter = 'REJECTED' 
                        THEN c.status = 'REJECTED'
                    ELSE c.status::TEXT = p_status_filter
                END
            )
            -- Search Query
            AND (
                p_search_query IS NULL 
                OR trim(p_search_query) = '' 
                OR c.tracking_number ILIKE '%' || trim(p_search_query) || '%'
                OR c.title ILIKE '%' || trim(p_search_query) || '%'
                OR c.category ILIKE '%' || trim(p_search_query) || '%'
                OR (p_stud.full_name IS NOT NULL AND p_stud.full_name ILIKE '%' || trim(p_search_query) || '%')
            )
        ORDER BY
            CASE 
                WHEN p_sort_option = 'NEWEST' THEN NULL
                WHEN p_sort_option = 'OLDEST' THEN NULL
                WHEN p_sort_option = 'DEADLINE' THEN NULL
                WHEN p_sort_option = 'STATUS' THEN NULL
                ELSE 
                    -- Default 'PRIORITY_SLA':
                    -- 1. Overdue / breached active grievances
                    -- 2. Due soon / SLA-critical active grievances (within 24h)
                    -- 3. Pending Intake / newly submitted grievances
                    -- 4. Under Review / In Progress / Escalated
                    -- 5. Other active grievances
                    -- 6. Terminal (Resolved / Rejected)
                    CASE
                        WHEN c.status NOT IN ('RESOLVED', 'REJECTED') 
                             AND c.current_tier_deadline < timezone('utc'::text, now()) 
                            THEN 1
                        WHEN c.status NOT IN ('RESOLVED', 'REJECTED') 
                             AND c.current_tier_deadline <= (timezone('utc'::text, now()) + interval '24 hours') 
                            THEN 2
                        WHEN c.status = 'PENDING' 
                            THEN 3
                        WHEN c.status IN ('UNDER_REVIEW', 'IN_PROGRESS', 'ESCALATED') 
                            THEN 4
                        WHEN c.status NOT IN ('RESOLVED', 'REJECTED') 
                            THEN 5
                        ELSE 6
                    END
            END ASC NULLS LAST,
            -- Sort tie-breakers & explicit sort options
            CASE WHEN p_sort_option = 'NEWEST' THEN c.created_at END DESC NULLS LAST,
            CASE WHEN p_sort_option = 'OLDEST' THEN c.created_at END ASC NULLS LAST,
            CASE WHEN p_sort_option = 'DEADLINE' THEN c.current_tier_deadline END ASC NULLS LAST,
            CASE WHEN p_sort_option = 'STATUS' THEN c.status::TEXT END ASC NULLS LAST,
            c.created_at DESC,
            c.tracking_number DESC
    ) q_row;

    RETURN v_result;
END;
$$;

-- 4. Authoritative Queue Summary Counts RPC
CREATE OR REPLACE FUNCTION public.get_authority_queue_summary()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_user_role TEXT;
    v_user_dept_id UUID;
    v_user_level_id UUID;
    v_is_admin BOOLEAN;
    v_total_active INT := 0;
    v_pending INT := 0;
    v_under_review INT := 0;
    v_in_progress INT := 0;
    v_escalated INT := 0;
    v_due_soon INT := 0;
    v_overdue INT := 0;
    v_resolved INT := 0;
    v_rejected INT := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT role::TEXT, department_id, authority_level_id
    INTO v_user_role, v_user_dept_id, v_user_level_id
    FROM public.profiles
    WHERE id = v_user_id;

    IF v_user_role IS NULL OR v_user_role NOT IN ('authority', 'admin') THEN
        RAISE EXCEPTION 'Access denied.';
    END IF;

    v_is_admin := (v_user_role = 'admin');

    SELECT
        COUNT(*) FILTER (WHERE c.status NOT IN ('RESOLVED', 'REJECTED')),
        COUNT(*) FILTER (WHERE c.status = 'PENDING'),
        COUNT(*) FILTER (WHERE c.status = 'UNDER_REVIEW'),
        COUNT(*) FILTER (WHERE c.status = 'IN_PROGRESS'),
        COUNT(*) FILTER (WHERE c.status = 'ESCALATED'),
        COUNT(*) FILTER (WHERE c.status NOT IN ('RESOLVED', 'REJECTED') 
                               AND c.current_tier_deadline > timezone('utc'::text, now()) 
                               AND c.current_tier_deadline <= (timezone('utc'::text, now()) + interval '24 hours')),
        COUNT(*) FILTER (WHERE c.status NOT IN ('RESOLVED', 'REJECTED') 
                               AND c.current_tier_deadline < timezone('utc'::text, now())),
        COUNT(*) FILTER (WHERE c.status = 'RESOLVED'),
        COUNT(*) FILTER (WHERE c.status = 'REJECTED')
    INTO
        v_total_active,
        v_pending,
        v_under_review,
        v_in_progress,
        v_escalated,
        v_due_soon,
        v_overdue,
        v_resolved,
        v_rejected
    FROM public.complaints c
    WHERE (
        v_is_admin 
        OR (
            c.department_id = v_user_dept_id 
            AND (
                c.current_authority_level_id = v_user_level_id 
                OR c.assigned_authority_id = v_user_id
                OR v_user_level_id IS NULL
            )
        )
        OR c.assigned_authority_id = v_user_id
    );

    RETURN jsonb_build_object(
        'total_active', v_total_active,
        'pending_count', v_pending,
        'under_review_count', v_under_review,
        'in_progress_count', v_in_progress,
        'escalated_count', v_escalated,
        'due_soon_count', v_due_soon,
        'overdue_count', v_overdue,
        'resolved_count', v_resolved,
        'rejected_count', v_rejected
    );
END;
$$;

-- 5. Permissions
GRANT EXECUTE ON FUNCTION public.get_authority_redressal_queue(TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_authority_queue_summary() TO authenticated;
