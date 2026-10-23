import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';

/// SMARTIFY Standard Complaint Status Enumeration
enum ComplaintStatus {
  pending('PENDING', 'Pending Intake'),
  underReview('UNDER_REVIEW', 'Under Review'),
  inProgress('IN_PROGRESS', 'In Progress'),
  escalated('ESCALATED', 'Escalated'),
  cutoffPaused('CUTOFF_PAUSED', 'Cutoff Paused (20d)'),
  resolved('RESOLVED', 'Resolved'),
  rejected('REJECTED', 'Rejected');

  final String code;
  final String label;

  const ComplaintStatus(this.code, this.label);

  static ComplaintStatus fromCode(String code) {
    return ComplaintStatus.values.firstWhere(
      (s) => s.code == code.toUpperCase(),
      orElse: () => ComplaintStatus.pending,
    );
  }

  Color get color {
    switch (this) {
      case ComplaintStatus.pending:
        return AppColors.statusPending;
      case ComplaintStatus.underReview:
        return AppColors.statusUnderReview;
      case ComplaintStatus.inProgress:
        return AppColors.statusInProgress;
      case ComplaintStatus.escalated:
        return AppColors.statusEscalated;
      case ComplaintStatus.cutoffPaused:
        return AppColors.statusCutoffPaused;
      case ComplaintStatus.resolved:
        return AppColors.statusResolved;
      case ComplaintStatus.rejected:
        return AppColors.statusRejected;
    }
  }

  IconData get icon {
    switch (this) {
      case ComplaintStatus.pending:
        return Icons.hourglass_empty_rounded;
      case ComplaintStatus.underReview:
        return Icons.sync_rounded;
      case ComplaintStatus.inProgress:
        return Icons.engineering_rounded;
      case ComplaintStatus.escalated:
        return Icons.trending_up_rounded;
      case ComplaintStatus.cutoffPaused:
        return Icons.pause_circle_outline_rounded;
      case ComplaintStatus.resolved:
        return Icons.check_circle_outline_rounded;
      case ComplaintStatus.rejected:
        return Icons.cancel_outlined;
    }
  }

  /// State Machine Guard: Returns valid subsequent target statuses
  List<ComplaintStatus> get permittedNextStatuses {
    switch (this) {
      case ComplaintStatus.pending:
        return [ComplaintStatus.underReview, ComplaintStatus.rejected];
      case ComplaintStatus.underReview:
        return [
          ComplaintStatus.inProgress,
          ComplaintStatus.escalated,
          ComplaintStatus.resolved,
          ComplaintStatus.rejected,
        ];
      case ComplaintStatus.inProgress:
        return [
          ComplaintStatus.escalated,
          ComplaintStatus.resolved,
          ComplaintStatus.rejected,
        ];
      case ComplaintStatus.escalated:
        return [
          ComplaintStatus.underReview,
          ComplaintStatus.resolved,
          ComplaintStatus.rejected,
        ];
      case ComplaintStatus.cutoffPaused:
        // Cutoff paused grievances can only resume to UNDER_REVIEW via Admin sign-off
        return [ComplaintStatus.underReview];
      case ComplaintStatus.resolved:
      case ComplaintStatus.rejected:
        return []; // Terminal states
    }
  }

  bool canTransitionTo(ComplaintStatus nextStatus) {
    return permittedNextStatuses.contains(nextStatus);
  }

  bool get isTerminal =>
      this == ComplaintStatus.resolved || this == ComplaintStatus.rejected;
}
