import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';
import 'package:smartify/features/analytics/providers/analytics_provider.dart';
import 'package:smartify/features/analytics/widgets/analytics_kpi_card.dart';
import 'package:smartify/features/analytics/widgets/monthly_trend_bar_chart.dart';
import 'package:smartify/features/analytics/widgets/status_distribution_pie_chart.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/authority/providers/authority_workflow_provider.dart';
import 'package:smartify/features/authority/services/authority_service.dart';
import 'package:smartify/features/admin/screens/department_dashboard_screen.dart';
import 'package:smartify/features/complaints/models/department_model.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';

/// SMARTIFY Analytics Dashboard Screen
/// Responsive, database-backed dashboard with charts, KPI metrics, and PDF/CSV export.
class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsProvider>().loadAnalytics();
    });
  }

  Future<List<GrievanceModel>> _getScopedComplaintsForExport() async {
    final authProv = context.read<AuthorityWorkflowProvider>();
    if (authProv.queue.isNotEmpty) {
      return authProv.queue;
    }
    try {
      final queue = await AuthorityService().fetchAuthorityQueue();
      if (queue.isNotEmpty) return queue;
    } catch (e) {
      debugPrint('Error fetching scoped complaints for export: $e');
    }
    if (!mounted) return const [];
    return context.read<StudentTrackingProvider>().complaints;
  }

  void _exportCsv() async {
    final analyticsProv = context.read<AnalyticsProvider>();
    final complaints = await _getScopedComplaintsForExport();
    final file = await analyticsProv.exportToCsv(complaints);
    if (file != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV successfully generated at: ${file.path}'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  void _exportPdf() async {
    final analyticsProv = context.read<AnalyticsProvider>();
    final complaints = await _getScopedComplaintsForExport();
    final file = await analyticsProv.exportToPdf(complaints);
    if (file != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF report generated at: ${file.path}'),
          backgroundColor: AppColors.secondary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    // Student accounts cannot access institutional analytics
    if (user != null && user.isStudent) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Grievance Analytics',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.space24),
            child: Text(
              'Access Restricted: Student accounts do not have permission to view institutional analytics.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    final provider = context.watch<AnalyticsProvider>();
    final data = provider.analytics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grievance Analytics',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined, size: 20),
            tooltip: 'Export CSV (Formula Injection Safe)',
            onPressed: provider.isExporting ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            tooltip: 'Generate PDF Report',
            onPressed: provider.isExporting ? null : _exportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Analytics',
            onPressed: provider.loadAnalytics,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: theme.colorScheme.outline, height: 1),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: provider.loadAnalytics,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Period Filter Selector
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.space8,
                  runSpacing: AppSpacing.space8,
                  children: [
                    const Text('Audit Period:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildPeriodChip('30 Days', 30, provider),
                        _buildPeriodChip('90 Days', 90, provider),
                        _buildPeriodChip('1 Year', 365, provider),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space16),

                // 2. Loading / Error / Content States
                if (provider.isLoading)
                  const StateLoadingShimmer(height: 320)
                else if (provider.errorMessage != null)
                  StateErrorView(
                    message: provider.errorMessage!,
                    onRetry: provider.loadAnalytics,
                  )
                else if (data == null)
                  const Center(child: Text('No analytics data available.'))
                else ...[
                  // 3. KPI Metrics Grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.space12,
                    crossAxisSpacing: AppSpacing.space12,
                    childAspectRatio: 1.05,
                    children: [
                      AnalyticsKpiCard(
                        title: 'TOTAL LODGED',
                        value: data.totalSubmitted.toString(),
                        subtitle: '${data.totalPending} pending triage',
                        icon: Icons.assignment_outlined,
                        iconColor: AppColors.primary,
                      ),
                      AnalyticsKpiCard(
                        title: 'RESOLUTION RATE',
                        value: '${data.resolutionRate.toStringAsFixed(1)}%',
                        subtitle:
                            '${data.totalResolved} solved case${data.totalResolved == 1 ? '' : 's'}',
                        icon: Icons.check_circle_outline,
                        iconColor: AppColors.statusResolved,
                      ),
                      AnalyticsKpiCard(
                        title: 'AVG RESOLUTION',
                        value: AppDateTimeUtils.formatAverageResolutionCompact(
                          data.totalResolved,
                          data.averageResolutionDays,
                        ),
                        subtitle: data.totalResolved > 0
                            ? 'Average calendar time'
                            : 'No resolved cases',
                        icon: Icons.timer_outlined,
                        iconColor: AppColors.secondary,
                      ),
                      AnalyticsKpiCard(
                        title: 'OVERDUE / BREACHED',
                        value: data.overdueCount.toString(),
                        subtitle: '${data.totalPaused} frozen at 20d',
                        icon: Icons.warning_amber_rounded,
                        iconColor: AppColors.statusSlaBreached,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space16),

                  // 4. Status Pie Chart
                  StatusDistributionPieChart(analytics: data),
                  const SizedBox(height: AppSpacing.space16),

                  // 5. Monthly Trend Chart
                  MonthlyTrendBarChart(trends: data.monthlyTrends),
                  const SizedBox(height: AppSpacing.space16),

                  // 6. Department Breakdown Card
                  _buildDepartmentBreakdownCard(data, theme),
                  const SizedBox(height: AppSpacing.space16),

                  // 7. Authority Workload Card
                  _buildAuthorityWorkloadCard(data, theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, int days, AnalyticsProvider provider) {
    final isSelected = provider.selectedPeriodDays == days;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
      selected: isSelected,
      onSelected: (_) => provider.setPeriod(days),
    );
  }

  Widget _buildDepartmentBreakdownCard(
      AnalyticsDataModel data, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Department Performance Breakdown',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: AppSpacing.space12),
          if (data.departmentDistribution.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No department records found in this scope.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.departmentDistribution.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, i) {
                final dept = data.departmentDistribution[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DepartmentDashboardScreen(
                          department: DepartmentModel(
                            id: dept.id,
                            name: dept.name,
                            code: dept.code,
                          ),
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dept.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text(
                                '${dept.code} • ${dept.resolvedCount} resolved',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${dept.totalComplaints} case${dept.totalComplaints == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right,
                                size: 16,
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.8)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAuthorityWorkloadCard(AnalyticsDataModel data, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Authority Staff Triage Caseload',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: AppSpacing.space12),
          if (data.authorityWorkload.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No active authority caseload in this scope.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.authorityWorkload.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, i) {
                final auth = data.authorityWorkload[i];
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            '${auth.authorityLevelTitle} • ${auth.departmentName}',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${auth.activeCaseload} active',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.secondary)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
