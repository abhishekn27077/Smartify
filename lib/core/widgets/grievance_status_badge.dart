import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';

/// SMARTIFY Multi-Token Grievance Status Badge
class GrievanceStatusBadge extends StatelessWidget {
  final ComplaintStatus status;
  final bool isCompact;

  const GrievanceStatusBadge({
    super.key,
    required this.status,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = status.color;

    return Semantics(
      label: 'Status: ${status.label}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 12,
          vertical: isCompact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status.icon,
              size: isCompact ? 12 : 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              isCompact && status == ComplaintStatus.cutoffPaused
                  ? 'Cutoff Paused'
                  : status.label,
              style: TextStyle(
                color: color,
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
