import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/utils/date_validator.dart';

/// SMARTIFY Restricted Date Picker Field
/// Enforces institutional policy: strictly [Today - 7 days, Today].
class RestrictedDatePicker extends StatelessWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final String? errorText;

  const RestrictedDatePicker({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.errorText,
  });

  Future<void> _pickDate(BuildContext context) async {
    final earliest = DateValidator.getEarliestPermittedDate();
    final latest = DateValidator.getLatestPermittedDate();
    final initial =
        selectedDate != null && DateValidator.isValidIncidentDate(selectedDate!)
            ? DateValidator.stripTime(selectedDate!)
            : latest;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: latest,
      helpText: 'SELECT INCIDENT DATE (LAST 7 DAYS ONLY)',
      cancelText: 'CANCEL',
      confirmText: 'SELECT',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: Theme.of(context).colorScheme.surface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      onDateSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earliest = DateValidator.getEarliestPermittedDate();
    final latest = DateValidator.getLatestPermittedDate();
    final dateFormat = DateFormat('EEE, dd MMM yyyy');
    final formattedEarliest = DateFormat('dd MMM').format(earliest);
    final formattedLatest = DateFormat('dd MMM yyyy').format(latest);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Incident Date',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ' *',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                'Window: $formattedEarliest - $formattedLatest',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space8),
        Semantics(
          button: true,
          label:
              'Select incident date. Selected date is ${selectedDate != null ? dateFormat.format(selectedDate!) : "not set"}.',
          child: InkWell(
            onTap: () => _pickDate(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            child: Container(
              height: AppSpacing.minTouchTarget,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                border: Border.all(
                  color: errorText != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
                  width: errorText != null ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.space12),
                  Expanded(
                    child: Text(
                      selectedDate != null
                          ? AppDateTimeUtils.formatIncidentDate(selectedDate!)
                          : 'Select when the grievance occurred',
                      style: TextStyle(
                        fontSize: 14,
                        color: selectedDate != null
                            ? theme.colorScheme.onSurface
                            : theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.6),
                        fontWeight: selectedDate != null
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: TextStyle(
              color: theme.colorScheme.error,
              fontSize: 12,
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 13,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Grievances must be submitted within 7 calendar days of the incident.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
