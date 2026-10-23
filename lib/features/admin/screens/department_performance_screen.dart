import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/screens/department_dashboard_screen.dart';
import 'package:smartify/features/admin/services/admin_service.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';
import 'package:smartify/features/analytics/services/analytics_service.dart';
import 'package:smartify/features/complaints/models/department_model.dart';

/// SMARTIFY Department Performance Screen
/// Displays comparative department metrics: total cases, resolved, pending,
/// resolution rate, and average resolution days.
/// Tapping any row opens the corresponding DepartmentDashboardScreen.
class DepartmentPerformanceScreen extends StatefulWidget {
  const DepartmentPerformanceScreen({super.key});

  @override
  State<DepartmentPerformanceScreen> createState() =>
      _DepartmentPerformanceScreenState();
}

class _DepartmentPerformanceScreenState
    extends State<DepartmentPerformanceScreen> {
  final AnalyticsService _analyticsService = AnalyticsService();
  final AdminService _adminService = AdminService();

  AnalyticsDataModel? _analytics;
  List<DepartmentModel> _departments = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _analyticsService.fetchAnalytics(),
        _adminService.fetchDepartments(),
      ]);

      if (mounted) {
        setState(() {
          _analytics = results[0] as AnalyticsDataModel;
          _departments = results[1] as List<DepartmentModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load department performance: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _analytics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Department Performance',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Metrics',
            onPressed: _loadData,
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
                    onRetry: _loadData,
                  )
                : data == null || data.departmentDistribution.isEmpty
                    ? const StateEmptyView(
                        title: 'No Performance Data',
                        subtitle:
                            'Department performance distribution is not available.',
                        icon: Icons.insights_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.space16),
                          itemCount: data.departmentDistribution.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.space12),
                          itemBuilder: (context, index) {
                            final metric = data.departmentDistribution[index];
                            final deptModel = _departments.firstWhere(
                              (d) => d.id == metric.id,
                              orElse: () => DepartmentModel(
                                id: metric.id,
                                name: metric.name,
                                code: metric.code,
                              ),
                            );

                            final total = metric.totalComplaints;
                            final resolved = metric.resolvedCount;
                            final pending =
                                total - resolved - metric.pausedCount;
                            final rate = total > 0
                                ? ((resolved / total) * 100).toStringAsFixed(1)
                                : '0.0';

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusMedium),
                                side: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusMedium),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => DepartmentDashboardScreen(
                                          department: deptModel),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(AppSpacing.space16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Name + Code
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              metric.name,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppSpacing.radiusSmall),
                                            ),
                                            child: Text(
                                              metric.code,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Performance Metrics Row
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.35),
                                          borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusSmall),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceAround,
                                          children: [
                                            _buildColumn('$total', 'Total',
                                                theme.colorScheme.onSurface),
                                            _buildDivider(theme),
                                            _buildColumn(
                                                '$resolved',
                                                'Resolved',
                                                AppColors.statusResolved),
                                            _buildDivider(theme),
                                            _buildColumn('$pending', 'Pending',
                                                AppColors.statusPending),
                                            _buildDivider(theme),
                                            _buildColumn('$rate%', 'Resolution',
                                                AppColors.primary),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Container(
      height: 24,
      width: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.4),
    );
  }

  Widget _buildColumn(String value, String label, Color color) {
    return Column(
      children: [
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
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
