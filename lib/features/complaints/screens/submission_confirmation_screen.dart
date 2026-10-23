import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartify/app.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/primary_button.dart';
import 'package:smartify/features/complaints/models/complaint_submission_result.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';
import 'package:smartify/features/tracking/services/tracking_service.dart';

/// SMARTIFY Grievance Submission Confirmation Screen
/// Provides instant feedback, copies tracking number, and summarizes redressal path.
class SubmissionConfirmationScreen extends StatelessWidget {
  final ComplaintSubmissionResult result;

  const SubmissionConfirmationScreen({
    super.key,
    required this.result,
  });

  void _copyTrackingNumber(BuildContext context) {
    Clipboard.setData(ClipboardData(text: result.trackingNumber));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Tracking Reference ${result.trackingNumber} copied to clipboard!'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grievance Submitted Successfully',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        automaticallyImplyLeading: false,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.space12),

              // 1. Success Icon Container
              Container(
                padding: const EdgeInsets.all(AppSpacing.space20),
                decoration: BoxDecoration(
                  color: AppColors.successContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                      width: 2),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    size: 54, color: AppColors.success),
              ),

              const SizedBox(height: AppSpacing.space16),

              Text(
                'Submission Confirmed',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: AppSpacing.space4),

              Text(
                'Your grievance has been submitted to the appropriate department authority.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),

              const SizedBox(height: AppSpacing.space24),

              // 2. Tracking Reference Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  border:
                      Border.all(color: theme.colorScheme.primary, width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      'UNIQUE TRACKING REFERENCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    Text(
                      result.trackingNumber,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusPill)),
                      ),
                      onPressed: () => _copyTrackingNumber(context),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('COPY REFERENCE',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space20),

              // 3. Metadata Breakdown Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Column(
                  children: [
                    _buildRow('Category', result.category, theme),
                    const Divider(height: 16),
                    _buildRow('Department', result.departmentName, theme),
                    const Divider(height: 16),
                    _buildRow(
                        'Incident Date',
                        AppDateTimeUtils.formatIncidentDate(
                            result.incidentDate),
                        theme),
                    const Divider(height: 16),
                    _buildRow(
                        'Logged At',
                        AppDateTimeUtils.formatLocalDateTime(
                            result.submittedAt),
                        theme),
                    const Divider(height: 16),
                    _buildRow(
                      'Initial Status',
                      ComplaintStatus.fromCode(result.status).label,
                      theme,
                      valueColor: ComplaintStatus.fromCode(result.status).color,
                    ),
                    const Divider(height: 16),
                    _buildRow('Starting Tier', result.currentTierTitle, theme,
                        valueColor: theme.colorScheme.primary),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space24),

              // 4. Primary Actions
              PrimaryButton(
                text: 'TRACK GRIEVANCE',
                icon: Icons.track_changes_rounded,
                onPressed: () async {
                  final service = TrackingService();
                  final grievance =
                      await service.fetchComplaintById(result.complaintId);
                  if (context.mounted) {
                    if (grievance != null) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ComplaintDetailScreen(grievance: grievance),
                        ),
                      );
                    } else {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => const PortalNavigationShell(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                },
              ),

              const SizedBox(height: AppSpacing.space12),

              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize:
                      const Size(double.infinity, AppSpacing.minTouchTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const PortalNavigationShell(),
                    ),
                    (route) => false,
                  );
                },
                child: const Text('BACK TO HOME',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, ThemeData theme,
      {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
