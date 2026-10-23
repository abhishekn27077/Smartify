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
import 'package:smartify/features/authority/utils/authority_workflow_permissions.dart';
import 'package:smartify/features/authority/widgets/authority_action_dialog.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Dedicated Authority Escalation Screen
/// Visualizes multi-tier escalation hierarchy (L1 -> L2 -> L3) and shows cases
/// forwarded to higher tiers, awaiting higher-level action, or needing SLA/cutoff attention.
class AuthorityEscalationsScreen extends StatefulWidget {
  const AuthorityEscalationsScreen({super.key});

  @override
  State<AuthorityEscalationsScreen> createState() =>
      _AuthorityEscalationsScreenState();
}

class _AuthorityEscalationsScreenState
    extends State<AuthorityEscalationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthorityWorkflowProvider>().loadQueue();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<AuthorityWorkflowProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.currentUser?.id ?? '';

    // Filter queue to cases that represent escalations, higher tier actions, or SLA/cutoff warnings
    final escalationCases = prov.queue.where((g) {
      final isEscalatedOrHigherTier = g.status == ComplaintStatus.escalated ||
          g.currentAuthorityLevelNumber > 1 ||
          g.status == ComplaintStatus.cutoffPaused ||
          g.isOverdue;
      if (!isEscalatedOrHigherTier) return false;

      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return g.title.toLowerCase().contains(q) ||
          g.trackingNumber.toLowerCase().contains(q) ||
          (g.studentName?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Department Escalations',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Escalations',
            onPressed: prov.loadQueue,
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
            // Informational Workflow Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.space12),
              color: AppColors.secondary.withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(Icons.trending_up_rounded,
                      color: AppColors.secondary, size: 20),
                  const SizedBox(width: AppSpacing.space10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tier Hierarchy Progression (L1 → L2 → L3)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Showing cases forwarded to higher tiers or approaching SLA limits.',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                  AppSpacing.space12, AppSpacing.space16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search escalations by ID, student, or title...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Case List
            Expanded(
              child: prov.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.space16),
                      child: StateLoadingShimmer(height: 250),
                    )
                  : escalationCases.isEmpty
                      ? const StateEmptyView(
                          title: 'No Escalations',
                          subtitle:
                              'No grievances are currently awaiting higher-tier escalation or SLA intervention.',
                          icon: Icons.check_circle_outline_rounded,
                        )
                      : RefreshIndicator(
                          onRefresh: prov.loadQueue,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.space16),
                            itemCount: escalationCases.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.space12),
                            itemBuilder: (context, index) {
                              final grievance = escalationCases[index];
                              return _buildEscalationCard(
                                  context, grievance, theme, currentUserId);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEscalationCard(BuildContext context, GrievanceModel grievance,
      ThemeData theme, String currentUserId) {
    final prevLevelNumber = grievance.currentAuthorityLevelNumber > 1
        ? grievance.currentAuthorityLevelNumber - 1
        : 1;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        side: BorderSide(
          color: grievance.isOverdue
              ? AppColors.error.withValues(alpha: 0.6)
              : AppColors.secondary.withValues(alpha: 0.35),
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
            const SizedBox(height: 10),

            // Tier Forwarding Badge Banner
            Container(
              padding: const EdgeInsets.all(AppSpacing.space10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTierStep(
                        label: 'Previous',
                        tier: 'Level $prevLevelNumber',
                        isCurrent: false,
                        theme: theme,
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: AppColors.secondary),
                      _buildTierStep(
                        label: 'Current Stage',
                        tier: grievance.currentAuthorityLevelTitle,
                        isCurrent: true,
                        theme: theme,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Assigned: ${grievance.assignedAuthorityName ?? "Awaiting authority assignment"}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Forwarding Justification if present
            if (grievance.statusRemarks != null &&
                grievance.statusRemarks!.trim().isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Forwarding Justification:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      grievance.statusRemarks!,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Updated time & SLA countdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Forwarded: ${AppDateTimeUtils.formatLocalDateTime(grievance.updatedAt)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                SlaCountdownBadge(grievance: grievance),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action Buttons (Accept Case / Process / View Details)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 13),
                  label: const Text('Details',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                    fontSize: 12, fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
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
                            label: const Text('PROCESS CASE',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
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

  Widget _buildTierStep({
    required String label,
    required String tier,
    required bool isCurrent,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment:
          isCurrent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        Text(
          tier,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
            color:
                isCurrent ? AppColors.secondary : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
