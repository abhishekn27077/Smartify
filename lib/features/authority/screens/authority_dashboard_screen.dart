import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/sla_countdown_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/authority/providers/authority_workflow_provider.dart';
import 'package:smartify/features/authority/screens/authority_escalations_screen.dart';
import 'package:smartify/features/authority/screens/authority_my_cases_screen.dart';
import 'package:smartify/features/authority/utils/authority_workflow_permissions.dart';
import 'package:smartify/features/authority/widgets/authority_action_dialog.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Authority Dashboard & Redressal Queue Screen
/// Delivers clean institutional header, tappable KPI cards, deterministic newest-first sorting,
/// filter chips, and distinct action buttons.
class AuthorityDashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToMyCases;
  final VoidCallback? onNavigateToEscalations;

  const AuthorityDashboardScreen({
    super.key,
    this.onNavigateToMyCases,
    this.onNavigateToEscalations,
  });

  @override
  State<AuthorityDashboardScreen> createState() =>
      _AuthorityDashboardScreenState();
}

class _AuthorityDashboardScreenState extends State<AuthorityDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<AuthorityWorkflowProvider>();
      // Ensure default sort is NEWEST
      if (prov.sortOption == 'PRIORITY_SLA') {
        prov.setSortOption('NEWEST');
      } else {
        prov.loadQueue();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openMyCases() {
    if (widget.onNavigateToMyCases != null) {
      widget.onNavigateToMyCases!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AuthorityMyCasesScreen(),
        ),
      );
    }
  }

  void _openEscalations() {
    if (widget.onNavigateToEscalations != null) {
      widget.onNavigateToEscalations!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AuthorityEscalationsScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<AuthorityWorkflowProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final authName = user?.fullName ?? 'Authority Officer';
    final deptName = user?.departmentName ?? 'Authorized Department';
    final tierTitle =
        user?.authorityLevelTitle ?? 'Level 1 — Faculty / Department Officer';

    // Calculate personal active cases count
    final myActiveCount = provider.queue
        .where((g) =>
            g.assignedAuthorityId == user?.id &&
            !g.status.isTerminal &&
            g.status != ComplaintStatus.cutoffPaused)
        .length;

    // Calculate escalations count
    final escalationsCount = provider.queue
        .where((g) =>
            g.status == ComplaintStatus.escalated ||
            g.currentAuthorityLevelNumber > 1 ||
            g.status == ComplaintStatus.cutoffPaused)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Authority Dashboard',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Queue',
            onPressed: provider.loadQueue,
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
        child: Column(
          children: [
            // 1. Authority Profile Header Context
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color:
                  theme.colorScheme.secondaryContainer.withValues(alpha: 0.25),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.secondary,
                    child: Text(
                      authName.isNotEmpty ? authName[0].toUpperCase() : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          tierTitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.secondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          deptName,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Interactive KPI Cards (PhonePe-Style Launcher Row)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _buildTappableKpiCard(
                    title: 'Pending Intake',
                    count: provider.pendingCount,
                    color: AppColors.statusPending,
                    icon: Icons.hourglass_top_rounded,
                    isSelected: provider.selectedStatus == 'PENDING',
                    onTap: () => provider.setStatusFilter(
                      provider.selectedStatus == 'PENDING' ? 'ALL' : 'PENDING',
                    ),
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  _buildTappableKpiCard(
                    title: 'Under Review',
                    count: provider.underReviewCount,
                    color: AppColors.statusUnderReview,
                    icon: Icons.sync_rounded,
                    isSelected: provider.selectedStatus == 'UNDER_REVIEW',
                    onTap: () => provider.setStatusFilter(
                      provider.selectedStatus == 'UNDER_REVIEW'
                          ? 'ALL'
                          : 'UNDER_REVIEW',
                    ),
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  _buildTappableKpiCard(
                    title: 'My Cases',
                    count: myActiveCount,
                    color: AppColors.primary,
                    icon: Icons.assignment_ind_outlined,
                    onTap: _openMyCases,
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  _buildTappableKpiCard(
                    title: 'Escalations',
                    count: escalationsCount,
                    color: AppColors.secondary,
                    icon: Icons.trending_up_rounded,
                    onTap: _openEscalations,
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  _buildTappableKpiCard(
                    title: 'Due Soon',
                    count: provider.dueSoonCount,
                    color: AppColors.statusSlaBreached,
                    icon: Icons.timer_outlined,
                    isSelected: provider.selectedStatus == 'DUE_SOON',
                    onTap: () => provider.setStatusFilter(
                      provider.selectedStatus == 'DUE_SOON'
                          ? 'ALL'
                          : 'DUE_SOON',
                    ),
                    theme: theme,
                  ),
                ],
              ),
            ),

            // 3. Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space16, AppSpacing.space8, AppSpacing.space16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: provider.setSearchQuery,
                decoration: InputDecoration(
                  hintText: 'Search by reference, student, or title...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            provider.setSearchQuery('');
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),

            // 4. Sort Control Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space16, AppSpacing.space8, AppSpacing.space16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Queue Count: ${provider.queue.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sort: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSmall),
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: provider.sortOption,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, size: 18),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'NEWEST', child: Text('Newest First')),
                              DropdownMenuItem(
                                  value: 'PRIORITY_SLA',
                                  child: Text('Priority / SLA')),
                              DropdownMenuItem(
                                  value: 'OLDEST', child: Text('Oldest First')),
                              DropdownMenuItem(
                                  value: 'DEADLINE',
                                  child: Text('SLA Deadline')),
                              DropdownMenuItem(
                                  value: 'STATUS', child: Text('Status')),
                            ],
                            onChanged: (val) {
                              if (val != null) provider.setSortOption(val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 5. Status Filter Chips with exact counts
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
              child: Row(
                children: [
                  _buildFilterChip(
                      'ALL', 'All Active (${provider.activeCount})', provider),
                  _buildFilterChip('PENDING',
                      'Pending Intake (${provider.pendingCount})', provider),
                  _buildFilterChip('UNDER_REVIEW',
                      'Under Review (${provider.underReviewCount})', provider),
                  _buildFilterChip('DUE_SOON',
                      'Due Soon (${provider.dueSoonCount})', provider),
                  _buildFilterChip(
                      'ESCALATED', 'Escalated ($escalationsCount)', provider),
                  _buildFilterChip('RESOLVED',
                      'Resolved (${provider.resolvedCount})', provider),
                ],
              ),
            ),

            if (provider.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space16, vertical: 4),
                child: FeedbackBanner(
                  message: provider.errorMessage!,
                  isError: true,
                  onRetry: provider.loadQueue,
                ),
              ),

            // 7. Main Queue List
            Expanded(
              child: provider.isLoading
                  ? _buildLoadingSkeleton()
                  : provider.queue.isEmpty
                      ? const StateEmptyView(
                          title: 'No Pending Grievances',
                          subtitle:
                              'You\'re all caught up. No grievances currently require triage in this filter.',
                          icon: Icons.assignment_turned_in_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: provider.loadQueue,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.space16),
                            itemCount: provider.queue.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.space12),
                            itemBuilder: (context, index) {
                              final grievance = provider.queue[index];
                              return _buildQueueCard(
                                  context, grievance, theme, user?.id ?? '');
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTappableKpiCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    required ThemeData theme,
    bool isSelected = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            border: Border.all(
              color: isSelected
                  ? color
                  : theme.colorScheme.outline.withValues(alpha: 0.4),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      String status, String label, AuthorityWorkflowProvider provider) {
    final isSelected = provider.selectedStatus == status;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: theme.colorScheme.secondaryContainer,
        labelStyle: TextStyle(
          color: isSelected
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurface,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.secondary
                : theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        onSelected: (_) => provider.setStatusFilter(status),
      ),
    );
  }

  Widget _buildQueueCard(BuildContext context, GrievanceModel grievance,
      ThemeData theme, String currentUserId) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        side: BorderSide(
          color: grievance.isOverdue
              ? AppColors.error.withValues(alpha: 0.6)
              : theme.colorScheme.outline.withValues(alpha: 0.5),
          width: grievance.isOverdue ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Tracking ID + Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  grievance.trackingNumber,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.primary,
                  ),
                ),
                GrievanceStatusBadge(status: grievance.status, isCompact: true),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Student Name, Department, Category
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    (grievance.studentName != null &&
                            grievance.studentName!.trim().isNotEmpty)
                        ? grievance.studentName!
                        : 'Student information unavailable',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text('•',
                    style: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.4))),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${grievance.departmentName} (${grievance.category})',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Assigned Authority info
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Assigned: ${grievance.assignedAuthorityName ?? "Awaiting authority assignment"}',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: grievance.assignedAuthorityName == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: grievance.assignedAuthorityName == null
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Received time & SLA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Received: ${AppDateTimeUtils.formatLocalDateTime(grievance.createdAt)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                SlaCountdownBadge(grievance: grievance),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Action Buttons: Details and Triage Action
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                  ),
                  onPressed: () {
                    context
                        .read<StudentTrackingProvider>()
                        .selectComplaint(grievance);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ComplaintDetailScreen(grievance: grievance),
                      ),
                    );
                  },
                  child: const Text('Details',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                Builder(
                  builder: (context) {
                    final auth = context.watch<AuthProvider>();
                    final canAct = AuthorityWorkflowPermissions.canAct(
                      user: auth.currentUser,
                      grievance: grievance,
                    );
                    if (!canAct) return const SizedBox.shrink();

                    final isAccepted =
                        AuthorityWorkflowPermissions.isCaseAccepted(
                      user: auth.currentUser,
                      grievance: grievance,
                    );

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        if (!isAccepted) ...[
                          ElevatedButton.icon(
                            icon:
                                const Icon(Icons.how_to_reg_rounded, size: 14),
                            label: const Text('ACCEPT CASE',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                              ),
                            ),
                            onPressed: () {
                              context
                                  .read<AuthorityWorkflowProvider>()
                                  .selectComplaint(grievance);
                              AuthorityActionDialog.show(
                                context,
                                grievance,
                                initialAction: TriageActionType.claim,
                              );
                            },
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            icon: const Icon(Icons.gavel_rounded, size: 14),
                            label: const Text('Process Case',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: theme.colorScheme.secondary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                              ),
                            ),
                            onPressed: () {
                              context
                                  .read<AuthorityWorkflowProvider>()
                                  .selectComplaint(grievance);
                              AuthorityActionDialog.show(context, grievance);
                            },
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.space16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space12),
      itemBuilder: (_, __) => const StateLoadingShimmer(height: 150),
    );
  }
}
