import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

/// SMARTIFY Modern E-Commerce Style Expandable Timeline Node
/// Provides clean, order-tracking aesthetics with clickable/expandable audit detail cards.
class TimelineNodeView extends StatefulWidget {
  final TimelineEventModel event;
  final bool isLast;
  final bool initiallyExpanded;

  const TimelineNodeView({
    super.key,
    required this.event,
    this.isLast = false,
    this.initiallyExpanded = true,
  });

  @override
  State<TimelineNodeView> createState() => _TimelineNodeViewState();
}

class _TimelineNodeViewState extends State<TimelineNodeView> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  Color _getStatusColor() {
    final e = widget.event;
    if (e.isSystemEvent || e.eventType == 'SYSTEM_ESCALATION') {
      return AppColors.secondary;
    }
    switch (e.newStatus) {
      case ComplaintStatus.pending:
        return AppColors.statusPending;
      case ComplaintStatus.underReview:
      case ComplaintStatus.inProgress:
        return AppColors.statusUnderReview;
      case ComplaintStatus.resolved:
        return AppColors.statusResolved;
      case ComplaintStatus.rejected:
        return AppColors.error;
      case ComplaintStatus.escalated:
        return AppColors.statusEscalated;
      case ComplaintStatus.cutoffPaused:
        return AppColors.statusCutoffPaused;
    }
  }

  IconData _getStatusIcon() {
    final e = widget.event;
    if (e.isSystemEvent || e.eventType == 'SYSTEM_ESCALATION') {
      return Icons.smart_toy_rounded;
    }
    switch (e.newStatus) {
      case ComplaintStatus.pending:
        return Icons.assignment_turned_in_rounded;
      case ComplaintStatus.underReview:
        return Icons.sync_rounded;
      case ComplaintStatus.inProgress:
        return Icons.pending_actions_rounded;
      case ComplaintStatus.resolved:
        return Icons.check_circle_rounded;
      case ComplaintStatus.rejected:
        return Icons.cancel_rounded;
      case ComplaintStatus.escalated:
        return Icons.trending_up_rounded;
      case ComplaintStatus.cutoffPaused:
        return Icons.pause_circle_filled_rounded;
    }
  }

  String _getEventStageTitle() {
    final e = widget.event;
    if (e.isSystemEvent || e.eventType == 'SYSTEM_ESCALATION') {
      return 'AUTOMATED ESCALATION';
    }
    if (e.newStatus == ComplaintStatus.pending || e.eventType == 'SUBMITTED') {
      return 'SUBMITTED';
    }
    if (e.newStatus == ComplaintStatus.underReview ||
        e.eventType == 'UNDER_REVIEW') {
      return 'UNDER REVIEW';
    }
    if (e.newStatus == ComplaintStatus.resolved || e.eventType == 'RESOLVED') {
      return 'RESOLVED';
    }
    if (e.newStatus == ComplaintStatus.rejected || e.eventType == 'REJECTED') {
      return 'REJECTED';
    }
    if (e.newStatus == ComplaintStatus.escalated ||
        e.eventType == 'FORWARDED') {
      if (e.assignedToTier != null && e.assignedToTier!.isNotEmpty) {
        return 'FORWARDED TO ${e.assignedToTier!.toUpperCase()}';
      }
      return 'FORWARDED';
    }
    if (e.newStatus == ComplaintStatus.cutoffPaused ||
        e.eventType == 'PAUSED') {
      return '20-DAY CUTOFF PAUSED';
    }
    if (e.eventType == 'RESUMED') {
      return 'ADMINISTRATIVE RESUMPTION';
    }
    return e.newStatus.label.toUpperCase();
  }

  String _getActionPrefix() {
    final e = widget.event;
    if (e.isSystemEvent) {
      return 'By:';
    }
    if (e.newStatus == ComplaintStatus.pending || e.eventType == 'SUBMITTED') {
      return 'Submitted by:';
    }
    if (e.newStatus == ComplaintStatus.underReview ||
        e.eventType == 'UNDER_REVIEW') {
      return 'Reviewed by:';
    }
    if (e.newStatus == ComplaintStatus.resolved || e.eventType == 'RESOLVED') {
      return 'Resolved by:';
    }
    if (e.newStatus == ComplaintStatus.rejected || e.eventType == 'REJECTED') {
      return 'Rejected by:';
    }
    if (e.newStatus == ComplaintStatus.escalated ||
        e.eventType == 'FORWARDED') {
      return 'Forwarded by:';
    }
    if (e.eventType == 'RESUMED') {
      return 'Authorized by:';
    }
    return 'Action by:';
  }

  String _getRemarksLabel() {
    final e = widget.event;
    if (e.newStatus == ComplaintStatus.resolved || e.eventType == 'RESOLVED') {
      return 'Resolution:';
    }
    if (e.newStatus == ComplaintStatus.rejected || e.eventType == 'REJECTED') {
      return 'Rejection grounds:';
    }
    if (e.newStatus == ComplaintStatus.escalated ||
        e.eventType == 'FORWARDED') {
      return 'Reason:';
    }
    return 'Remarks:';
  }

  String _getCollapsedSummaryText() {
    final e = widget.event;
    if (e.isSystemEvent) {
      return 'Automated escalation triggered by system redressal engine';
    }
    if (e.newStatus == ComplaintStatus.escalated ||
        e.eventType == 'FORWARDED') {
      final tier = e.assignedToTier ?? 'Next Tier';
      final name = e.assignedToName;
      return name != null && name.isNotEmpty
          ? 'Forwarded to $tier — $name'
          : 'Forwarded to $tier';
    }
    if (e.newStatus == ComplaintStatus.underReview) {
      final name = e.changedByName ?? 'Authorized Officer';
      return 'Under Review by $name';
    }
    if (e.newStatus == ComplaintStatus.resolved) {
      final name = e.changedByName ?? 'Authorized Officer';
      return 'Resolved by $name';
    }
    if (e.newStatus == ComplaintStatus.rejected) {
      final name = e.changedByName ?? 'Authorized Officer';
      return 'Rejected by $name';
    }
    if (e.newStatus == ComplaintStatus.pending) {
      final name = e.changedByName ?? 'Complainant';
      return 'Submitted by $name';
    }
    return '${e.newStatus.label} by ${e.changedByName ?? "System"}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor();
    final statusIcon = _getStatusIcon();
    final stageTitle = _getEventStageTitle();
    final actionPrefix = _getActionPrefix();
    final remarksLabel = _getRemarksLabel();
    final summaryText = _getCollapsedSummaryText();
    final e = widget.event;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Order-Tracking Icon Node & Connecting Vertical Line
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  statusIcon,
                  size: 15,
                  color: Colors.white,
                ),
              ),
              if (!widget.isLast)
                Expanded(
                  child: Container(
                    width: 2.5,
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.space12),

          // Right Column: Interactive / Expandable Content Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space16),
              child: InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(AppSpacing.space12),
                  decoration: BoxDecoration(
                    color: _isExpanded
                        ? theme.colorScheme.surface
                        : theme.colorScheme.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    border: Border.all(
                      color: _isExpanded
                          ? statusColor.withValues(alpha: 0.5)
                          : theme.colorScheme.outline.withValues(alpha: 0.3),
                      width: _isExpanded ? 1.5 : 1.0,
                    ),
                    boxShadow: _isExpanded
                        ? [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Stage Title + Local Time + Expand Chevron
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              stageTitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppDateTimeUtils.formatLocalDateTime(
                                    e.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: statusColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Collapsed / One-Line Summary
                      Text(
                        summaryText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.9),
                        ),
                      ),

                      // Expanded Details
                      if (_isExpanded) ...[
                        const SizedBox(height: AppSpacing.space12),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.space12),

                        // Actor Detail Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.space8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.25),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSmall),
                            border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Role Prefix (e.g., "Submitted by:", "Reviewed by:")
                              Text(
                                actionPrefix,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),

                              if (e.isSystemEvent) ...[
                                Text(
                                  'System Redressal Engine (AUTOMATED)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FontStyle.italic,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ] else ...[
                                // Full Name with Student Indicator
                                Row(
                                  children: [
                                    Text(
                                      (e.changedByName != null &&
                                              e.changedByName!
                                                  .trim()
                                                  .isNotEmpty)
                                          ? e.changedByName!
                                          : (e.changedByRole?.toLowerCase() ==
                                                  'student'
                                              ? 'Complainant Student'
                                              : 'Authorized Officer'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    if (e.changedByRole?.toLowerCase() ==
                                        'student') ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme.primaryContainer
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '(STUDENT)',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                // Designation
                                if (e.actorDesignation != null &&
                                    e.actorDesignation!.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    e.actorDesignation!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],

                                // Department
                                if (e.changedByDept != null &&
                                    e.changedByDept!.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    e.changedByDept!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ],

                              // Destination Tier & Name (if Forwarded)
                              if ((e.newStatus == ComplaintStatus.escalated ||
                                      e.eventType == 'FORWARDED') &&
                                  e.assignedToTier != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Forwarded to: ${e.assignedToTier!}${e.assignedToName != null ? ' — ${e.assignedToName!}' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Remarks / Resolution Memo / Justification
                        if (e.remarks != null &&
                            e.remarks!.trim().isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.space8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.space8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSmall),
                              border: Border.all(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  remarksLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  e.remarks!.trim(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
