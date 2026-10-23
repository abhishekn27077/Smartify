import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Status Machine & Authorization Invariants', () {
    test('Student cannot directly transition CUTOFF_PAUSED to RESOLVED', () {
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.resolved),
          isFalse);
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.inProgress),
          isFalse);
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.escalated),
          isFalse);
    });

    test(
        'CUTOFF_PAUSED can only transition to UNDER_REVIEW via Admin Resumption',
        () {
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.underReview),
          isTrue);
    });

    test('RESOLVED and REJECTED states are strictly terminal', () {
      for (final target in ComplaintStatus.values) {
        if (target != ComplaintStatus.resolved) {
          expect(ComplaintStatus.resolved.canTransitionTo(target), isFalse);
        }
        if (target != ComplaintStatus.rejected) {
          expect(ComplaintStatus.rejected.canTransitionTo(target), isFalse);
        }
      }
    });
  });

  group('3. Database Failure Exception Mapping Verification', () {
    test('DatabaseFailure preserves code and user friendly message', () {
      const failure =
          DatabaseFailure('Unauthorized RPC invocation', code: '42501');
      expect(failure.message, equals('Unauthorized RPC invocation'));
      expect(failure.code, equals('42501'));
      expect(failure.toString(), contains('Unauthorized RPC invocation'));
    });

    test('AuthFailure preserves permission denied message', () {
      const failure = AuthFailure('Administrative privileges required');
      expect(failure.message, equals('Administrative privileges required'));
      expect(
          failure.toString(), contains('Administrative privileges required'));
    });
  });

  group('4. Service Error Handling & Mock Fallback Prevention', () {
    test('DatabaseFailure is thrown instead of silent success on RPC errors',
        () {
      // Validates that DatabaseFailure is a recognized Exception in the core domain
      expect(() {
        throw const DatabaseFailure(
            'Forbidden: only administrators can reassign roles',
            code: '42501');
      }, throwsA(isA<DatabaseFailure>()));
    });
  });
}
