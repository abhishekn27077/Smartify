import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';

void main() {
  group('SMARTIFY Timezone & Timestamp Conversion Audit', () {
    test('UTC ISO string with +00:00 parses as UTC and converts to local', () {
      const utcString = '2026-10-20T14:28:03.443689+00:00';
      final dt = AppDateTimeUtils.parseBackendTimestamp(utcString);
      
      expect(dt.isUtc, isTrue);
      expect(dt.hour, equals(14));
      expect(dt.minute, equals(28));

      final local = dt.toLocal();
      // Local offset on tester machine
      final expectedHour = (14 + local.timeZoneOffset.inHours + ((28 + local.timeZoneOffset.inMinutes % 60) >= 60 ? 1 : 0)) % 24;
      expect(local.hour, equals(expectedHour));

      final formatted = AppDateTimeUtils.formatLocalDateTime(dt);
      expect(formatted, isNotEmpty);
      expect(formatted, contains('2026'));
    });

    test('UTC ISO string with Z suffix parses as UTC and converts to local', () {
      const utcString = '2026-10-20T14:28:03.443689Z';
      final dt = AppDateTimeUtils.parseBackendTimestamp(utcString);
      
      expect(dt.isUtc, isTrue);
      expect(dt.hour, equals(14));
    });

    test('Missing timezone suffix assumes UTC and correctly offsets to local', () {
      // Postgres sometimes outputs '2026-10-20 14:28:03.443689' without Z
      const rawString = '2026-10-20 14:28:03.443689';
      final dt = AppDateTimeUtils.parseBackendTimestamp(rawString);

      expect(dt.isUtc, isTrue);
      expect(dt.hour, equals(14));
      expect(dt.minute, equals(28));
    });

    test('Calendar date strings like 2026-10-18 do not drift', () {
      const dateString = '2026-10-18';
      final dt = AppDateTimeUtils.parseIncidentDate(dateString);

      expect(dt.year, equals(2026));
      expect(dt.month, equals(10));
      expect(dt.day, equals(18));
      expect(AppDateTimeUtils.formatIncidentDate(dt), contains('18 Oct 2026'));
    });

    test('SLA remaining calculations use monotonic absolute UTC timestamps', () {
      final nowUtc = DateTime.now().toUtc();
      final deadlineInFuture = nowUtc.add(const Duration(days: 3, hours: 23));
      final futureDuration = AppDateTimeUtils.calculateRemainingSla(deadlineInFuture);
      expect(AppDateTimeUtils.formatSlaRemaining(futureDuration), contains('3d'));

      final deadlineInPast = nowUtc.subtract(const Duration(hours: 5));
      final pastDuration = AppDateTimeUtils.calculateRemainingSla(deadlineInPast);
      expect(pastDuration.isNegative, isTrue);
      expect(AppDateTimeUtils.formatSlaRemaining(pastDuration), contains('5 hours overdue'));
      expect(
        AppDateTimeUtils.getSlaStatusLabel(
          isCutoffPaused: false,
          isSlaBreached: true,
          timeRemaining: pastDuration,
        ),
        'ACTION OVERDUE',
      );
    });
  });
}
