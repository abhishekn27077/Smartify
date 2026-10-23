import 'package:smartify/features/auth/models/user_session_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Canonical Authority Workflow & Action Permissions Guard
///
/// Strictly determines whether the currently authenticated user is permitted
/// to view or execute redressal actions on a given grievance.
///
/// Invariants:
/// - Only the current authority tier, matching department, and current assignee may act.
/// - Admin is a governance/audit role and does NOT receive normal grievance action controls.
/// - Once a case is forwarded to Level N+1, Level N authorities lose all action controls.
/// - Level 1 authorities are strictly prohibited from rejecting grievances.
/// - Grievances must be explicitly accepted (claim) before triage actions unlock.
/// - Terminal (RESOLVED, REJECTED) and frozen (CUTOFF_PAUSED) cases permit no actions.
class AuthorityWorkflowPermissions {
  const AuthorityWorkflowPermissions._();

  /// Evaluates whether the authenticated user has permission to perform redressal actions.
  static bool canAct({
    required UserSessionModel? user,
    required GrievanceModel grievance,
  }) {
    if (user == null) return false;

    // Terminal states allow no further triage actions
    if (grievance.status.isTerminal) return false;

    // 20-day governance cutoff freezes normal progression pending admin review
    if (grievance.status == ComplaintStatus.cutoffPaused ||
        grievance.isCutoffPaused) {
      return false;
    }

    // Admins hold supervisory governance role, NOT normal grievance reviewer.
    // Admin must not receive ordinary L1/L2/L3 grievance action controls.
    if (user.isAdmin) return false;

    // Only authority role can act
    if (!user.isAuthority) return false;

    // 1. Department Scoping:
    // User must belong to the grievance's responsible department (unless campus-wide authority)
    if (user.departmentId != null &&
        grievance.departmentId.isNotEmpty &&
        user.departmentId != grievance.departmentId) {
      return false;
    }

    // 2. Tier Scoping:
    // User authority level MUST match the grievance's active tier
    final userLevelNum = user.authorityLevelNumber;
    final grievanceLevelNum = grievance.currentAuthorityLevelNumber;
    if (userLevelNum != null && userLevelNum != grievanceLevelNum) {
      return false;
    }

    if (user.authorityLevelId != null &&
        grievance.currentAuthorityLevelId.isNotEmpty &&
        user.authorityLevelId != grievance.currentAuthorityLevelId) {
      return false;
    }

    // 3. Ownership / Assignment Scoping:
    // If assigned to someone else at this tier, the caller cannot act.
    // If assigned to caller, caller can act.
    // If unassigned at this tier, authority at this tier may triage/claim it.
    final isAssignedToMe = grievance.assignedAuthorityId == user.id;
    final isUnassigned = grievance.assignedAuthorityId == null;

    return isAssignedToMe || isUnassigned;
  }

  /// Evaluates whether the case has been explicitly accepted by the current authority
  static bool isCaseAccepted({
    required UserSessionModel? user,
    required GrievanceModel grievance,
  }) {
    if (user == null) return false;
    final isAssignedToMe = grievance.assignedAuthorityId == user.id;
    final isPendingOrEscalated = grievance.status == ComplaintStatus.pending ||
        grievance.status == ComplaintStatus.escalated;
    return isAssignedToMe && !isPendingOrEscalated;
  }

  /// Whether the Under Review action is actionable
  static bool canUnderReview({
    required UserSessionModel? user,
    required GrievanceModel grievance,
  }) {
    if (!canAct(user: user, grievance: grievance)) return false;
    return grievance.status != ComplaintStatus.underReview;
  }

  /// Whether Resolve action is allowed.
  /// Case must be explicitly accepted first.
  static bool canResolve({
    required UserSessionModel? user,
    required GrievanceModel grievance,
  }) {
    if (!canAct(user: user, grievance: grievance)) return false;
    return isCaseAccepted(user: user, grievance: grievance);
  }

  /// Whether Reject action is allowed.
  /// Strict policy:
  /// - Level 1 authorities CANNOT reject grievances.
  /// - Only Level >= 2 can reject.
  /// - Case must be explicitly accepted first.
  static bool canReject({
    required UserSessionModel? user,
    required GrievanceModel grievance,
  }) {
    if (!canAct(user: user, grievance: grievance)) return false;
    if (grievance.currentAuthorityLevelNumber == 1) return false;
    return isCaseAccepted(user: user, grievance: grievance);
  }

  /// Whether Forward action is allowed.
  /// Case must be explicitly accepted first.
  static bool canForward({
    required UserSessionModel? user,
    required GrievanceModel grievance,
    int maxConfiguredLevel = 4,
  }) {
    if (!canAct(user: user, grievance: grievance)) return false;
    if (!isCaseAccepted(user: user, grievance: grievance)) return false;
    if (grievance.isOperationalDepartment) {
      return grievance.currentAuthorityLevelNumber == 1;
    }
    if (grievance.currentAuthorityLevelNumber >= maxConfiguredLevel) {
      return false;
    }
    return true;
  }

  /// Computes the exact button label for forwarding or operational escalation
  static String nextForwardLabel(GrievanceModel grievance) {
    if (grievance.isOperationalDepartment) {
      return 'ESCALATE TO GOVERNANCE';
    }
    final nextLevel = grievance.currentAuthorityLevelNumber + 1;
    return 'FORWARD TO LEVEL $nextLevel';
  }

  /// Computes clear, context-aware informational status text when action controls are hidden
  static String? getInformationalStatusMessage({
    required UserSessionModel? user,
    required GrievanceModel grievance,
  }) {
    if (grievance.status == ComplaintStatus.resolved) {
      final resolver = grievance.assignedAuthorityName;
      return resolver != null && resolver.isNotEmpty
          ? 'Resolved by $resolver. Case closed.'
          : 'Resolved. Case closed.';
    }

    if (grievance.status == ComplaintStatus.rejected) {
      final rejecter = grievance.assignedAuthorityName;
      return rejecter != null && rejecter.isNotEmpty
          ? 'Rejected by $rejecter. Case closed.'
          : 'Rejected. Case closed.';
    }

    if (grievance.status == ComplaintStatus.cutoffPaused ||
        grievance.isCutoffPaused) {
      return '20-day governance cutoff reached. Automated progression is frozen pending administrative review.';
    }

    if (user != null && user.isAdmin) {
      return 'Viewing in Governance & Audit mode. Grievance redressal is managed by assigned departmental authorities.';
    }

    if (user != null && user.isAuthority) {
      final userLevel = user.authorityLevelNumber ?? 1;
      final grievanceLevel = grievance.currentAuthorityLevelNumber;

      if (userLevel < grievanceLevel) {
        return 'Forwarded to Level $grievanceLevel (${grievance.currentAuthorityLevelTitle}) — no action required from you.';
      }
      if (userLevel > grievanceLevel) {
        return 'Currently pending at Level $grievanceLevel (${grievance.currentAuthorityLevelTitle}) — awaiting tier escalation.';
      }
      if (grievance.assignedAuthorityId != null &&
          grievance.assignedAuthorityId != user.id) {
        final assignee = grievance.assignedAuthorityName ?? 'assigned officer';
        return 'Assigned to $assignee — view only.';
      }
    }

    return null;
  }
}
