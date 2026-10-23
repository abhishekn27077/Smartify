import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/screens/authority_staff_workload_screen.dart';
import 'package:smartify/features/admin/screens/department_grievances_screen.dart';
import 'package:smartify/features/admin/services/admin_service.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';
import 'package:smartify/features/analytics/screens/analytics_dashboard_screen.dart';
import 'package:smartify/features/analytics/services/analytics_service.dart';
import 'package:smartify/features/complaints/models/department_model.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Department Dashboard Screen
/// Delivers a focused, strictly department-scoped view containing only metrics,
/// workload, and grievances for the selected department.
class DepartmentDashboardScreen extends StatefulWidget {
  final DepartmentModel department;

  const DepartmentDashboardScreen({super.key, required this.department});

  @override
  State<DepartmentDashboardScreen> createState() =>
      _DepartmentDashboardScreenState();
}

class _DepartmentDashboardScreenState extends State<DepartmentDashboardScreen> {
  final AnalyticsService _analyticsService = AnalyticsService();
  final AdminService _adminService = AdminService();

  AnalyticsDataModel? _analytics;
  List<GrievanceModel> _recentGrievances = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDepartmentData();
  }

  Future<void> _loadDepartmentData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _analyticsService.fetchAnalytics(departmentId: widget.department.id),
        _adminService.fetchComplaints(departmentId: widget.department.id),
      ]);

      if (mounted) {
        final grievances = results[1] as List<GrievanceModel>;
        grievances.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        setState(() {
          _analytics = results[0] as AnalyticsDataModel;
          _recentGrievances = grievances;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load department data: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _getConciseTitle(String code, String name) {
    final upper = code.toUpperCase().trim();
    if (upper == 'MCA') return 'MCA Department';
    if (upper == 'MBA') return 'MBA Department';
    if (upper == 'MCOM' || upper == 'M.COM') return 'M.Com Department';
    if (upper == 'HOSTEL') return 'Hostel Department';
    if (upper == 'INFRA') return 'Campus Facilities';
    if (upper == 'FIN' || upper == 'ACCOUNTS') return 'Finance Department';
    if (upper == 'IT' || upper == 'LIBRARY') return 'Library & IT';
    if (name.startsWith('Department of ')) {
      return '${name.replaceFirst('Department of ', '')} Dept';
    }
    return name.length > 20 ? '$code Department' : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dept = widget.department;
    final data = _analytics;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getConciseTitle(dept.code, dept.name),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadDepartmentData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
              height: 1),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.space16),
                child: StateLoadingShimmer(height: 300),
              )
            : _errorMessage != null
                ? StateErrorView(
                    message: _errorMessage!,
                    onRetry: _loadDepartmentData,
                  )
                : RefreshIndicator(
                    onRefresh: _loadDepartmentData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(AppSpacing.space16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Department Identity Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.space16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMedium),
                              border: Border.all(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.domain_rounded,
                                      color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: AppSpacing.space14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dept.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Code: ${dept.code} • Institutional Department Scope',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: AppSpacing.space20),

                          // 2. Summary KPI Grid
                          Text(
                            'Department Grievance Breakdown',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space10),

                          if (data != null) ...[
                            GridView.count(
                              crossAxisCount: 3,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1.15,
                              children: [
                                _buildMetricBox(
                                  'Total',
                                  data.totalSubmitted.toString(),
                                  theme.colorScheme.primary,
                                  Icons.assignment_outlined,
                                  theme,
                                ),
                                _buildMetricBox(
                                  'Pending',
                                  data.totalPending.toString(),
                                  AppColors.statusPending,
                                  Icons.hourglass_top_rounded,
                                  theme,
                                ),
                                _buildMetricBox(
                                  'Under Review',
                                  data.totalUnderReview.toString(),
                                  AppColors.statusUnderReview,
                                  Icons.sync_rounded,
                                  theme,
                                ),
                                _buildMetricBox(
                                  'Resolved',
                                  data.totalResolved.toString(),
                                  AppColors.statusResolved,
                                  Icons.check_circle_outline_rounded,
                                  theme,
                                ),
                                _buildMetricBox(
                                  'Rejected',
                                  data.totalRejected.toString(),
                                  AppColors.error,
                                  Icons.cancel_outlined,
                                  theme,
                                ),
                                _buildMetricBox(
                                  'Escalated',
                                  data.totalEscalated.toString(),
                                  AppColors.secondary,
                                  Icons.trending_up_rounded,
                                  theme,
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.space16),

                            // 3. Performance Metrics
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.space16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusMedium),
                                border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.5)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildPerformanceItem(
                                        label: 'Resolution Rate',
                                        value:
                                            '${data.resolutionRate.toStringAsFixed(1)}%',
                                        color: AppColors.statusResolved,
                                        icon: Icons.pie_chart_outline_rounded,
                                        theme: theme,
                                      ),
                                      Container(
                                        height: 40,
                                        width: 1,
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.4),
                                      ),
                                      _buildPerformanceItem(
                                        label: 'Avg Resolution Time',
                                        value: AppDateTimeUtils.formatAverageResolution(
                                          data.totalResolved,
                                          data.averageResolutionDays,
                                        ),
                                        color: theme.colorScheme.primary,
                                        icon: Icons.timer_outlined,
                                        theme: theme,
                                      ),
                                      Container(
                                        height: 40,
                                        width: 1,
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.4),
                                      ),
                                      _buildPerformanceItem(
                                        label: 'Overdue / Breached',
                                        value: data.overdueCount.toString(),
                                        color: AppColors.error,
                                        icon: Icons.warning_amber_rounded,
                                        theme: theme,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: AppSpacing.space20),

                          // 4. Authority Workload in This Department
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Department Authority Workload',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          AuthorityStaffWorkloadScreen(
                                        departmentId: dept.id,
                                        departmentName: dept.name,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('View Staff',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space8),

                          if (data?.authorityWorkload.isEmpty ?? true)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.space16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                                border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'No authority staff assigned to this department caseload yet.',
                                style: TextStyle(
                                    fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            )
                          else
                            ...data!.authorityWorkload.map((staff) {
                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusSmall),
                                  side: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.4)),
                                ),
                                child: ListTile(
                                  visualDensity: VisualDensity.compact,
                                  leading: CircleAvatar(
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.15),
                                    child: Icon(Icons.shield_outlined,
                                        size: 18,
                                        color: theme.colorScheme.primary),
                                  ),
                                  title: Text(staff.fullName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  subtitle: Text(staff.authorityLevelTitle,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.65))),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: staff.activeCaseload > 0
                                          ? AppColors.primary
                                              .withValues(alpha: 0.15)
                                          : AppColors.statusResolved
                                              .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusPill),
                                    ),
                                    child: Text(
                                      '${staff.activeCaseload} Active',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: staff.activeCaseload > 0
                                            ? AppColors.primary
                                            : AppColors.statusResolved,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),

                          const SizedBox(height: AppSpacing.space20),

                          // 5. Recent Department Grievances
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recent ${dept.name} Grievances',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          DepartmentGrievancesScreen(
                                        department: dept,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('View All',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space8),

                          if (_recentGrievances.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.space20),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                                border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      size: 32,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4)),
                                  const SizedBox(height: 6),
                                  Text(
                                    'No grievances recorded for ${dept.name}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          else
                            ..._recentGrievances.take(4).map((g) {
                              return _buildRecentGrievanceCard(g, theme);
                            }),

                          const SizedBox(height: AppSpacing.space24),

                          // 6. Navigation Buttons
                          Column(
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSmall),
                                  ),
                                ),
                                icon: const Icon(Icons.list_alt_rounded),
                                label: Text('View All ${dept.name} Grievances'),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          DepartmentGrievancesScreen(
                                        department: dept,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSmall),
                                  ),
                                ),
                                icon: const Icon(Icons.insights_rounded),
                                label: Text('View ${dept.name} Analytics'),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const AnalyticsDashboardScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: AppSpacing.space32),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildMetricBox(
      String label, String value, Color color, IconData icon, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentGrievanceCard(GrievanceModel grievance, ThemeData theme) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        side:
            BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComplaintDetailScreen(grievance: grievance),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    grievance.trackingNumber,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  GrievanceStatusBadge(
                      status: grievance.status, isCompact: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                grievance.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Student: ${(grievance.studentName != null && grievance.studentName!.trim().isNotEmpty) ? grievance.studentName! : "Student information unavailable"}',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppDateTimeUtils.formatLocalDate(grievance.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
