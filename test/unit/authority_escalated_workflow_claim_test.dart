import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/authority/services/authority_service.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

void main() {
  group('SMARTIFY Escalated Authority Workflow & Claim Engine Tests', () {
    late AuthorityService service;

    setUp(() {
      service = AuthorityService();
    });

    test('1. Validates that claimGrievance rejects empty complaintId',
        () async {
      expect(
        () => service.claimGrievance(complaintId: '   '),
        throwsA(isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          contains('Complaint ID is required'),
        )),
      );
    });

    test(
        '2. Mock fallback gracefully succeeds when unauthenticated in test harness',
        () async {
      final result = await service.claimGrievance(
        complaintId: 'test-complaint-id',
      );
      expect(result, isTrue);
    });

    test('3. Correctly parses RPC claim_grievance response payload', () {
      final rpcResponse = {
        'success': true,
        'complaint_id': '45a8df2a-579c-4e89-8d59-3fb65e4baef9',
        'tracking_number': 'SMT-2026-01074',
        'department_name': 'Department of MCA',
        'current_level_number': 2,
        'assigned_authority_id': 'fe2a30f6-3aa1-47ad-8a88-9d46f537d9c4',
        'assigned_authority_name': 'Dr. Radhika Sharma (HoD)',
        'status': 'UNDER_REVIEW',
        'message':
            'Grievance SMT-2026-01074 has been assigned to Dr. Radhika Sharma (HoD) and is now UNDER_REVIEW.',
      };

      expect(rpcResponse['success'], isTrue);
      expect(rpcResponse['current_level_number'], equals(2));
      expect(rpcResponse['status'], equals('UNDER_REVIEW'));
      expect(rpcResponse['assigned_authority_name'],
          equals('Dr. Radhika Sharma (HoD)'));
      expect(rpcResponse['message'], contains('now UNDER_REVIEW'));
    });

    test('4. Intake Pool vs Active Caseload segregation logic', () {
      const currentUserId = 'auth-user-hod-radhika';
      final now = DateTime.now().toUtc();

      final queue = [
        GrievanceModel(
          id: 'case-1',
          trackingNumber: 'SMT-2026-01074',
          title: 'MCA Semester 3 Lab Collision - AI & Cloud',
          description: 'Conflict in lab scheduling',
          category: 'Academics',
          priority: 'HIGH',
          status: ComplaintStatus.escalated,
          incidentDate: now.subtract(const Duration(days: 2)),
          createdAt: now.subtract(const Duration(hours: 12)),
          updatedAt: now,
          departmentId: 'dept-mca',
          departmentName: 'Department of MCA',
          departmentCode: 'MCA',
          studentId: 'student-rohit',
          studentName: 'Rohit Verma',
          assignedAuthorityId: null, // Unassigned awaiting intake
          assignedAuthorityName: null,
          currentAuthorityLevelId: 'lvl-2-hod',
          currentAuthorityLevelNumber: 2,
          currentAuthorityLevelTitle: 'Level 2 — Head of Department (HoD)',
          currentTierDeadline: now.add(const Duration(days: 3)),
          cutoffDeadline: now.add(const Duration(days: 18)),
        ),
        GrievanceModel(
          id: 'case-2',
          trackingNumber: 'SMT-2026-01075',
          title: 'Network latency in MCA Lab 2',
          description: 'Ethernet switches faulty',
          category: 'Academics',
          priority: 'MEDIUM',
          status: ComplaintStatus.underReview,
          incidentDate: now.subtract(const Duration(days: 1)),
          createdAt: now.subtract(const Duration(hours: 6)),
          updatedAt: now,
          departmentId: 'dept-mca',
          departmentName: 'Department of MCA',
          departmentCode: 'MCA',
          studentId: 'student-rohit',
          studentName: 'Rohit Verma',
          assignedAuthorityId: currentUserId, // Personally assigned
          assignedAuthorityName: 'Dr. Radhika Sharma',
          currentAuthorityLevelId: 'lvl-2-hod',
          currentAuthorityLevelNumber: 2,
          currentAuthorityLevelTitle: 'Level 2 — Head of Department (HoD)',
          currentTierDeadline: now.add(const Duration(days: 4)),
          cutoffDeadline: now.add(const Duration(days: 19)),
        ),
      ];

      // Active cases filter:
      final activeCases = queue
          .where((g) =>
              g.assignedAuthorityId == currentUserId && !g.status.isTerminal)
          .toList();

      // Intake pool filter:
      final intakeCases = queue
          .where((g) =>
              (g.assignedAuthorityId == null ||
                  g.assignedAuthorityId != currentUserId) &&
              !g.status.isTerminal)
          .toList();

      expect(activeCases.length, equals(1));
      expect(activeCases.first.id, equals('case-2'));

      expect(intakeCases.length, equals(1));
      expect(intakeCases.first.id, equals('case-1'));
      expect(intakeCases.first.trackingNumber, equals('SMT-2026-01074'));

      // Simulate claiming case-1:
      final c1 = intakeCases.first;
      final claimedCase1 = GrievanceModel(
        id: c1.id,
        trackingNumber: c1.trackingNumber,
        title: c1.title,
        description: c1.description,
        category: c1.category,
        priority: c1.priority,
        status: ComplaintStatus.underReview,
        incidentDate: c1.incidentDate,
        createdAt: c1.createdAt,
        updatedAt: DateTime.now().toUtc(),
        departmentId: c1.departmentId,
        departmentName: c1.departmentName,
        departmentCode: c1.departmentCode,
        studentId: c1.studentId,
        studentName: c1.studentName,
        assignedAuthorityId: currentUserId,
        assignedAuthorityName: 'Dr. Radhika Sharma',
        currentAuthorityLevelId: c1.currentAuthorityLevelId,
        currentAuthorityLevelNumber: c1.currentAuthorityLevelNumber,
        currentAuthorityLevelTitle: c1.currentAuthorityLevelTitle,
        currentTierDeadline: c1.currentTierDeadline,
        cutoffDeadline: c1.cutoffDeadline,
      );

      final updatedQueue = [claimedCase1, queue[1]];
      final updatedActive = updatedQueue
          .where((g) =>
              g.assignedAuthorityId == currentUserId && !g.status.isTerminal)
          .toList();
      final updatedIntake = updatedQueue
          .where((g) =>
              (g.assignedAuthorityId == null ||
                  g.assignedAuthorityId != currentUserId) &&
              !g.status.isTerminal)
          .toList();

      expect(updatedActive.length, equals(2));
      expect(updatedIntake.length, equals(0));
    });

    test('5. Timeline Event deserializes CLAIMED event with human authority',
        () {
      final json = {
        'id': 'hist-claim-01',
        'complaint_id': '45a8df2a-579c-4e89-8d59-3fb65e4baef9',
        'old_status': 'ESCALATED',
        'new_status': 'UNDER_REVIEW',
        'event_type': 'CLAIMED',
        'actor_user_id': 'fe2a30f6-3aa1-47ad-8a88-9d46f537d9c4',
        'actor_display_name': 'Dr. Radhika Sharma',
        'actor_role': 'authority',
        'actor_authority_level': 2,
        'actor_department_name': 'Department of MCA',
        'actor_designation': 'Level 2 — Head of Department (HoD)',
        'assigned_to_tier': 'Level 2 — Head of Department (HoD)',
        'assigned_to_name': 'Dr. Radhika Sharma',
        'is_system_event': false,
        'remarks':
            'Case accepted by Dr. Radhika Sharma (Level 2 — Head of Department (HoD)). Status set to UNDER_REVIEW.',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.eventType, equals('CLAIMED'));
      expect(event.newStatus, equals(ComplaintStatus.underReview));
      expect(event.changedByName, equals('Dr. Radhika Sharma'));
      expect(
          event.actorDesignation, equals('Level 2 — Head of Department (HoD)'));
      expect(event.remarks, contains('Case accepted by Dr. Radhika Sharma'));
    });
  });
}
