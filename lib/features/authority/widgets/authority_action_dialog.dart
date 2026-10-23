import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/app_text_field.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/primary_button.dart';
import 'package:smartify/core/widgets/sla_countdown_badge.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/authority/providers/authority_workflow_provider.dart';
import 'package:smartify/features/authority/utils/authority_workflow_permissions.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';

/// SMARTIFY Authority Triage Action Modal
/// Enforces distinct action button hierarchies (Claim, Under Review, Resolve, Reject, Forward)
/// and validation gates with confirmation before terminal actions.
class AuthorityActionDialog extends StatefulWidget {
  final GrievanceModel grievance;
  final TriageActionType? initialAction;

  const AuthorityActionDialog({
    super.key,
    required this.grievance,
    this.initialAction,
  });

  static Future<void> show(
    BuildContext context,
    GrievanceModel grievance, {
    TriageActionType? initialAction,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AuthorityActionDialog(
        grievance: grievance,
        initialAction: initialAction,
      ),
    );
  }

  @override
  State<AuthorityActionDialog> createState() => _AuthorityActionDialogState();
}

enum TriageActionType {
  claim,
  underReview,
  resolve,
  reject,
  forward,
}

class _AuthorityActionDialogState extends State<AuthorityActionDialog> {
  final TextEditingController _reasonController = TextEditingController();
  TriageActionType _selectedAction = TriageActionType.underReview;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAction != null) {
      _selectedAction = widget.initialAction!;
    } else if (widget.grievance.assignedAuthorityId == null ||
        widget.grievance.status == ComplaintStatus.pending ||
        widget.grievance.status == ComplaintStatus.escalated) {
      _selectedAction = TriageActionType.claim;
    } else {
      _selectedAction = TriageActionType.resolve;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _isReasonValid {
    final text = _reasonController.text.trim();
    switch (_selectedAction) {
      case TriageActionType.claim:
      case TriageActionType.underReview:
        return true; // Optional for taking under review or claiming
      case TriageActionType.resolve:
      case TriageActionType.reject:
      case TriageActionType.forward:
        return text.length >= 5;
    }
  }

  String get _reasonFieldLabel {
    switch (_selectedAction) {
      case TriageActionType.claim:
        return 'Acceptance Remarks (Optional)';
      case TriageActionType.underReview:
        return 'Review Remarks (Optional)';
      case TriageActionType.resolve:
        return 'Resolution Memo *';
      case TriageActionType.reject:
        return 'Rejection Reason *';
      case TriageActionType.forward:
        return widget.grievance.isOperationalDepartment
            ? 'Governance Escalation Justification *'
            : 'Forwarding Justification *';
    }
  }

  String get _reasonFieldHint {
    switch (_selectedAction) {
      case TriageActionType.claim:
        return 'e.g., Accepting grievance for departmental review...';
      case TriageActionType.underReview:
        return 'e.g., Initiating investigation into the reported issue...';
      case TriageActionType.resolve:
        return 'Detail how the grievance was resolved and action taken...';
      case TriageActionType.reject:
        return 'Specify institutional grounds for rejecting this grievance...';
      case TriageActionType.forward:
        return widget.grievance.isOperationalDepartment
            ? 'State why this operational grievance requires Governance / Admin review...'
            : 'State why this case requires escalation to the next tier...';
    }
  }

  Future<void> _onConfirmAction() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final provider = context.read<AuthorityWorkflowProvider>();
      final reason = _reasonController.text.trim();

      // Check confirmation dialog for final or destructive actions
      if (_selectedAction == TriageActionType.reject) {
        final confirmed = await _showConfirmationDialog(
          title: 'Confirm Grievance Rejection',
          message:
              'Are you sure you want to reject grievance ${widget.grievance.trackingNumber}? This is a permanent closure action.',
          confirmText: 'REJECT GRIEVANCE',
          isDestructive: true,
        );
        if (!confirmed) return;
      } else if (_selectedAction == TriageActionType.resolve) {
        final confirmed = await _showConfirmationDialog(
          title: 'Confirm Grievance Resolution',
          message:
              'Are you sure you want to mark grievance ${widget.grievance.trackingNumber} as RESOLVED? This will notify the student and conclude redressal.',
          confirmText: 'RESOLVE GRIEVANCE',
          isDestructive: false,
        );
        if (!confirmed) return;
      }

      if (!mounted) return;

      if (_selectedAction == TriageActionType.claim) {
        final ok = await provider.claimComplaint(widget.grievance.id);
        if (ok && mounted) {
          final trackingProv = context.read<StudentTrackingProvider>();
          final nav = Navigator.of(context);
          await trackingProv.refreshSelectedComplaint();
          if (mounted) {
            nav.pop();
          }
        }
        return;
      }

      if (_selectedAction == TriageActionType.forward) {
        final ok = await provider.forwardComplaint(reason: reason);
        if (ok && mounted) {
          final trackingProv = context.read<StudentTrackingProvider>();
          final nav = Navigator.of(context);
          await trackingProv.refreshSelectedComplaint();
          if (mounted) {
            nav.pop();
          }
        }
        return;
      }

      ComplaintStatus targetStatus;
      switch (_selectedAction) {
        case TriageActionType.claim:
        case TriageActionType.underReview:
          targetStatus = ComplaintStatus.underReview;
          break;
        case TriageActionType.resolve:
          targetStatus = ComplaintStatus.resolved;
          break;
        case TriageActionType.reject:
          targetStatus = ComplaintStatus.rejected;
          break;
        case TriageActionType.forward:
          targetStatus = ComplaintStatus.escalated;
          break;
      }

      final remarks = reason.isNotEmpty
          ? reason
          : 'Status changed to ${targetStatus.label}.';

      final ok = await provider.processStatusChange(
        newStatus: targetStatus,
        remarks: remarks,
        resolutionNotes:
            _selectedAction == TriageActionType.resolve ? reason : null,
      );

      if (ok && mounted) {
        final trackingProv = context.read<StudentTrackingProvider>();
        final nav = Navigator.of(context);
        await trackingProv.refreshSelectedComplaint();
        if (mounted) {
          nav.pop();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmText,
    required bool isDestructive,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDestructive ? AppColors.error : AppColors.statusResolved,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<AuthorityWorkflowProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.currentUser;

    final canAct = AuthorityWorkflowPermissions.canAct(
      user: currentUser,
      grievance: widget.grievance,
    );
    final isAccepted = AuthorityWorkflowPermissions.isCaseAccepted(
      user: currentUser,
      grievance: widget.grievance,
    );
    final canResolve = AuthorityWorkflowPermissions.canResolve(
      user: currentUser,
      grievance: widget.grievance,
    );
    final canReject = AuthorityWorkflowPermissions.canReject(
      user: currentUser,
      grievance: widget.grievance,
    );
    final canForward = AuthorityWorkflowPermissions.canForward(
      user: currentUser,
      grievance: widget.grievance,
    );
    final forwardLabel =
        AuthorityWorkflowPermissions.nextForwardLabel(widget.grievance);
    final isTerminal = widget.grievance.status.isTerminal;

    // Safety adjustment: If case is not yet accepted, force claim
    if (!isAccepted) {
      _selectedAction = TriageActionType.claim;
    } else if (_selectedAction == TriageActionType.claim) {
      _selectedAction = TriageActionType.resolve;
    } else if (_selectedAction == TriageActionType.reject && !canReject) {
      _selectedAction = TriageActionType.resolve;
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space20,
          AppSpacing.space20,
          AppSpacing.space20,
          AppSpacing.space24,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusMedium)),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Triage Case Action',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space12),

              // Comprehensive Case Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tracking ID + Badges
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          widget.grievance.trackingNumber,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GrievanceStatusBadge(
                                status: widget.grievance.status,
                                isCompact: true),
                            const SizedBox(width: 6),
                            SlaCountdownBadge(grievance: widget.grievance),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Title
                    Text(
                      widget.grievance.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Metadata details grid
                    _buildMetaRow(
                      'Student',
                      (widget.grievance.studentName != null &&
                              widget.grievance.studentName!.trim().isNotEmpty)
                          ? widget.grievance.studentName!
                          : 'Student information unavailable',
                      theme,
                    ),
                    const SizedBox(height: 4),
                    _buildMetaRow(
                        'Department',
                        '${widget.grievance.departmentName} (${widget.grievance.category})',
                        theme),
                    const SizedBox(height: 4),
                    _buildMetaRow('Current Level',
                        widget.grievance.currentAuthorityLevelTitle, theme),
                    const SizedBox(height: 4),
                    _buildMetaRow(
                      'Assigned Authority',
                      widget.grievance.assignedAuthorityName ??
                          'Awaiting authority assignment',
                      theme,
                      isHighlighted:
                          widget.grievance.assignedAuthorityName != null,
                    ),
                    const SizedBox(height: 4),
                    _buildMetaRow(
                      'Acting As',
                      (widget.grievance.assignedAuthorityId == currentUser?.id)
                          ? (currentUser?.fullName ?? 'Assigned Officer')
                          : (widget.grievance.assignedAuthorityId == null
                              ? '${currentUser?.fullName ?? 'Authority'} (Unassigned Case)'
                              : 'Not assigned to you (${currentUser?.fullName ?? 'Observer'})'),
                      theme,
                      isHighlighted: widget.grievance.assignedAuthorityId ==
                          currentUser?.id,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space16),

              if (isTerminal) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.outline.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                  child: const Text(
                    'This grievance is in a terminal state (Resolved or Rejected). Further triage actions are locked.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ] else if (!canAct) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.outline.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                  child: Text(
                    AuthorityWorkflowPermissions.getInformationalStatusMessage(
                          user: currentUser,
                          grievance: widget.grievance,
                        ) ??
                        'You are not authorized to perform redressal actions on this grievance.',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ] else ...[
                // Action Buttons Hierarchy
                const Text(
                  'Select Redressal Action:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),

                // Distinct Action Buttons Grid
                Column(
                  children: [
                    if (!isAccepted) ...[
                      _buildActionSelectionButton(
                        action: TriageActionType.claim,
                        label: 'ACCEPT CASE / TAKE RESPONSIBILITY',
                        subtitle: 'Assign to active caseload & begin review',
                        color: theme.colorScheme.primary,
                        icon: Icons.assignment_turned_in_rounded,
                      ),
                    ] else ...[
                      // Row 1: Resolve & Forward
                      Row(
                        children: [
                          if (canResolve)
                            Expanded(
                              child: _buildActionSelectionButton(
                                action: TriageActionType.resolve,
                                label: 'RESOLVE',
                                subtitle: 'Formal resolution',
                                color: AppColors.statusResolved,
                                icon: Icons.check_circle_outline_rounded,
                              ),
                            ),
                          if (canResolve && canForward) const SizedBox(width: 8),
                          if (canForward)
                            Expanded(
                              child: _buildActionSelectionButton(
                                action: TriageActionType.forward,
                                label: forwardLabel,
                                subtitle: widget.grievance.isOperationalDepartment
                                    ? 'Governance review'
                                    : 'Escalate to L${widget.grievance.currentAuthorityLevelNumber + 1}',
                                color: AppColors.statusCutoffPaused,
                                icon: Icons.trending_up_rounded,
                              ),
                            ),
                        ],
                      ),
                      if (canReject) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildActionSelectionButton(
                                action: TriageActionType.reject,
                                label: 'REJECT',
                                subtitle: 'Formal dismissal with grounds',
                                color: AppColors.error,
                                icon: Icons.cancel_outlined,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),

                const SizedBox(height: AppSpacing.space16),

                // Dynamic Input Field for the selected action
                AppTextField(
                  label: _reasonFieldLabel,
                  isRequired: _selectedAction != TriageActionType.underReview &&
                      _selectedAction != TriageActionType.claim,
                  controller: _reasonController,
                  hintText: _reasonFieldHint,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: AppSpacing.space20),

                // Error Display if any
                if (prov.errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      prov.errorMessage!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                // Final Confirmation Button
                PrimaryButton(
                  text: _selectedAction == TriageActionType.claim
                      ? 'CONFIRM CASE ACCEPTANCE'
                      : (_selectedAction == TriageActionType.forward &&
                              widget.grievance.isOperationalDepartment
                          ? 'CONFIRM ESCALATION TO GOVERNANCE'
                          : 'CONFIRM ${_selectedAction.name.toUpperCase()}'),
                  icon: Icons.check_rounded,
                  isLoading: prov.isProcessingAction || _isSubmitting,
                  onPressed: (_isReasonValid &&
                          !prov.isProcessingAction &&
                          !_isSubmitting)
                      ? _onConfirmAction
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, ThemeData theme,
      {bool isHighlighted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
              color: isHighlighted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionSelectionButton({
    required TriageActionType action,
    required String label,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _selectedAction == action;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedAction = action;
        });
      },
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          border: Border.all(
            color: isSelected
                ? color
                : theme.colorScheme.outline.withValues(alpha: 0.5),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.25 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? color : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    );
  }
}
