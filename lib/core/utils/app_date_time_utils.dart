import 'package:intl/intl.dart';

/// SMARTIFY Centralized Timezone-Aware DateTime & Formatting Utility
///
/// Principles:
/// 1. Backend timestamps are stored in UTC (Postgres timestamptz).
/// 2. Parsing ensures UTC awareness.
/// 3. Display formatting converts to the user device's local timezone (.toLocal()) exactly once.
/// 4. Incident dates (calendar dates) are handled without timezone drift.
/// 5. SLA calculations use monotonic duration differences.
class AppDateTimeUtils {
  AppDateTimeUtils._();

  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _longDateTimeFormat =
      DateFormat('EEE, dd MMM yyyy, hh:mm a');
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _incidentDateFormat = DateFormat('EEE, dd MMM yyyy');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');
  static final DateFormat _auditFormat = DateFormat('dd MMM yyyy, hh:mm:ss a');

  /// Parses a backend timestamp string into a UTC DateTime.
  /// Handles ISO-8601 strings, ensuring timezone awareness.
  static DateTime parseBackendTimestamp(dynamic value) {
    if (value == null) return DateTime.now().toUtc();
    if (value is DateTime) {
      return value.isUtc ? value : value.toUtc();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return DateTime.now().toUtc();

      // If it's a date-only string like '2026-10-18', parse as date
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
        return DateTime.parse(trimmed);
      }

      // If missing timezone indicator, append Z to treat as UTC
      if (!trimmed.endsWith('Z') &&
          !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(trimmed)) {
        return DateTime.parse('${trimmed}Z').toUtc();
      }
      return DateTime.parse(trimmed).toUtc();
    }
    return DateTime.now().toUtc();
  }

  /// Parses an incident date (which is a calendar date, e.g., 2026-10-18).
  static DateTime parseIncidentDate(dynamic value) {
    if (value == null) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    if (value is String) {
      final parsed = DateTime.parse(value.trim());
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Formats a UTC or local DateTime to local date & time: '20 Oct 2026, 08:28 PM'
  static String formatLocalDateTime(DateTime? dt,
      {bool includeDayOfWeek = false}) {
    if (dt == null) return 'N/A';
    final local = dt.toLocal();
    return includeDayOfWeek
        ? _longDateTimeFormat.format(local)
        : _dateTimeFormat.format(local);
  }

  /// Formats date only in user's local timezone: '20 Oct 2026'
  static String formatLocalDate(DateTime? dt) {
    if (dt == null) return 'N/A';
    return _dateFormat.format(dt.toLocal());
  }

  /// Formats incident date (calendar day): 'Tue, 18 Oct 2026'
  static String formatIncidentDate(DateTime? dt) {
    if (dt == null) return 'N/A';
    return _incidentDateFormat.format(dt);
  }

  /// Formats time only in user's local timezone: '08:28 PM'
  static String formatLocalTime(DateTime? dt) {
    if (dt == null) return 'N/A';
    return _timeFormat.format(dt.toLocal());
  }

  /// Formats high-precision audit timestamp: '20 Oct 2026, 08:28:15 PM'
  static String formatAuditTimestamp(DateTime? dt) {
    if (dt == null) return 'N/A';
    return _auditFormat.format(dt.toLocal());
  }

  /// Calculates remaining SLA duration against current UTC instant
  static Duration calculateRemainingSla(DateTime deadline) {
    final nowUtc = DateTime.now().toUtc();
    final deadlineUtc = deadline.toUtc();
    return deadlineUtc.difference(nowUtc);
  }

  /// Human-readable relative or countdown time for SLA
  static String formatSlaRemaining(Duration duration) {
    if (duration.isNegative) {
      final totalHours = duration.inHours.abs();
      final days = duration.inDays.abs();
      final hours = totalHours % 24;
      if (days == 0 && hours == 0) return 'Action overdue';
      if (days == 0) return '$totalHours hours overdue';
      return '${days}d ${hours}h overdue';
    }
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h remaining';
    }
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m remaining';
    }
    return '${duration.inMinutes}m remaining';
  }

  /// Formats average resolution time, displaying '—' if no resolved cases exist
  static String formatAverageResolution(int totalResolved, double averageDays) {
    if (totalResolved <= 0) return '—';
    if (averageDays <= 0.0) return '0.0 days';
    if (averageDays < 0.1) {
      final hours = (averageDays * 24).round();
      if (hours <= 1) return '< 1 hour';
      return '$hours hours';
    }
    return '${averageDays.toStringAsFixed(1)} days';
  }

  /// Compact version of average resolution for small metric cards
  static String formatAverageResolutionCompact(int totalResolved, double averageDays) {
    if (totalResolved <= 0) return '—';
    if (averageDays <= 0.0) return '0.0d';
    if (averageDays < 0.1) {
      final hours = (averageDays * 24).round();
      if (hours <= 1) return '<1h';
      return '${hours}h';
    }
    return '${averageDays.toStringAsFixed(1)}d';
  }

  /// Authority-facing SLA badge headline: ACTION OVERDUE, SLA ACTIVE, DUE SOON, GOVERNANCE CUTOFF
  static String getSlaStatusLabel({
    required bool isCutoffPaused,
    required bool isSlaBreached,
    required Duration timeRemaining,
  }) {
    if (isCutoffPaused) return 'GOVERNANCE CUTOFF';
    if (isSlaBreached) return 'ACTION OVERDUE';
    if (timeRemaining.inHours < 24) return 'DUE SOON';
    return 'SLA ACTIVE';
  }

  /// Authority-facing SLA explanation
  static String getSlaExplanation({
    required bool isCutoffPaused,
    required bool isSlaBreached,
    required Duration timeRemaining,
    required int currentLevelNumber,
  }) {
    if (isCutoffPaused) {
      return 'Automated progression is paused because this grievance reached its 20-day governance limit. Administrative review is required before progression can resume.';
    }
    if (isSlaBreached) {
      return 'This case exceeded the Level $currentLevelNumber action deadline and requires attention.';
    }
    if (timeRemaining.inHours < 24) {
      return 'Please take action before the SLA expires.';
    }
    return 'Time remaining for Level $currentLevelNumber to act.';
  }
}
