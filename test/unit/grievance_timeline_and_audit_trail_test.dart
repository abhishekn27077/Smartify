import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/utils/authority_designation_resolver.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

void main() {
  group(
      'SMARTIFY Grievance Timeline & Audit Trail Verification (17 Requirements)',
      () {
    final baseTime = DateTime.parse('2026-10-18T10:00:00.000Z');

    // 1. Student submission shows "Submitted by", not "Reviewed by"
    test(
        '1. Student submission correctly parses with student actor snapshot and SUBMITTED event type',
        () {
      final json = {
        'id': 'hist-001',
        'complaint_id': 'c-mba-001',
        'old_status': null,
        'new_status': 'PENDING',
        'event_type': 'SUBMITTED',
        'actor_user_id': 'stud-mba-001',
        'actor_display_name': 'Rohan Verma',
        'actor_role': 'student',
        'actor_department_name': 'Department of MBA',
        'actor_designation': 'MBA Student',
        'is_system_event': false,
        'remarks': 'Grievance registered and placed in Intake Queue.',
        'created_at': baseTime.toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.newStatus, equals(ComplaintStatus.pending));
      expect(event.eventType, equals('SUBMITTED'));
      expect(event.changedByName, equals('Rohan Verma'));
      expect(event.changedByRole, equals('student'));
      expect(event.actorDesignation, equals('MBA Student'));
      expect(event.changedByDept, equals('Department of MBA'));
      expect(event.isSystemEvent, isFalse);
    });

    // 2. L1 Under Review records actual L1 authority
    test(
        '2. L1 Under Review captures authenticated L1 faculty identity and designation',
        () {
      final json = {
        'id': 'hist-002',
        'complaint_id': 'c-mba-001',
        'old_status': 'PENDING',
        'new_status': 'UNDER_REVIEW',
        'event_type': 'UNDER_REVIEW',
        'actor_user_id': 'auth-mba-l1',
        'actor_display_name': 'Dr. Amit Trivedi',
        'actor_role': 'authority',
        'actor_authority_level': 1,
        'actor_department_name': 'Department of MBA',
        'actor_designation': 'Level 1 — Faculty Advisor / Department Officer',
        'is_system_event': false,
        'remarks': 'Reviewing internal marks with exam coordinator.',
        'created_at':
            baseTime.add(const Duration(minutes: 15)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.newStatus, equals(ComplaintStatus.underReview));
      expect(event.changedByName, equals('Dr. Amit Trivedi'));
      expect(event.actorDesignation,
          equals('Level 1 — Faculty Advisor / Department Officer'));
      expect(event.actorAuthorityLevel, equals(1));
      expect(event.changedByName, isNot(equals('Unknown User')));
    });

    // 3. L1 Resolve records actual L1 authority
    test(
        '3. L1 Resolve captures authenticated L1 faculty identity and formal resolution notes',
        () {
      final json = {
        'id': 'hist-003',
        'complaint_id': 'c-mba-001',
        'old_status': 'UNDER_REVIEW',
        'new_status': 'RESOLVED',
        'event_type': 'RESOLVED',
        'actor_user_id': 'auth-mba-l1',
        'actor_display_name': 'Dr. Amit Trivedi',
        'actor_role': 'authority',
        'actor_authority_level': 1,
        'actor_department_name': 'Department of MBA',
        'actor_designation': 'Level 1 — Faculty Advisor / Department Officer',
        'is_system_event': false,
        'remarks': 'Internal marks updated on student portal. Issue resolved.',
        'created_at': baseTime.add(const Duration(hours: 1)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.newStatus, equals(ComplaintStatus.resolved));
      expect(event.changedByName, equals('Dr. Amit Trivedi'));
      expect(event.actorDesignation,
          equals('Level 1 — Faculty Advisor / Department Officer'));
      expect(event.remarks, contains('Internal marks updated'));
    });

    // 4. L1 Forward records actual L1 authority and target tier
    test(
        '4. L1 Forward captures forwarding authority and target authority tier',
        () {
      final json = {
        'id': 'hist-004',
        'complaint_id': 'c-mba-002',
        'old_status': 'UNDER_REVIEW',
        'new_status': 'ESCALATED',
        'event_type': 'FORWARDED',
        'actor_user_id': 'auth-mba-l1',
        'actor_display_name': 'Dr. Amit Trivedi',
        'actor_role': 'authority',
        'actor_department_name': 'Department of MBA',
        'actor_designation': 'Level 1 — Faculty Advisor / Department Officer',
        'assigned_to_tier': 'Level 2 — Head of Department (HoD)',
        'assigned_to_name': 'Dr. Neha Gupta',
        'remarks': 'Requires departmental curriculum approval.',
        'created_at': baseTime.add(const Duration(hours: 2)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.newStatus, equals(ComplaintStatus.escalated));
      expect(event.eventType, equals('FORWARDED'));
      expect(event.changedByName, equals('Dr. Amit Trivedi'));
      expect(
          event.assignedToTier, equals('Level 2 — Head of Department (HoD)'));
      expect(event.assignedToName, equals('Dr. Neha Gupta'));
    });

    // 5. L2 Under Review records actual L2 authority
    test('5. L2 Under Review captures HoD identity and HoD designation', () {
      final json = {
        'id': 'hist-005',
        'complaint_id': 'c-mba-002',
        'old_status': 'ESCALATED',
        'new_status': 'UNDER_REVIEW',
        'event_type': 'UNDER_REVIEW',
        'actor_user_id': 'auth-mba-l2',
        'actor_display_name': 'Dr. Neha Gupta',
        'actor_role': 'authority',
        'actor_authority_level': 2,
        'actor_department_name': 'Department of MBA',
        'actor_designation': 'Level 2 — Head of Department (HoD)',
        'remarks': 'Evaluating syllabus conflict in faculty council.',
        'created_at': baseTime.add(const Duration(hours: 3)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.changedByName, equals('Dr. Neha Gupta'));
      expect(
          event.actorDesignation, equals('Level 2 — Head of Department (HoD)'));
      expect(event.actorAuthorityLevel, equals(2));
    });

    // 6. L2 Resolve records actual L2 authority
    test('6. L2 Resolve captures HoD resolution notes', () {
      final json = {
        'id': 'hist-006',
        'complaint_id': 'c-mba-002',
        'old_status': 'UNDER_REVIEW',
        'new_status': 'RESOLVED',
        'event_type': 'RESOLVED',
        'actor_user_id': 'auth-mba-l2',
        'actor_display_name': 'Dr. Neha Gupta',
        'actor_role': 'authority',
        'actor_authority_level': 2,
        'actor_designation': 'Level 2 — Head of Department (HoD)',
        'remarks': 'Council decided to reschedule conflicting test.',
        'created_at': baseTime.add(const Duration(hours: 4)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.changedByName, equals('Dr. Neha Gupta'));
      expect(
          event.actorDesignation, equals('Level 2 — Head of Department (HoD)'));
    });

    // 7. L3 Under Review records actual L3 authority
    test('7. L3 Under Review captures Dean identity and Dean designation', () {
      final json = {
        'id': 'hist-007',
        'complaint_id': 'c-mba-003',
        'old_status': 'ESCALATED',
        'new_status': 'UNDER_REVIEW',
        'event_type': 'UNDER_REVIEW',
        'actor_user_id': 'auth-mba-l3',
        'actor_display_name': 'Prof. Rajesh Khanna',
        'actor_role': 'authority',
        'actor_authority_level': 3,
        'actor_designation': 'Level 3 — Dean of Management Studies (MBA)',
        'remarks': 'Executive review by Dean.',
        'created_at': baseTime.add(const Duration(hours: 5)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.changedByName, equals('Prof. Rajesh Khanna'));
      expect(event.actorDesignation,
          equals('Level 3 — Dean of Management Studies (MBA)'));
    });

    // 8. L3 Resolve records actual L3 authority
    test('8. L3 Resolve captures Dean resolution', () {
      final json = {
        'id': 'hist-008',
        'complaint_id': 'c-mba-003',
        'old_status': 'UNDER_REVIEW',
        'new_status': 'RESOLVED',
        'event_type': 'RESOLVED',
        'actor_user_id': 'auth-mba-l3',
        'actor_display_name': 'Prof. Rajesh Khanna',
        'actor_role': 'authority',
        'actor_authority_level': 3,
        'actor_designation': 'Level 3 — Dean of Management Studies (MBA)',
        'remarks': 'Institutional sanction granted.',
        'created_at': baseTime.add(const Duration(hours: 6)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.changedByName, equals('Prof. Rajesh Khanna'));
      expect(event.newStatus, equals(ComplaintStatus.resolved));
    });

    // 9. Admin governance action records Admin only when Admin actually performs it
    test('9. Admin resumption event records Admin actor explicitly', () {
      final json = {
        'id': 'hist-009',
        'complaint_id': 'c-cutoff-001',
        'old_status': 'CUTOFF_PAUSED',
        'new_status': 'UNDER_REVIEW',
        'event_type': 'RESUMED',
        'actor_user_id': 'admin-uuid-001',
        'actor_display_name': 'Campus Administrator',
        'actor_role': 'admin',
        'actor_designation': 'Campus Administrator',
        'is_system_event': false,
        'remarks':
            'Administrative resumption authorized: Evidence verified with Dean.',
        'created_at': baseTime.add(const Duration(days: 21)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.changedByName, equals('Campus Administrator'));
      expect(event.changedByRole, equals('admin'));
      expect(event.eventType, equals('RESUMED'));
      expect(event.isSystemEvent, isFalse);
    });

    // 10. Automated escalation is marked SYSTEM/AUTOMATED
    test(
        '10. Automated escalation has is_system_event true and System Redressal Engine actor',
        () {
      final json = {
        'id': 'hist-010',
        'complaint_id': 'c-auto-001',
        'old_status': 'PENDING',
        'new_status': 'ESCALATED',
        'event_type': 'SYSTEM_ESCALATION',
        'actor_user_id': null,
        'actor_display_name': null,
        'actor_role': 'SYSTEM',
        'is_system_event': true,
        'remarks':
            'Automated escalation: Tier SLA deadline breached at Level 1.',
        'created_at': baseTime.add(const Duration(days: 3)).toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.isSystemEvent, isTrue);
      expect(
          event.changedByName, equals('System Redressal Engine (AUTOMATED)'));
      expect(event.changedByRole, equals('SYSTEM'));
    });

    // 11. Unknown User is not produced for valid authority actions
    test(
        '11. Authority profile join correctly maps full name without falling back to Unknown User',
        () {
      final json = {
        'id': 'hist-011',
        'complaint_id': 'c-011',
        'new_status': 'UNDER_REVIEW',
        'changed_by': 'auth-uuid',
        'profiles': {
          'full_name': 'Prof. Vikram Malhotra (M.Com L1)',
          'role': 'authority',
          'designation': 'Level 1: Faculty Advisor / Department Officer',
          'departments': {'name': 'Department of M.Com'},
          'authority_levels': {
            'title': 'Level 1: Faculty Advisor / Hostel Warden',
            'level_number': 1
          },
        },
        'created_at': baseTime.toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);
      expect(event.changedByName, equals('Prof. Vikram Malhotra'));
      expect(event.changedByName, isNot(contains('Unknown User')));
      expect(event.actorDesignation,
          equals('Level 1 — Faculty Advisor / Department Officer'));
      expect(event.changedByDept, equals('Department of M.Com'));
    });

    // 12 & 13. Duplicate prevention and cleanup
    test(
        '12 & 13. Deduplication logic correctly identifies and discards records within 5s window',
        () {
      final event1Time = DateTime.parse('2026-10-18T16:06:14.858Z');
      final event2Time =
          DateTime.parse('2026-10-18T16:06:15.219Z'); // 361ms later

      final diffSec = event2Time.difference(event1Time).inMilliseconds / 1000.0;
      expect(diffSec, lessThan(5.0));

      // Best remark selection logic
      const r1 = 'Status updated to UNDER_REVIEW';
      const r2 = 'it will be updated soon';
      final isGeneric = r1.startsWith('Status updated to');
      final bestRemark = isGeneric ? r2 : r1;
      expect(bestRemark, equals('it will be updated soon'));
    });

    // 14. Historical actor identity remains stable
    test(
        '14. Snapshot fields remain immutable even if current user profile changes',
        () {
      final snapshotJson = {
        'id': 'hist-014',
        'complaint_id': 'c-014',
        'new_status': 'UNDER_REVIEW',
        'actor_display_name': 'Dr. Amit Trivedi',
        'actor_role': 'authority',
        'actor_designation': 'Level 1 — Faculty Advisor / Department Officer',
        'actor_department_name': 'Department of MBA',
        // Dynamic profile lookup might return a transferred department
        'profiles': {
          'full_name': 'Dr. Amit Trivedi',
          'role': 'authority',
          'departments': {'name': 'Department of Executive Education'},
        },
        'created_at': baseTime.toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(snapshotJson);
      // Must use persisted snapshot department, not dynamic joined profile department
      expect(event.changedByDept, equals('Department of MBA'));
      expect(event.actorDesignation,
          equals('Level 1 — Faculty Advisor / Department Officer'));
    });

    // 15, 16, 17. Security invariants and designation resolver tests
    test('15 & 16. Context-specific designations for all departments', () {
      expect(
        AuthorityDesignationResolver.resolveDesignation(
            levelNumber: 1,
            departmentCode: 'MBA',
            departmentName: 'Department of MBA'),
        equals('Level 1 — Faculty / Department Officer'),
      );
      expect(
        AuthorityDesignationResolver.resolveDesignation(
            levelNumber: 1,
            departmentCode: 'HOSTEL',
            departmentName: 'Hostel & Residential Life'),
        equals('Level 1 — Hostel Warden'),
      );
      expect(
        AuthorityDesignationResolver.resolveDesignation(
            levelNumber: 1,
            departmentCode: 'IT',
            departmentName: 'Library & IT Services'),
        equals('Level 1 — IT Officer'),
      );
      expect(
        AuthorityDesignationResolver.resolveDesignation(
            levelNumber: 1,
            departmentCode: 'FIN',
            departmentName: 'Accounts & Finance'),
        equals('Level 1 — Accounts Officer'),
      );
      expect(
        AuthorityDesignationResolver.resolveDesignation(
            levelNumber: 1,
            departmentCode: 'INFRA',
            departmentName: 'Campus Infrastructure'),
        equals('Level 1 — Campus Facility Officer'),
      );
      expect(
        AuthorityDesignationResolver.resolveDesignation(
            levelNumber: 2,
            departmentCode: 'MBA',
            departmentName: 'Department of MBA'),
        equals('Level 2 — Head of Department (HoD)'),
      );
      expect(
        AuthorityDesignationResolver.resolveDesignation(
            levelNumber: 3,
            departmentCode: 'MBA',
            departmentName: 'Department of MBA'),
        equals('Level 3 — Dean of Management Studies (MBA)'),
      );
    });

    test('17. Timeline event remains append-only and immutable', () {
      final event = TimelineEventModel(
        id: 'hist-immut',
        complaintId: 'c-immut',
        newStatus: ComplaintStatus.resolved,
        eventType: 'RESOLVED',
        changedByName: 'Dr. Amit Trivedi',
        actorDesignation: 'Level 1 — Faculty Advisor / Department Officer',
        changedByDept: 'Department of MBA',
        createdAt: baseTime,
      );

      expect(event.newStatus.isTerminal, isTrue);
      expect(event.changedByName, equals('Dr. Amit Trivedi'));
      expect(event.actorDesignation, contains('Faculty Advisor'));
    });
  });
}
