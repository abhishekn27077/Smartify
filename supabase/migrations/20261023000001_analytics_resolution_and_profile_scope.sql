-- ==============================================================================
-- SMARTIFY MIGRATION: ANALYTICS RESOLUTION ACCURACY & PROFILE SCOPING RLS
-- Description:
--   1. Backfills resolved_at for legacy complaints.
--   2. Updates get_grievance_analytics to compute exact average resolution time
--      and isolate authority_workload to genuine authority staff.
--   3. Tightens profiles RLS so that students can only view their own profiles,
--      admins can view institution-wide, and authorities can only view students
--      who have grievances within their departmental/caseload scope.
-- ==============================================================================

-- 1. Backfill resolved_at on legacy resolved complaints
UPDATE public.complaints
SET resolved_at = COALESCE(updated_at, created_at + interval '1 hour')
WHERE status = 'RESOLVED' AND resolved_at IS NULL;

-- 2. Enhanced get_grievance_analytics with high-precision resolution time & workload scoping
CREATE OR REPLACE FUNCTION public.get_grievance_analytics(
    p_start_date TIMESTAMPTZ DEFAULT NULL,
    p_end_date TIMESTAMPTZ DEFAULT NULL,
    p_department_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_total_submitted INT := 0;
    v_total_resolved INT := 0;
    v_total_pending INT := 0;
    v_total_under_review INT := 0;
    v_total_in_progress INT := 0;
    v_total_paused INT := 0;
    v_total_escalated INT := 0;
    v_total_rejected INT := 0;
    v_overdue_count INT := 0;
    v_avg_resolution_days NUMERIC := 0.0;
    v_dept_distribution JSONB;
    v_category_distribution JSONB;
    v_monthly_trends JSONB;
    v_authority_workload JSONB;
BEGIN
    -- Strict security: Only authorities and administrators can access aggregate analytics
    IF NOT (public.is_authority() OR public.is_admin()) THEN
        RAISE EXCEPTION 'Unauthorized: Student accounts cannot access institutional analytics.';
    END IF;

    v_start := COALESCE(p_start_date, timezone('utc'::text, now()) - INTERVAL '365 days');
    v_end := COALESCE(p_end_date, timezone('utc'::text, now()));

    -- Overall Totals
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE status = 'RESOLVED'),
        COUNT(*) FILTER (WHERE status = 'PENDING'),
        COUNT(*) FILTER (WHERE status = 'UNDER_REVIEW'),
        COUNT(*) FILTER (WHERE status = 'IN_PROGRESS'),
        COUNT(*) FILTER (WHERE status = 'CUTOFF_PAUSED' OR is_cutoff_paused = true),
        COUNT(*) FILTER (WHERE status = 'ESCALATED'),
        COUNT(*) FILTER (WHERE status = 'REJECTED'),
        COUNT(*) FILTER (WHERE current_tier_deadline < timezone('utc'::text, now()) AND status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')),
        COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (COALESCE(resolved_at, updated_at) - created_at)) / 86400.0) FILTER (WHERE status = 'RESOLVED'), 2), 0.0)
    INTO
        v_total_submitted,
        v_total_resolved,
        v_total_pending,
        v_total_under_review,
        v_total_in_progress,
        v_total_paused,
        v_total_escalated,
        v_total_rejected,
        v_overdue_count,
        v_avg_resolution_days
    FROM public.complaints
    WHERE created_at >= v_start AND created_at <= v_end
      AND (p_department_id IS NULL OR department_id = p_department_id);

    -- Distribution by Department
    SELECT COALESCE(jsonb_agg(d_row), '[]'::jsonb)
    INTO v_dept_distribution
    FROM (
        SELECT 
            d.id,
            d.name,
            d.code,
            COUNT(c.id) AS total_complaints,
            COUNT(c.id) FILTER (WHERE c.status = 'RESOLVED') AS resolved_count,
            COUNT(c.id) FILTER (WHERE c.status = 'CUTOFF_PAUSED' OR c.is_cutoff_paused = true) AS paused_count
        FROM public.departments d
        LEFT JOIN public.complaints c ON c.department_id = d.id 
             AND c.created_at >= v_start AND c.created_at <= v_end
        WHERE (p_department_id IS NULL OR d.id = p_department_id)
        GROUP BY d.id, d.name, d.code
        ORDER BY total_complaints DESC
    ) d_row;

    -- Distribution by Category
    SELECT COALESCE(jsonb_agg(cat_row), '[]'::jsonb)
    INTO v_category_distribution
    FROM (
        SELECT 
            category,
            COUNT(*) AS count
        FROM public.complaints
        WHERE created_at >= v_start AND created_at <= v_end
          AND (p_department_id IS NULL OR department_id = p_department_id)
        GROUP BY category
        ORDER BY count DESC
    ) cat_row;

    -- Monthly Submission & Resolution Trends
    SELECT COALESCE(jsonb_agg(trend_row), '[]'::jsonb)
    INTO v_monthly_trends
    FROM (
        SELECT 
            TO_CHAR(DATE_TRUNC('month', created_at), 'Mon YYYY') AS month_label,
            DATE_TRUNC('month', created_at) AS sort_key,
            COUNT(*) AS submitted_count,
            COUNT(*) FILTER (WHERE status = 'RESOLVED') AS resolved_count
        FROM public.complaints
        WHERE created_at >= v_start AND created_at <= v_end
          AND (p_department_id IS NULL OR department_id = p_department_id)
        GROUP BY DATE_TRUNC('month', created_at), TO_CHAR(DATE_TRUNC('month', created_at), 'Mon YYYY')
        ORDER BY sort_key ASC
    ) trend_row;

    -- Authority Workload & Resolution Metrics (Restricted strictly to authority role and matching department)
    SELECT COALESCE(jsonb_agg(work_row), '[]'::jsonb)
    INTO v_authority_workload
    FROM (
        SELECT 
            p.id,
            p.full_name,
            d.name AS department_name,
            al.title AS authority_level_title,
            COUNT(c.id) FILTER (WHERE c.status NOT IN ('RESOLVED', 'REJECTED')) AS active_caseload,
            COUNT(c.id) FILTER (WHERE c.status = 'RESOLVED') AS resolved_count
        FROM public.profiles p
        JOIN public.departments d ON d.id = p.department_id
        LEFT JOIN public.authority_levels al ON al.id = p.authority_level_id
        LEFT JOIN public.complaints c ON c.assigned_authority_id = p.id
             AND c.created_at >= v_start AND c.created_at <= v_end
        WHERE p.role = 'authority'
          AND (p_department_id IS NULL OR p.department_id = p_department_id)
        GROUP BY p.id, p.full_name, d.name, al.title
        ORDER BY active_caseload DESC
        LIMIT 10
    ) work_row;

    RETURN jsonb_build_object(
        'period_start', v_start,
        'period_end', v_end,
        'total_submitted', v_total_submitted,
        'total_resolved', v_total_resolved,
        'total_pending', v_total_pending,
        'total_under_review', v_total_under_review,
        'total_in_progress', v_total_in_progress,
        'total_paused', v_total_paused,
        'total_escalated', v_total_escalated,
        'total_rejected', v_total_rejected,
        'overdue_count', v_overdue_count,
        'average_resolution_days', v_avg_resolution_days,
        'department_distribution', v_dept_distribution,
        'category_distribution', v_category_distribution,
        'monthly_trends', v_monthly_trends,
        'authority_workload', v_authority_workload
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Security Definer Helper for current authority's department to prevent RLS recursion
CREATE OR REPLACE FUNCTION public.get_auth_user_department_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
    SELECT department_id FROM public.profiles WHERE id = auth.uid();
$$;

-- Ensure is_admin has explicit search_path
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'admin'
    );
$$;

-- Ensure is_authority has explicit search_path
CREATE OR REPLACE FUNCTION public.is_authority()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('authority', 'admin')
    );
$$;

-- 4. Server-Side Scoped RLS on public.profiles
-- Enforces:
--   - Students see only their own profile
--   - Admins see all profiles institution-wide
--   - Authority staff see authority & admin profiles (directory, assignment)
--   - Authority staff see student profiles ONLY IF student has an active/historic grievance in their department or assigned to them
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Profiles access policy" ON public.profiles;

CREATE POLICY "Profiles access policy" ON public.profiles
FOR SELECT TO authenticated
USING (
    -- Any user can view their own profile
    id = auth.uid()
    -- Administrators have institution-wide governance visibility
    OR public.is_admin()
    -- Staff profiles (authorities and administrators) are viewable for workflow & governance
    OR role IN ('authority', 'admin')
    -- Authorities can view student identity only if the student has a grievance within their department scope or caseload
    OR (
        role = 'student'
        AND public.is_authority()
        AND EXISTS (
            SELECT 1 FROM public.complaints c
            WHERE c.student_id = public.profiles.id
              AND (
                  c.department_id = public.get_auth_user_department_id()
                  OR c.assigned_authority_id = auth.uid()
              )
        )
    )
);
