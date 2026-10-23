import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/app_text_field.dart';
import 'package:smartify/core/widgets/primary_button.dart';
import 'package:smartify/features/escalation/providers/escalation_provider.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Admin Cutoff Resumption Dialog
/// Collects authorized resumption notes and re-activates frozen grievances.
class AdminResumeDialog extends StatefulWidget {
  final GrievanceModel grievance;

  const AdminResumeDialog({super.key, required this.grievance});

  static Future<void> show(BuildContext context, GrievanceModel grievance) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminResumeDialog(grievance: grievance),
    );
  }

  @override
  State<AdminResumeDialog> createState() => _AdminResumeDialogState();
}

class _AdminResumeDialogState extends State<AdminResumeDialog> {
  final TextEditingController _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleResume() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<EscalationProvider>();
    final success = await provider.resumeComplaint(
      complaintId: widget.grievance.id,
      resumptionNotes: _notesController.text.trim(),
    );

    if (success && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Grievance ${widget.grievance.trackingNumber} successfully resumed.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<EscalationProvider>();

    return Container(
      padding: EdgeInsets.only(
        top: AppSpacing.space20,
        left: AppSpacing.space20,
        right: AppSpacing.space20,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.space24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusMedium)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Administrative Resumption',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        widget.grievance.trackingNumber,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space12),

              // Policy Info Banner
              Container(
                padding: const EdgeInsets.all(AppSpacing.space12),
                decoration: BoxDecoration(
                  color: AppColors.statusCutoffPaused.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(
                      color:
                          AppColors.statusCutoffPaused.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.pause_circle_filled,
                        color: AppColors.statusCutoffPaused, size: 20),
                    const SizedBox(width: AppSpacing.space8),
                    Expanded(
                      child: Text(
                        'This grievance reached the 20-calendar-day campus cutoff limit. Automated cron escalation was frozen. Resumption requires formal administrative justification.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.85),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space16),

              // Mandatory Notes Input
              AppTextField(
                label: 'Formal Resumption Justification',
                isRequired: true,
                controller: _notesController,
                hintText:
                    'State the administrative reasoning, dean sign-off, or special instructions to restart investigation...',
                minLines: 3,
                maxLines: 5,
                validator: (val) {
                  if (val == null || val.trim().length < 10) {
                    return 'Justification notes must be at least 10 characters.';
                  }
                  return null;
                },
              ),

              if (provider.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.space12),
                Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],

              const SizedBox(height: AppSpacing.space20),

              // Submit Button
              PrimaryButton(
                text: 'AUTHORIZE & UNFREEZE',
                isLoading: provider.isResuming,
                onPressed: _handleResume,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
