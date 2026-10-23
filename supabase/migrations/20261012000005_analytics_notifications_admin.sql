-- ==============================================================================
-- SMARTIFY MIGRATION 005: ANALYTICS, NOTIFICATION DE-DUPLICATION & ADMIN ACTIONS
-- Description: Server-side aggregated grievance analytics, deduplicated notification
--              pipeline, and protected administrative governance functions.
-- Target: Supabase PostgreSQL (Version 15+)
-- ==============================================================================

-- 1. Server-Side Aggregated Grievance Analytics Function
-- Enforces role protection (Staff and Admins only; Students blocked).
-- Computes real database aggregations: status breakdown, department distribution,
-- category distribution, monthly trends, average resolution time, and authority workload.

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
        COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (resolved_at - created_at)) / 86400.0) FILTER (WHERE status = 'RESOLVED' AND resolved_at IS NOT NULL), 1), 0.0)
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

    -- Monthly Submission & Resolution Trends (Last 6-12 Months)
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

    -- Authority Workload & Resolution Metrics
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
        WHERE p.role IN ('authority', 'admin')
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


-- 2. Deduplicated Notification Pipeline Function
-- Prevents duplicate in-app notifications if automated cron jobs retry or run concurrently.

CREATE OR REPLACE FUNCTION public.send_deduped_notification(
    p_user_id UUID,
    p_complaint_id UUID,
    p_title TEXT,
    p_message TEXT,
    p_type notification_type,
    p_window_minutes INT DEFAULT 60
)
RETURNS UUID AS $$
DECLARE
    v_existing_id UUID;
    v_new_id UUID;
BEGIN
    -- Check for duplicate notification within the debounce window
    SELECT id INTO v_existing_id
    FROM public.notifications
    WHERE user_id = p_user_id
      AND complaint_id = p_complaint_id
      AND notification_type = p_type
      AND created_at >= (timezone('utc'::text, now()) - (p_window_minutes || ' minutes')::INTERVAL)
    LIMIT 1;

    IF FOUND THEN
        -- Duplicate detected within window: return existing notification ID without re-inserting
        RETURN v_existing_id;
    END IF;

    -- Insert new notification
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        title,
        message,
        notification_type,
        created_at
    ) VALUES (
        p_user_id,
        p_complaint_id,
        p_title,
        p_message,
        p_type,
        timezone('utc'::text, now())
    ) RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. Administrative User & Role Governance Function
-- Strictly restricts role modifications to approved Administrators.
-- Records immutable audit trail of role grants and department reassignments.

CREATE OR REPLACE FUNCTION public.admin_update_profile_role(
    p_target_user_id UUID,
    p_new_role app_role,
    p_department_id UUID DEFAULT NULL,
    p_authority_level_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_target RECORD;
    v_old_role app_role;
BEGIN
    -- Only administrators may modify roles
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can modify roles and department assignments.';
    END IF;

    SELECT * INTO v_target FROM public.profiles WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found.';
    END IF;

    v_old_role := v_target.role;

    -- Update profile
    UPDATE public.profiles
    SET role = p_new_role,
        department_id = p_department_id,
        authority_level_id = p_authority_level_id,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_target_user_id;

    -- Record in audit logs
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        auth.uid(),
        'ADMIN_ROLE_UPDATED',
        'profiles',
        p_target_user_id,
        jsonb_build_object(
            'old_role', v_old_role,
            'new_role', p_new_role,
            'department_id', p_department_id,
            'authority_level_id', p_authority_level_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_target_user_id,
        'new_role', p_new_role
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. Administrative Authority Level SLA Configuration Function
CREATE OR REPLACE FUNCTION public.admin_update_authority_sla(
    p_level_id UUID,
    p_new_sla_days INT
)
RETURNS JSONB AS $$
DECLARE
    v_level RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can update authority SLA deadlines.';
    END IF;

    IF p_new_sla_days < 1 OR p_new_sla_days > 14 THEN
        RAISE EXCEPTION 'SLA days must be between 1 and 14 calendar days.';
    END IF;

    SELECT * INTO v_level FROM public.authority_levels WHERE id = p_level_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Authority level not found.';
    END IF;

    UPDATE public.authority_levels
    SET sla_days = p_new_sla_days
    WHERE id = p_level_id;

    -- Audit log
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        auth.uid(),
        'ADMIN_SLA_UPDATED',
        'authority_levels',
        p_level_id,
        jsonb_build_object(
            'level_number', v_level.level_number,
            'old_sla', v_level.sla_days,
            'new_sla', p_new_sla_days
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'level_id', p_level_id,
        'new_sla_days', p_new_sla_days
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 5. Administrative Department Status Toggle Function
CREATE OR REPLACE FUNCTION public.admin_toggle_department(
    p_department_id UUID,
    p_is_active BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_dept RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can toggle department active status.';
    END IF;

    SELECT * INTO v_dept FROM public.departments WHERE id = p_department_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Department not found.';
    END IF;

    UPDATE public.departments
    SET is_active = p_is_active
    WHERE id = p_department_id;

    -- Audit log
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        auth.uid(),
        'ADMIN_DEPARTMENT_STATUS_TOGGLED',
        'departments',
        p_department_id,
        jsonb_build_object(
            'department_code', v_dept.code,
            'is_active', p_is_active
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'department_id', p_department_id,
        'is_active', p_is_active
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
