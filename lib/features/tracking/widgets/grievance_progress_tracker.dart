import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/utils/authority_designation_resolver.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

enum StepStageState {
  completed,
  current,
  forwarded,
  rejected,
  notConfigured,
  upcoming,
}

class TrackerStageData {
  final int stageNumber;
  final String title;
  final String shortTitle;
  final StepStageState state;
  final String statusDescription;
  final String? actorName;
  final String? actorDesignation;
  final String? department;
  final DateTime? timestamp;
  final String? remarks;
  final bool isAutomated;

  const TrackerStageData({
    required this.stageNumber,
    required this.title,
    required this.shortTitle,
    required this.state,
    required this.statusDescription,
    this.actorName,
    this.actorDesignation,
    this.department,
    this.timestamp,
    this.remarks,
    this.isAutomated = false,
  });
}

/// SMARTIFY 2-Layer Visual Order-Tracking Journey
/// Displays an intuitive, e-commerce order-style vertical progress tracker.
/// Tapping any node displays a compact detail card with real actor identity,
/// timestamps in local device time, and remarks.
class GrievanceProgressTracker extends StatelessWidget {
  final GrievanceModel grievance;
  final List<TimelineEventModel> events;

  const GrievanceProgressTracker({
    super.key,
    required this.grievance,
    required this.events,
  });

  List<TrackerStageData> _buildStages() {
    final stages = <TrackerStageData>[];

    // 1. SUBMITTED
    TimelineEventModel? submitEvent;
    for (final e in events) {
      if (e.eventType == 'SUBMITTED' ||
          e.newStatus == ComplaintStatus.pending) {
        submitEvent = e;
        break;
      }
    }
    stages.add(
      TrackerStageData(
        stageNumber: 0,
        title: 'Grievance Submitted',
        shortTitle: 'Submitted',
        state: StepStageState.completed,
        statusDescription: 'Logged successfully in system',
        actorName:
            submitEvent?.changedByName ?? grievance.studentName ?? 'Student',
        actorDesignation: 'Student Filer',
        department: grievance.departmentName,
        timestamp: submitEvent?.createdAt ?? grievance.createdAt,
        remarks: grievance.title,
      ),
    );

    if (grievance.isOperationalDepartment) {
      // OPERATIONAL DEPARTMENTS (Hostel, IT, Finance, Infrastructure)
      // Single Responsible Authority (Level 1) -> Direct Resolution or Governance Escalation
      final l1Title = AuthorityDesignationResolver.resolveDesignation(
        levelNumber: 1,
        departmentCode: grievance.departmentCode,
        departmentName: grievance.departmentName,
      );
      stages.add(_buildAuthorityStage(
        levelNumber: 1,
        title: l1Title,
        shortTitle: 'L1 Officer',
      ));

      // Level 2: Not Configured for this operational department
      stages.add(
        TrackerStageData(
          stageNumber: 2,
          title: 'Level 2 — Not Configured',
          shortTitle: 'L2 (N/A)',
          state: StepStageState.notConfigured,
          statusDescription: 'Operational department — single responsible authority',
          actorName: 'Single-tier Operational Structure',
          actorDesignation: 'Direct Resolution or Governance Escalation',
          department: grievance.departmentName,
          remarks:
              'Higher department tiers are not configured for ${grievance.departmentName}. The Level 1 Officer handles direct resolution. If unresolved or requiring institutional action, this case escalates directly to Institutional Governance / Admin Review.',
        ),
      );

      // Check if escalated to Governance / Admin Review
      final hasGovernanceEscalation = grievance.currentAuthorityLevelNumber >= 4 ||
          grievance.status == ComplaintStatus.escalated ||
          events.any((e) =>
              (e.actorAuthorityLevel ?? 0) >= 4 ||
              e.assignedToTier?.contains('Level 4') == true ||
              e.remarks?.contains('Governance') == true);

      if (hasGovernanceEscalation) {
        final isCurrent = grievance.currentAuthorityLevelNumber >= 4 &&
            !grievance.status.isTerminal;
        stages.add(
          TrackerStageData(
            stageNumber: 4,
            title: 'Institutional Governance Review',
            shortTitle: 'Governance',
            state: isCurrent ? StepStageState.current : StepStageState.completed,
            statusDescription: isCurrent
                ? 'Under Admin & Governance Review'
                : 'Governance Review Concluded',
            actorName: grievance.assignedAuthorityName ??
                'Institutional Governance Board',
            actorDesignation: 'Campus Administrator / Ombudsman',
            department: 'Campus Governance',
            timestamp: grievance.status == ComplaintStatus.escalated
                ? grievance.updatedAt
                : null,
            remarks: grievance.statusRemarks ??
                'Operational escalation to Institutional Governance for administrative resolution.',
          ),
        );
      }
    } else {
      // ACADEMIC DEPARTMENTS (MCA, MBA, M.Com, etc.)
      // 3-Tier Canonical Structure: L1 Faculty -> L2 HoD -> L3 Dean -> Governance
      stages.add(_buildAuthorityStage(
        levelNumber: 1,
        title: 'Level 1 — Faculty / Dept Officer',
        shortTitle: 'L1 Review',
      ));

      stages.add(_buildAuthorityStage(
        levelNumber: 2,
        title: 'Level 2 — Head of Department (HoD)',
        shortTitle: 'L2 Review',
      ));

      final l3Title = AuthorityDesignationResolver.resolveDesignation(
        levelNumber: 3,
        departmentCode: grievance.departmentCode,
        departmentName: grievance.departmentName,
      );
      stages.add(_buildAuthorityStage(
        levelNumber: 3,
        title: l3Title,
        shortTitle: 'L3 Dean',
      ));

      final hasL4 = grievance.currentAuthorityLevelNumber >= 4 ||
          events.any((e) => (e.actorAuthorityLevel ?? 0) >= 4);
      if (hasL4) {
        stages.add(_buildAuthorityStage(
          levelNumber: 4,
          title: 'Level 4 — University Ombudsman Board',
          shortTitle: 'L4 Review',
        ));
      }
    }

    // 6. RESOLUTION / FINAL STATE
    final isResolved = grievance.status == ComplaintStatus.resolved;
    final isRejected = grievance.status == ComplaintStatus.rejected;
    TimelineEventModel? terminalEvent;
    for (final e in events.reversed) {
      if (e.newStatus.isTerminal) {
        terminalEvent = e;
        break;
      }
    }

    if (isResolved) {
      stages.add(
        TrackerStageData(
          stageNumber: 99,
          title: 'Case Resolved',
          shortTitle: 'Resolved',
          state: StepStageState.completed,
          statusDescription: 'Resolution memo issued',
          actorName: terminalEvent?.changedByName ??
              grievance.assignedAuthorityName ??
              'Authorized Officer',
          actorDesignation: terminalEvent?.actorDesignation ??
              grievance.currentAuthorityLevelTitle,
          department: grievance.departmentName,
          timestamp: terminalEvent?.createdAt ??
              grievance.resolvedAt ??
              grievance.updatedAt,
          remarks: grievance.resolutionNotes ?? terminalEvent?.remarks,
        ),
      );
    } else if (isRejected) {
      stages.add(
        TrackerStageData(
          stageNumber: 99,
          title: 'Case Rejected',
          shortTitle: 'Rejected',
          state: StepStageState.rejected,
          statusDescription: 'Grievance formal rejection',
          actorName: terminalEvent?.changedByName ??
              grievance.assignedAuthorityName ??
              'Authorized Officer',
          actorDesignation: terminalEvent?.actorDesignation ??
              grievance.currentAuthorityLevelTitle,
          department: grievance.departmentName,
          timestamp: terminalEvent?.createdAt ?? grievance.updatedAt,
          remarks: grievance.resolutionNotes ??
              terminalEvent?.remarks ??
              'Does not qualify under campus redressal criteria.',
        ),
      );
    } else {
      stages.add(
        const TrackerStageData(
          stageNumber: 99,
          title: 'Resolution',
          shortTitle: 'Resolution',
          state: StepStageState.upcoming,
          statusDescription: 'Pending final review & decision',
        ),
      );
    }

    return stages;
  }

  TrackerStageData _buildAuthorityStage({
    required int levelNumber,
    required String title,
    required String shortTitle,
  }) {
    final currentLevel = grievance.currentAuthorityLevelNumber;

    // Search events for this specific tier
    TimelineEventModel? tierEvent;
    for (final e in events.reversed) {
      if (e.actorAuthorityLevel == levelNumber ||
          (e.newStatus == ComplaintStatus.escalated &&
              e.assignedToTier != null &&
              e.assignedToTier!.contains('Level $levelNumber'))) {
        tierEvent = e;
        break;
      }
    }

    // Check if this level forwarded the case
    TimelineEventModel? forwardEvent;
    for (final e in events) {
      if (e.actorAuthorityLevel == levelNumber &&
          (e.eventType == 'FORWARDED' ||
              e.newStatus == ComplaintStatus.escalated)) {
        forwardEvent = e;
        break;
      }
    }

    if (currentLevel > levelNumber) {
      // Completed / Forwarded past this tier
      return TrackerStageData(
        stageNumber: levelNumber,
        title: title,
        shortTitle: shortTitle,
        state: StepStageState.completed,
        statusDescription: forwardEvent != null
            ? 'Forwarded to ${forwardEvent.assignedToTier ?? 'Next Level'}'
            : 'Review completed & progressed',
        actorName: forwardEvent?.changedByName ??
            tierEvent?.changedByName ??
            'Authorized Officer',
        actorDesignation:
            forwardEvent?.actorDesignation ?? tierEvent?.actorDesignation,
        department: grievance.departmentName,
        timestamp: forwardEvent?.createdAt ?? tierEvent?.createdAt,
        remarks: forwardEvent?.remarks ?? tierEvent?.remarks,
      );
    } else if (currentLevel == levelNumber) {
      // Currently active at this tier
      if (grievance.status.isTerminal) {
        return TrackerStageData(
          stageNumber: levelNumber,
          title: title,
          shortTitle: shortTitle,
          state: grievance.status == ComplaintStatus.resolved
              ? StepStageState.completed
              : StepStageState.rejected,
          statusDescription: grievance.status.label,
          actorName: tierEvent?.changedByName ??
              grievance.assignedAuthorityName ??
              'Authorized Officer',
          actorDesignation: tierEvent?.actorDesignation ??
              grievance.currentAuthorityLevelTitle,
          department: grievance.departmentName,
          timestamp: tierEvent?.createdAt ?? grievance.updatedAt,
          remarks: grievance.resolutionNotes ?? tierEvent?.remarks,
        );
      }

      final isUnderReview = grievance.status == ComplaintStatus.underReview;
      return TrackerStageData(
        stageNumber: levelNumber,
        title: title,
        shortTitle: shortTitle,
        state: StepStageState.current,
        statusDescription: isUnderReview
            ? 'Active Under Review'
            : (grievance.assignedAuthorityName != null
                ? 'Assigned — Action Pending'
                : 'Awaiting Authority Triage'),
        actorName: grievance.assignedAuthorityName ?? tierEvent?.changedByName,
        actorDesignation: grievance.currentAuthorityLevelTitle,
        department: grievance.departmentName,
        timestamp: tierEvent?.createdAt ?? grievance.updatedAt,
        remarks: tierEvent?.remarks,
      );
    } else {
      // Upcoming future tier
      return TrackerStageData(
        stageNumber: levelNumber,
        title: title,
        shortTitle: shortTitle,
        state: StepStageState.upcoming,
        statusDescription: 'Pending escalation if unresolved',
      );
    }
  }

  void _showStageDetail(BuildContext context, TrackerStageData stage) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStateBadge(stage.state),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stage.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stage.statusDescription,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Detailed attributes
              if (stage.actorName != null) ...[
                _buildDetailRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Authority Officer',
                  value: stage.actorName!,
                  theme: theme,
                ),
                const SizedBox(height: 10),
              ],
              if (stage.actorDesignation != null) ...[
                _buildDetailRow(
                  icon: Icons.badge_outlined,
                  label: 'Designation',
                  value: stage.actorDesignation!,
                  theme: theme,
                ),
                const SizedBox(height: 10),
              ],
              if (stage.department != null) ...[
                _buildDetailRow(
                  icon: Icons.business_outlined,
                  label: 'Department',
                  value: stage.department!,
                  theme: theme,
                ),
                const SizedBox(height: 10),
              ],
              if (stage.timestamp != null) ...[
                _buildDetailRow(
                  icon: Icons.access_time_rounded,
                  label: 'Local Timestamp',
                  value: AppDateTimeUtils.formatLocalDateTime(
                    stage.timestamp,
                    includeDayOfWeek: true,
                  ),
                  theme: theme,
                ),
                const SizedBox(height: 10),
              ],
              if (stage.remarks != null && stage.remarks!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceElevatedDark
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OFFICIAL REMARKS / NOTES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stage.remarks!,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Close button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStateBadge(StepStageState state) {
    IconData icon;
    Color color;
    switch (state) {
      case StepStageState.completed:
        icon = Icons.check_circle_rounded;
        color = AppColors.statusResolved;
        break;
      case StepStageState.current:
        icon = Icons.radio_button_checked_rounded;
        color = AppColors.statusUnderReview;
        break;
      case StepStageState.forwarded:
        icon = Icons.forward_rounded;
        color = AppColors.statusEscalated;
        break;
      case StepStageState.rejected:
        icon = Icons.cancel_rounded;
        color = AppColors.statusSlaBreached;
        break;
      case StepStageState.notConfigured:
        icon = Icons.remove_circle_outline_rounded;
        color = const Color(0xFF64748B);
        break;
      case StepStageState.upcoming:
        icon = Icons.radio_button_unchecked_rounded;
        color = const Color(0xFF94A3B8);
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 24, color: color),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stages = _buildStages();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timeline_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'REDRESSAL PROGRESS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Text(
                'Tap step for details',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space16),

          // Vertical Step Trail
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: stages.length,
            separatorBuilder: (context, index) {
              final isPassed = stages[index].state == StepStageState.completed;
              return Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Container(
                  width: 2,
                  height: 18,
                  color: isPassed
                      ? AppColors.statusResolved.withValues(alpha: 0.6)
                      : theme.colorScheme.outline.withValues(alpha: 0.4),
                ),
              );
            },
            itemBuilder: (context, index) {
              final stage = stages[index];
              return _buildStepItem(context, stage, theme);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(
    BuildContext context,
    TrackerStageData stage,
    ThemeData theme,
  ) {
    Color indicatorColor;
    IconData indicatorIcon;
    bool isGlowing = false;

    switch (stage.state) {
      case StepStageState.completed:
        indicatorColor = AppColors.statusResolved;
        indicatorIcon = Icons.check;
        break;
      case StepStageState.current:
        indicatorColor = AppColors.statusUnderReview;
        indicatorIcon = Icons.circle;
        isGlowing = true;
        break;
      case StepStageState.forwarded:
        indicatorColor = AppColors.statusEscalated;
        indicatorIcon = Icons.arrow_forward_rounded;
        break;
      case StepStageState.rejected:
        indicatorColor = AppColors.statusSlaBreached;
        indicatorIcon = Icons.close;
        break;
      case StepStageState.notConfigured:
        indicatorColor = theme.colorScheme.outline.withValues(alpha: 0.45);
        indicatorIcon = Icons.remove_rounded;
        break;
      case StepStageState.upcoming:
        indicatorColor = theme.colorScheme.outline.withValues(alpha: 0.5);
        indicatorIcon = Icons.circle_outlined;
        break;
    }

    final isClickable = stage.state != StepStageState.upcoming ||
        stage.state == StepStageState.notConfigured ||
        stage.actorName != null ||
        stage.timestamp != null;

    return InkWell(
      onTap: isClickable ? () => _showStageDetail(context, stage) : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Node Icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: stage.state == StepStageState.upcoming
                    ? Colors.transparent
                    : indicatorColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: indicatorColor,
                  width: stage.state == StepStageState.current ? 2.5 : 1.5,
                ),
                boxShadow: isGlowing
                    ? [
                        BoxShadow(
                          color: indicatorColor.withValues(alpha: 0.35),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: Icon(
                indicatorIcon,
                size: stage.state == StepStageState.current ? 10 : 14,
                color: indicatorColor,
              ),
            ),
            const SizedBox(width: 12),

            // Step Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        stage.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: stage.state == StepStageState.current
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: stage.state == StepStageState.upcoming
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45)
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (stage.timestamp != null)
                        Text(
                          AppDateTimeUtils.formatLocalDate(stage.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stage.actorName != null
                              ? '${stage.statusDescription} • ${stage.actorName}'
                              : stage.statusDescription,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: stage.state == StepStageState.current
                                ? indicatorColor
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                            fontWeight: stage.state == StepStageState.current
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isClickable)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
