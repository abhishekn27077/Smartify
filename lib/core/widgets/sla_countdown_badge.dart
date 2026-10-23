import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY SLA Deadline Urgency Badge
class SlaCountdownBadge extends StatelessWidget {
  final GrievanceModel grievance;

  const SlaCountdownBadge({super.key, required this.grievance});

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData icon;

    if (grievance.isCutoffPaused) {
      badgeColor = AppColors.statusCutoffPaused;
      icon = Icons.pause_circle_filled;
    } else if (grievance.isSlaBreached) {
      badgeColor = AppColors.statusSlaBreached;
      icon = Icons.warning_rounded;
    } else if (grievance.timeRemaining.inHours < 24) {
      badgeColor = AppColors.statusEscalated;
      icon = Icons.timer_outlined;
    } else {
      badgeColor = AppColors.statusUnderReview;
      icon = Icons.access_time_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            grievance.formattedTimeRemaining,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
