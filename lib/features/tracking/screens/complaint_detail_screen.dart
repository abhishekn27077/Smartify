import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/sla_countdown_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/auth/models/user_session_model.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/authority/providers/authority_workflow_provider.dart';
import 'package:smartify/features/authority/utils/authority_workflow_permissions.dart';
import 'package:smartify/features/authority/widgets/authority_action_dialog.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/widgets/grievance_progress_tracker.dart';
import 'package:smartify/features/tracking/widgets/timeline_node_view.dart';

/// SMARTIFY Complaint Detail & Redressal Timeline Screen
/// Features dedicated, mobile-optimized authority action controls (Accept, Under Review, Resolve, Reject, Forward)
/// and immutable chronological audit-trail events.
class ComplaintDetailScreen extends StatelessWidget {
  final GrievanceModel grievance;

  const ComplaintDetailScreen({super.key, required this.grievance});

  void _copyReference(BuildContext context, String trackingNumber) {
    Clipboard.setData(ClipboardData(text: trackingNumber));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reference $trackingNumber copied!'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleClaim(BuildContext context, GrievanceModel g) async {
    final workflowProv = context.read<AuthorityWorkflowProvider>();
    final trackingProv = context.read<StudentTrackingProvider>();
    final scaffold = ScaffoldMessenger.of(context);

    final ok = await workflowProv.claimComplaint(g.id);
    if (ok) {
      await trackingProv.refreshSelectedComplaint();
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
              'Grievance ${g.trackingNumber} accepted! You are now assigned to this case.'),
          backgroundColor: AppColors.statusResolved,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (workflowProv.errorMessage != null) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(workflowProv.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _openAction(
    BuildContext context,
    GrievanceModel g,
    TriageActionType action,
  ) {
    context.read<AuthorityWorkflowProvider>().selectComplaint(g);
    AuthorityActionDialog.show(context, g, initialAction: action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackingProv = context.watch<StudentTrackingProvider>();
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    // Favor reactive selected complaint if updated, fallback to passed parameter
    final activeGrievance = (trackingProv.selectedComplaint?.id == grievance.id)
        ? trackingProv.selectedComplaint!
        : grievance;

    final currentUserId = currentUser?.id ?? '';
    final isAssignedToMe = activeGrievance.assignedAuthorityId == currentUserId;
    final isUnassigned = activeGrievance.assignedAuthorityId == null;

    final canAct = AuthorityWorkflowPermissions.canAct(
      user: currentUser,
      grievance: activeGrievance,
    );
    final infoMessage =
        AuthorityWorkflowPermissions.getInformationalStatusMessage(
      user: currentUser,
      grievance: activeGrievance,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          activeGrievance.trackingNumber,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh Timeline',
            onPressed: () => trackingProv.refreshSelectedComplaint(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: theme.colorScheme.outline, height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Status & SLA Countdown Bar with dedicated Copy Reference Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        GrievanceStatusBadge(status: activeGrievance.status),
                        SlaCountdownBadge(grievance: activeGrievance),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 13),
                    label: const Text('Copy ID',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSmall),
                      ),
                    ),
                    onPressed: () => _copyReference(
                        context, activeGrievance.trackingNumber),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space16),

              // 2. Authority Assignment & SLA Explainer Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space16),
                margin: const EdgeInsets.only(bottom: AppSpacing.space16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'CURRENT STAGE & SLA GOVERNANCE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space12),
                    _buildAuthorityInfoRow('Current Stage',
                        activeGrievance.currentAuthorityLevelTitle, theme),
                    const SizedBox(height: 8),
                    _buildAuthorityInfoRow(
                      'Assigned Authority',
                      activeGrievance.assignedAuthorityName ??
                          'Awaiting authority assignment',
                      theme,
                      isDimmed: activeGrievance.assignedAuthorityName == null,
                      isHighlighted:
                          activeGrievance.assignedAuthorityName != null,
                    ),
                    const SizedBox(height: 8),
                    _buildAuthorityInfoRow(
                        'Department', activeGrievance.departmentName, theme),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Delineate CURRENT TIER SLA vs 20-DAY GOVERNANCE CUTOFF
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    activeGrievance.isSlaBreached
                                        ? Icons.warning_rounded
                                        : Icons.timer_outlined,
                                    size: 15,
                                    color: activeGrievance.isSlaBreached
                                        ? AppColors.statusSlaBreached
                                        : (activeGrievance.timeRemaining.inHours < 24
                                            ? AppColors.statusEscalated
                                            : AppColors.statusUnderReview),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    activeGrievance.slaStatusHeadline.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: activeGrievance.isSlaBreached
                                          ? AppColors.statusSlaBreached
                                          : (activeGrievance.timeRemaining.inHours < 24
                                              ? AppColors.statusEscalated
                                              : AppColors.statusUnderReview),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                activeGrievance.formattedTimeRemaining,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: activeGrievance.isSlaBreached
                                      ? AppColors.statusSlaBreached
                                      : (activeGrievance.timeRemaining.inHours < 24
                                          ? AppColors.statusEscalated
                                          : AppColors.statusUnderReview),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            activeGrievance.slaExplanation,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.lock_clock_outlined,
                                      size: 15,
                                      color: AppColors.statusCutoffPaused),
                                  SizedBox(width: 6),
                                  Text(
                                    '20-DAY GOVERNANCE CUTOFF',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.statusCutoffPaused,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                AppDateTimeUtils.formatLocalDate(
                                    activeGrievance.cutoffDeadline),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.statusCutoffPaused,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Maximum lifecycle window (${AppDateTimeUtils.formatLocalDateTime(activeGrievance.cutoffDeadline)}) before automated escalation freezes.',
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

              // 3. Dedicated Authority Redressal Action Panel (In-Body)
              if (canAct) ...[
                _buildAuthorityActionCard(
                  context,
                  activeGrievance,
                  currentUser,
                  isAssignedToMe,
                  isUnassigned,
                  theme,
                ),
                const SizedBox(height: AppSpacing.space16),
              ] else if (infoMessage != null) ...[
                _buildInformationalStatusCard(infoMessage, theme),
                const SizedBox(height: AppSpacing.space16),
              ],

              // 4. Grievance Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeGrievance.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space12),
                    Text(
                      'DESCRIPTION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.primary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeGrievance.description,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: AppSpacing.space16),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.space12),
                    _buildInfoRow(
                        'Department', activeGrievance.departmentName, theme),
                    const SizedBox(height: 8),
                    _buildInfoRow('Category', activeGrievance.category, theme),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                        'Incident Date',
                        AppDateTimeUtils.formatIncidentDate(
                            activeGrievance.incidentDate),
                        theme),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                        'Logged At',
                        AppDateTimeUtils.formatLocalDateTime(
                            activeGrievance.createdAt),
                        theme),
                    const SizedBox(height: 8),
                    _buildInfoRow('Current Tier',
                        activeGrievance.currentAuthorityLevelTitle, theme,
                        isBold: true),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                        '20-Day Cutoff Limit',
                        AppDateTimeUtils.formatLocalDateTime(
                            activeGrievance.cutoffDeadline),
                        theme),
                    if (activeGrievance.attachmentPaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Evidence Attached',
                        '${activeGrievance.attachmentPaths.length} file(s) on record',
                        theme,
                      ),
                    ],
                    if (activeGrievance.resolutionNotes != null &&
                        activeGrievance.resolutionNotes!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              AppColors.successContainer.withValues(alpha: 0.5),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSmall),
                          border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FORMAL RESOLUTION MEMO',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success),
                            ),
                            const SizedBox(height: 4),
                            Text(activeGrievance.resolutionNotes!,
                                style:
                                    const TextStyle(fontSize: 13, height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space16),

              // 5. Layer 1: Simple Visual Order Tracker
              GrievanceProgressTracker(
                grievance: activeGrievance,
                events: trackingProv.timelineEvents,
              ),

              const SizedBox(height: AppSpacing.space16),

              // 6. Layer 2: Expandable Detailed Audit Trail
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                child: Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.history_edu_rounded,
                          size: 18, color: theme.colorScheme.primary),
                    ),
                    title: Text(
                      'View detailed activity history (${trackingProv.timelineEvents.length})',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Tap to expand chronological audit log',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    children: [
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: trackingProv.isLoadingTimeline
                            ? const StateLoadingShimmer(height: 160)
                            : trackingProv.timelineEvents.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                          'No timeline history recorded yet.'),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount:
                                        trackingProv.timelineEvents.length,
                                    itemBuilder: (context, index) {
                                      final event =
                                          trackingProv.timelineEvents[index];
                                      final isLast = index ==
                                          trackingProv.timelineEvents.length -
                                              1;
                                      return TimelineNodeView(
                                          event: event, isLast: isLast);
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Status Notice Card for non-actionable authorities or view-only states
  Widget _buildInformationalStatusCard(String message, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.secondary),
          const SizedBox(width: AppSpacing.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CASE STATUS NOTICE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// In-body Authority Redressal Card ensuring visible, impossible-to-miss actions
  Widget _buildAuthorityActionCard(
    BuildContext context,
    GrievanceModel g,
    UserSessionModel? currentUser,
    bool isAssignedToMe,
    bool isUnassigned,
    ThemeData theme,
  ) {
    final isAccepted = AuthorityWorkflowPermissions.isCaseAccepted(
      user: currentUser,
      grievance: g,
    );
    final canResolve = AuthorityWorkflowPermissions.canResolve(
      user: currentUser,
      grievance: g,
    );
    final canReject = AuthorityWorkflowPermissions.canReject(
      user: currentUser,
      grievance: g,
    );
    final canForward = AuthorityWorkflowPermissions.canForward(
      user: currentUser,
      grievance: g,
    );
    final forwardLabel = AuthorityWorkflowPermissions.nextForwardLabel(g);
    final authName = currentUser?.fullName ?? 'Authority';
    final authTitle = currentUser?.authorityLevelTitle ?? 'Staff';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.gavel_rounded,
                    size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AUTHORITY REDRESSAL CONTROLS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      isAccepted
                          ? 'Assigned to: $authName ($authTitle)'
                          : (isUnassigned
                              ? 'Awaiting authority assignment at ${g.currentAuthorityLevelTitle}'
                              : 'Case assigned to ${g.assignedAuthorityName ?? 'another officer'}'),
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (!isAccepted) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.statusPending.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.statusPending.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.statusPending),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CASE AWAITING ACCEPTANCE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.statusPending,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          g.currentAuthorityLevelNumber == 1
                              ? 'This grievance is awaiting Level 1 authority acceptance. Accept the case to take personal responsibility and unlock redressal actions.'
                              : 'This case moved to ${g.currentAuthorityLevelTitle}. Accept the case to claim active caseload ownership and unlock redressal actions.',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.assignment_turned_in_rounded, size: 18),
              label: const Text(
                'ACCEPT CASE / TAKE RESPONSIBILITY',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
              ),
              onPressed: () => _handleClaim(context, g),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.statusResolved.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.statusResolved.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 15, color: AppColors.statusResolved),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assigned to you: $authName (Active Caseload). Case accepted by: $authName ($authTitle)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Distinct Action Buttons Grid (Resolve, Forward, Reject)
            Row(
              children: [
                if (canResolve)
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 15),
                      label: const Text('RESOLVE',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                          maxLines: 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusResolved,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          _openAction(context, g, TriageActionType.resolve),
                    ),
                  ),
                if (canResolve && canForward) const SizedBox(width: 8),
                if (canForward)
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.trending_up_rounded, size: 15),
                      label: Text(
                        forwardLabel,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusCutoffPaused,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          _openAction(context, g, TriageActionType.forward),
                    ),
                  ),
              ],
            ),
            if (canReject) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined,
                          size: 15, color: AppColors.error),
                      label: const Text('REJECT',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error),
                          maxLines: 1),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          _openAction(context, g, TriageActionType.reject),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                color: isBold
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorityInfoRow(String label, String value, ThemeData theme,
      {bool isDimmed = false,
      bool isImportant = false,
      bool isHighlighted = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isImportant || isHighlighted
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: isImportant
                  ? theme.colorScheme.error
                  : isHighlighted
                      ? theme.colorScheme.primary
                      : isDimmed
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
