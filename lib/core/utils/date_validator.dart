import 'package:smartify/core/constants/app_constants.dart';

/// SMARTIFY Date Validation Utility
/// Enforces the mandatory 7-calendar-day retrospective rule [Today - 7 days, Today].
class DateValidator {
  DateValidator._();

  /// Converts any DateTime into a date-only DateTime (midnight UTC/local)
  static DateTime stripTime(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Calculates the earliest permitted incident date [Today - 7 days]
  static DateTime getEarliestPermittedDate({DateTime? referenceDate}) {
    final now = stripTime(referenceDate ?? DateTime.now());
    return now
        .subtract(const Duration(days: AppConstants.kMaxRetrospectiveDays));
  }

  /// Calculates the latest permitted incident date [Today]
  static DateTime getLatestPermittedDate({DateTime? referenceDate}) {
    return stripTime(referenceDate ?? DateTime.now());
  }

  /// Validates whether [selectedDate] falls within [Today - 7 days, Today] inclusive.
  /// Returns null if valid, or a descriptive error message if invalid.
  static String? validateIncidentDate(DateTime? selectedDate,
      {DateTime? referenceDate}) {
    if (selectedDate == null) {
      return 'Please select the date when the incident occurred.';
    }

    final date = stripTime(selectedDate);
    final today = getLatestPermittedDate(referenceDate: referenceDate);
    final earliest = getEarliestPermittedDate(referenceDate: referenceDate);

    if (date.isAfter(today)) {
      return 'Future dates are not allowed. You cannot select a date after today.';
    }

    if (date.isBefore(earliest)) {
      return 'Grievance date cannot be older than 7 calendar days as per campus policy.';
    }

    return null;
  }

  /// Quick boolean check for boundary validation
  static bool isValidIncidentDate(DateTime date, {DateTime? referenceDate}) {
    return validateIncidentDate(date, referenceDate: referenceDate) == null;
  }
}
