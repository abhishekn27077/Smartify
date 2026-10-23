import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/features/admin/providers/admin_management_provider.dart';
import 'package:smartify/features/admin/screens/admin_all_complaints_screen.dart';
import 'package:smartify/features/admin/screens/admin_audit_trail_screen.dart';
import 'package:smartify/features/admin/screens/admin_departments_screen.dart';
import 'package:smartify/features/admin/screens/admin_students_screen.dart';
import 'package:smartify/features/admin/screens/authority_staff_workload_screen.dart';
import 'package:smartify/features/admin/screens/tier_sla_screen.dart';
import 'package:smartify/features/analytics/providers/analytics_provider.dart';
import 'package:smartify/features/analytics/screens/analytics_dashboard_screen.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/escalation/providers/escalation_provider.dart';
import 'package:smartify/features/escalation/screens/admin_cutoff_review_screen.dart';
import 'package:smartify/features/notifications/providers/notification_provider.dart';
import 'package:smartify/features/notifications/screens/notifications_screen.dart';

/// SMARTIFY Admin Governance & Control Center Screen
/// Implements the PhonePe-style modular launcher pattern:
/// HOME -> focused functional modules -> deep drill-down sections.
class AdminControlCenterScreen extends StatefulWidget {
  final VoidCallback? onNavigateToDepartments;
  final VoidCallback? onNavigateToAnalytics;
  final VoidCallback? onNavigateToGovernance;

  const AdminControlCenterScreen({
    super.key,
    this.onNavigateToDepartments,
    this.onNavigateToAnalytics,
    this.onNavigateToGovernance,
  });

  @override
  State<AdminControlCenterScreen> createState() =>
      _AdminControlCenterScreenState();
}

class _AdminControlCenterScreenState extends State<AdminControlCenterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminManagementProvider>().loadAdminData();
      context.read<AnalyticsProvider>().loadAnalytics();
      context.read<EscalationProvider>().loadPausedComplaints();
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  void _refreshAll() {
    context.read<AdminManagementProvider>().loadAdminData();
    context.read<AnalyticsProvider>().loadAnalytics();
    context.read<EscalationProvider>().loadPausedComplaints();
    context.read<NotificationProvider>().loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final analyticsProv = context.watch<AnalyticsProvider>();
    final escalationProv = context.watch<EscalationProvider>();
    final notifProv = context.watch<NotificationProvider>();
    final unread = notifProv.unreadCount;

    final analyticsData = analyticsProv.analytics;
    final totalLodged = analyticsData?.totalSubmitted ?? 0;
    final totalResolved = analyticsData?.totalResolved ?? 0;
    final frozenCount = escalationProv.pausedComplaints.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              ),
              child: Icon(Icons.shield_rounded,
                  color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.space8),
            const Text(
              'Admin Governance',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread.toString()),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            tooltip: 'Notifications',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh All Data',
            onPressed: _refreshAll,
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
        child: RefreshIndicator(
          onRefresh: () async => _refreshAll(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Institutional Governance Context Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.25),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMedium),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(Icons.admin_panel_settings_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'Campus Administrator',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Institutional Governance & Arbitration Board',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.statusUnderReview,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.space16),

                // 2. High-Level Campus Pulse Summary
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildPulseItem(
                        count: '$totalLodged',
                        label: 'Total Cases',
                        color: theme.colorScheme.primary,
                      ),
                      Container(
                        height: 30,
                        width: 1,
                        color: theme.colorScheme.outline.withValues(alpha: 0.4),
                      ),
                      _buildPulseItem(
                        count: '$totalResolved',
                        label: 'Resolved',
                        color: AppColors.statusResolved,
                      ),
                      Container(
                        height: 30,
                        width: 1,
                        color: theme.colorScheme.outline.withValues(alpha: 0.4),
                      ),
                      _buildPulseItem(
                        count: '$frozenCount',
                        label: 'Cutoff Paused',
                        color: AppColors.statusCutoffPaused,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.space24),

                // 3. Operational & Governance Modules Header
                Text(
                  'Governance Modules',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap any dedicated section to manage cases, staff, and policies',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: AppSpacing.space16),

                // 4. PhonePe-Style Launcher Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.space12,
                  crossAxisSpacing: AppSpacing.space12,
                  childAspectRatio: 1.15,
                  children: [
                    // Module 1: Departments
                    _buildModuleCard(
                      icon: Icons.domain_rounded,
                      iconColor: theme.colorScheme.primary,
                      title: 'Departments',
                      subtitle: 'Department-wise grievance performance',
                      theme: theme,
                      onTap: () {
                        if (widget.onNavigateToDepartments != null) {
                          widget.onNavigateToDepartments!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AdminDepartmentsScreen(),
                            ),
                          );
                        }
                      },
                    ),

                    // Module 2: Grievances
                    _buildModuleCard(
                      icon: Icons.assignment_outlined,
                      iconColor: AppColors.statusUnderReview,
                      title: 'Grievances',
                      subtitle: 'View and manage all campus cases',
                      theme: theme,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdminAllComplaintsScreen(),
                          ),
                        );
                      },
                    ),

                    // Module 3: Analytics
                    _buildModuleCard(
                      icon: Icons.insights_rounded,
                      iconColor: AppColors.secondary,
                      title: 'Analytics',
                      subtitle: 'Performance and resolution insights',
                      theme: theme,
                      onTap: () {
                        if (widget.onNavigateToAnalytics != null) {
                          widget.onNavigateToAnalytics!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AnalyticsDashboardScreen(),
                            ),
                          );
                        }
                      },
                    ),

                    // Module 4: Authority Staff
                    _buildModuleCard(
                      icon: Icons.people_alt_outlined,
                      iconColor: AppColors.primary,
                      title: 'Authority Staff',
                      subtitle: 'Workload and staff activity',
                      theme: theme,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const AuthorityStaffWorkloadScreen(),
                          ),
                        );
                      },
                    ),

                    // Module 5: Escalation Center
                    _buildModuleCard(
                      icon: Icons.hourglass_bottom_rounded,
                      iconColor: AppColors.statusCutoffPaused,
                      title: 'Escalation Center',
                      subtitle: '20-day cutoff governance',
                      theme: theme,
                      onTap: () {
                        if (widget.onNavigateToGovernance != null) {
                          widget.onNavigateToGovernance!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AdminCutoffReviewScreen(),
                            ),
                          );
                        }
                      },
                    ),

                    // Module 6: SLA Configuration
                    _buildModuleCard(
                      icon: Icons.tune_rounded,
                      iconColor: AppColors.statusPending,
                      title: 'SLA Configuration',
                      subtitle: 'Tier forwarding policies',
                      theme: theme,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TierSlaScreen(),
                          ),
                        );
                      },
                    ),

                    // Module 7: Audit Trail
                    _buildModuleCard(
                      icon: Icons.history_edu_rounded,
                      iconColor: AppColors.outline,
                      title: 'Audit Trail',
                      subtitle: 'Immutable system activity',
                      theme: theme,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdminAuditTrailScreen(),
                          ),
                        );
                      },
                    ),

                    // Module 8: Registered Students
                    _buildModuleCard(
                      icon: Icons.school_outlined,
                      iconColor: AppColors.statusUnderReview,
                      title: 'Student Accounts',
                      subtitle: 'Institution-wide registered students',
                      theme: theme,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdminStudentsScreen(),
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

  Widget _buildPulseItem({
    required String count,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildModuleCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        side:
            BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
