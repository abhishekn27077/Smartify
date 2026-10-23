import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/primary_button.dart';
import 'package:smartify/core/widgets/sla_countdown_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/complaints/screens/complaint_registration_screen.dart';
import 'package:smartify/features/notifications/providers/notification_provider.dart';
import 'package:smartify/features/notifications/screens/notifications_screen.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';
import 'package:smartify/features/tracking/screens/my_complaints_screen.dart';
import 'package:smartify/features/tracking/services/tracking_service.dart';

/// SMARTIFY Student Home Dashboard Screen
/// Delivers an intuitive, mobile-first overview with greeting, compact metrics,
/// prominent submission action, quick tracking lookup, and recent cases.
class StudentHomeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToComplaints;
  final VoidCallback? onNavigateToSubmit;

  const StudentHomeScreen({
    super.key,
    this.onNavigateToComplaints,
    this.onNavigateToSubmit,
  });

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final TextEditingController _trackController = TextEditingController();
  bool _isSearchingTracking = false;
  String? _trackError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentTrackingProvider>().loadComplaints();
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  @override
  void dispose() {
    _trackController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _handleQuickTrack() async {
    final query = _trackController.text.trim();
    if (query.isEmpty) {
      setState(() => _trackError = 'Please enter a tracking number.');
      return;
    }

    setState(() {
      _isSearchingTracking = true;
      _trackError = null;
    });

    try {
      final service = TrackingService();
      final grievance = await service.fetchComplaintById(query);
      if (!mounted) return;

      if (grievance != null) {
        _trackController.clear();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ComplaintDetailScreen(grievance: grievance),
          ),
        );
      } else {
        setState(() => _trackError = 'No grievance found matching "$query".');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _trackError = 'Could not search tracking ID: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSearchingTracking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final trackingProv = context.watch<StudentTrackingProvider>();
    final notifProv = context.watch<NotificationProvider>();
    final unread = notifProv.unreadCount;

    final studentName = user?.fullName ?? 'Student';
    final program = user?.academicProgram ?? 'Campus Member';

    final complaints = trackingProv.complaints;
    final total = complaints.length;
    final pending =
        complaints.where((c) => c.status == ComplaintStatus.pending).length;
    final underReview = complaints
        .where((c) =>
            c.status == ComplaintStatus.underReview ||
            c.status == ComplaintStatus.inProgress)
        .length;
    final resolved =
        complaints.where((c) => c.status == ComplaintStatus.resolved).length;
    final recentComplaints = complaints.take(4).toList();

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
              child: Icon(Icons.school_rounded,
                  color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.space8),
            const Text(
              'SMARTIFY',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
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
            tooltip: 'Refresh',
            onPressed: () => trackingProv.loadComplaints(),
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
          onRefresh: trackingProv.loadComplaints,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Greeting & Profile Context
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.25),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMedium),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          studentName.isNotEmpty
                              ? studentName[0].toUpperCase()
                              : 'S',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_getGreeting()},',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                            Text(
                              studentName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                              ),
                              child: Text(
                                'Program: $program',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.space20),

                // 2. Compact My Grievances KPI Summary
                Text(
                  'My Grievances Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),
                Row(
                  children: [
                    _buildKpiCard(
                      label: 'Total',
                      count: total,
                      color: theme.colorScheme.primary,
                      icon: Icons.folder_outlined,
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      label: 'Pending',
                      count: pending,
                      color: AppColors.statusPending,
                      icon: Icons.hourglass_top_rounded,
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      label: 'Under Review',
                      count: underReview,
                      color: AppColors.statusUnderReview,
                      icon: Icons.sync_rounded,
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      label: 'Resolved',
                      count: resolved,
                      color: AppColors.statusResolved,
                      icon: Icons.check_circle_outline_rounded,
                      theme: theme,
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.space20),

                // 3. Prominent Action: + Submit New Grievance
                PrimaryButton(
                  text: 'SUBMIT NEW GRIEVANCE',
                  icon: Icons.add_circle_rounded,
                  onPressed: () {
                    if (widget.onNavigateToSubmit != null) {
                      widget.onNavigateToSubmit!();
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ComplaintRegistrationScreen(),
                        ),
                      );
                    }
                  },
                ),

                const SizedBox(height: AppSpacing.space20),

                // 4. Quick Track Grievance
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMedium),
                    border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.search_rounded,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Track Grievance by ID',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter your institutional tracking number (e.g. SMT-2026-01044)',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _trackController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'SMT-2026-XXXXX',
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusSmall),
                                ),
                              ),
                              onSubmitted: (_) => _handleQuickTrack(),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                              ),
                            ),
                            onPressed:
                                _isSearchingTracking ? null : _handleQuickTrack,
                            child: _isSearchingTracking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Text('Track',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      if (_trackError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _trackError!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.space24),

                // 5. Recent Grievances Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Grievances',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: theme.colorScheme.primary,
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('View All',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () {
                        if (widget.onNavigateToComplaints != null) {
                          widget.onNavigateToComplaints!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const MyComplaintsScreen(),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space8),

                // 6. Recent Grievances Content
                if (trackingProv.isLoading)
                  const StateLoadingShimmer(height: 180)
                else if (recentComplaints.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                      border: Border.all(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 36,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 8),
                        const Text(
                          'No Grievances Submitted Yet',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'When you submit an issue, it will be listed here with live tracking.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: recentComplaints.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final grievance = recentComplaints[index];
                      return _buildRecentCard(grievance, theme);
                    },
                  ),

                const SizedBox(height: AppSpacing.space32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required ThemeData theme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
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
      ),
    );
  }

  Widget _buildRecentCard(GrievanceModel grievance, ThemeData theme) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        side:
            BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        onTap: () {
          context.read<StudentTrackingProvider>().selectComplaint(grievance);
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
              // Top Bar: Tracking ID + Status
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
              const SizedBox(height: 6),

              // Title
              Text(
                grievance.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Department & Level
              Row(
                children: [
                  Icon(Icons.business_rounded,
                      size: 13,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${grievance.departmentName} • ${grievance.currentAuthorityLevelTitle}',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Last updated & SLA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Updated: ${AppDateTimeUtils.formatLocalDate(grievance.updatedAt)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  SlaCountdownBadge(grievance: grievance),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
