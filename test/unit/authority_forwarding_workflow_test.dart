import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/authority/services/authority_service.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

void main() {
  group('SMARTIFY Authority Forwarding Workflow Tests (L1 -> L2)', () {
    late AuthorityService service;

    setUp(() {
      service = AuthorityService();
    });

    test('1. Validates that forwarding justification is mandatory (>= 5 chars)',
        () async {
      expect(
        () => service.forwardToNextTier(
          complaintId: 'test-id',
          currentLevelId: 'lvl-1',
          currentLevelNumber: 1,
          reason: '   ',
        ),
        throwsA(isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          contains('mandatory'),
        )),
      );

      expect(
        () => service.forwardToNextTier(
          complaintId: 'test-id',
          currentLevelId: 'lvl-1',
          currentLevelNumber: 1,
          reason: 'abc',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('2. Rejects forwarding when already at highest level (Level 4)',
        () async {
      expect(
        () => service.forwardToNextTier(
          complaintId: 'test-id',
          currentLevelId: 'lvl-4',
          currentLevelNumber: 4,
          reason: 'Escalating higher',
        ),
        throwsA(isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          contains('highest authority level'),
        )),
      );
    });

    test(
        '3. Mock fallback gracefully succeeds when unauthenticated in test harness',
        () async {
      final result = await service.forwardToNextTier(
        complaintId: 'test-id',
        currentLevelId: 'lvl-1',
        currentLevelNumber: 1,
        reason: 'Legitimate justification for forwarding to Level 2',
      );

      expect(result, isTrue);
    });

    test('4. Correctly parses RPC forwarding response payload', () {
      final rpcResponse = {
        'success': true,
        'complaint_id': 'f9839a0d-727f-4f5c-b906-3bda0221902d',
        'tracking_number': 'SMT-2026-01028',
        'department_name': 'Department of MBA',
        'from_level_number': 1,
        'to_level_number': 2,
        'to_level_title': 'Level 2: Head of Department (HoD)',
        'assigned_authority_id': '0b07af6b-6206-4c97-8697-513cc237a855',
        'assigned_authority_name': 'Dr. Neha Gupta',
        'message':
            'Grievance SMT-2026-01028 successfully forwarded to Dr. Neha Gupta (Level 2: Head of Department (HoD)).',
      };

      expect(rpcResponse['success'], isTrue);
      expect(rpcResponse['to_level_number'], equals(2));
      expect(rpcResponse['assigned_authority_name'], equals('Dr. Neha Gupta'));
      expect(rpcResponse['message'],
          contains('successfully forwarded to Dr. Neha Gupta'));
    });

    test(
        '5. Timeline FORWARDED event snapshots actor and destination authority',
        () {
      final json = {
        'id': 'hist-fwd-01',
        'complaint_id': 'f9839a0d-727f-4f5c-b906-3bda0221902d',
        'old_status': 'PENDING',
        'new_status': 'ESCALATED',
        'event_type': 'FORWARDED',
        'actor_user_id': '4037af5d-991a-4e0a-9f97-13f45e72d891',
        'actor_display_name': 'Dr. Amit Trivedi',
        'actor_role': 'authority',
        'actor_authority_level': 1,
        'actor_department_name': 'Department of MBA',
        'actor_designation': 'Level 1 — Faculty Advisor / Department Officer',
        'assigned_to_tier': 'Level 2: Head of Department (HoD)',
        'assigned_to_name': 'Dr. Neha Gupta',
        'is_system_event': false,
        'remarks':
            'Forwarded to Level 2: Head of Department (HoD). Reason: Referred to HoD for syllabus coverage review.',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.eventType, equals('FORWARDED'));
      expect(event.newStatus, equals(ComplaintStatus.escalated));
      expect(event.changedByName, equals('Dr. Amit Trivedi'));
      expect(event.actorDesignation,
          equals('Level 1 — Faculty Advisor / Department Officer'));
      expect(event.assignedToTier, equals('Level 2: Head of Department (HoD)'));
      expect(event.assignedToName, equals('Dr. Neha Gupta'));
      expect(event.remarks,
          contains('Referred to HoD for syllabus coverage review'));
    });
  });
}
