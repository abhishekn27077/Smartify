import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/authority/services/authority_service.dart';
import 'package:smartify/features/complaints/models/complaint_category_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

void main() {
  group('SMARTIFY Phase 1 — Backend, Routing & Audit Unit Tests', () {
    late AuthorityService authorityService;

    setUp(() {
      authorityService = AuthorityService();
    });

    test('1. Forwarding validation requires minimum 5-character justification',
        () async {
      expect(
        () => authorityService.forwardToNextTier(
          complaintId: 'test-123',
          currentLevelId: 'lvl-1',
          currentLevelNumber: 1,
          reason: 'abc',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('2. Forwarding validation prevents forwarding beyond Level 4',
        () async {
      expect(
        () => authorityService.forwardToNextTier(
          complaintId: 'test-123',
          currentLevelId: 'lvl-4',
          currentLevelNumber: 4,
          reason: 'Escalation to ombudsman',
        ),
        throwsA(isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          contains('highest authority level'),
        )),
      );
    });

    test(
        '3. TimelineEventModel deserializes human authority identity without Unknown User',
        () {
      final json = {
        'id': 'evt-1',
        'complaint_id': 'comp-1',
        'old_status': 'PENDING',
        'new_status': 'UNDER_REVIEW',
        'event_type': 'UNDER_REVIEW',
        'actor_display_name': 'Prof. Suresh Kumar',
        'actor_role': 'authority',
        'actor_designation': 'Level 1 — Faculty / Department Officer',
        'actor_department_name': 'Department of MCA',
        'is_system_event': false,
        'remarks': 'Review started',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);

      expect(event.changedByName, 'Prof. Suresh Kumar');
      expect(event.changedByRole, 'authority');
      expect(event.actorDesignation, 'Level 1 — Faculty / Department Officer');
      expect(event.changedByDept, 'Department of MCA');
      expect(event.isSystemEvent, false);
      expect(event.changedByName, isNot(contains('Unknown')));
      expect(event.changedByName, isNot(equals('USER')));
    });

    test(
        '4. TimelineEventModel marks automated events as System Redressal Engine (AUTOMATED)',
        () {
      final json = {
        'id': 'evt-2',
        'complaint_id': 'comp-1',
        'old_status': 'UNDER_REVIEW',
        'new_status': 'ESCALATED',
        'event_type': 'SYSTEM_ESCALATION',
        'actor_display_name': 'System Redressal Engine (AUTOMATED)',
        'actor_role': 'SYSTEM',
        'actor_designation': 'Automated System',
        'is_system_event': true,
        'remarks': 'Auto-forwarded due to SLA expiration',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);

      expect(event.isSystemEvent, true);
      expect(event.changedByName, 'System Redressal Engine (AUTOMATED)');
      expect(event.changedByRole, 'SYSTEM');
    });

    test('5. TimelineEventModel preserves student submitter identity and role',
        () {
      final json = {
        'id': 'evt-3',
        'complaint_id': 'comp-1',
        'old_status': null,
        'new_status': 'PENDING',
        'event_type': 'SUBMITTED',
        'actor_display_name': 'Aarav Patel',
        'actor_role': 'student',
        'actor_designation': 'MCA Student',
        'actor_department_name': 'Department of MCA',
        'is_system_event': false,
        'remarks': 'Grievance registered',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final event = TimelineEventModel.fromJson(json);

      expect(event.changedByName, 'Aarav Patel');
      expect(event.changedByRole, 'student');
      expect(event.actorDesignation, 'MCA Student');
    });

    test('6. GrievanceModel retains assigned authority name when populated',
        () {
      final json = {
        'id': 'g-101',
        'tracking_number': 'SMT-2026-01028',
        'student_id': 's-1',
        'department_id': 'd-1',
        'current_authority_level_id': 'l-1',
        'assigned_authority_id': 'a-1',
        'authority_profile': {'full_name': 'Dr. Amit Trivedi'},
        'title': 'Test Grievance',
        'description': 'Valid test grievance description with facts.',
        'category': 'Academic Affairs',
        'incident_date': '2026-10-18',
        'status': 'RESOLVED',
        'current_tier_deadline':
            DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'cutoff_deadline':
            DateTime.now().add(const Duration(days: 20)).toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final model = GrievanceModel.fromJson(json);
      expect(model.assignedAuthorityName, 'Dr. Amit Trivedi');
      expect(model.assignedAuthorityId, 'a-1');
      expect(model.status, ComplaintStatus.resolved);
    });

    test(
        '7. State Machine: CUTOFF_PAUSED cannot transition directly to RESOLVED or REJECTED',
        () {
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.resolved),
          false);
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.rejected),
          false);
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.escalated),
          false);
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.underReview),
          true);
    });

    test('8. State Machine: RESOLVED and REJECTED are strictly terminal states',
        () {
      expect(ComplaintStatus.resolved.isTerminal, true);
      expect(ComplaintStatus.rejected.isTerminal, true);
      expect(ComplaintStatus.resolved.permittedNextStatuses, isEmpty);
      expect(ComplaintStatus.rejected.permittedNextStatuses, isEmpty);
    });

    test('9. Operational Routing: IT category derives IT department code', () {
      final wifiCat = ComplaintCategoryModel.predefinedCategories.firstWhere(
        (c) => c.title.contains('IT'),
      );
      expect(wifiCat.defaultDepartmentCode, 'IT');
    });

    test(
        '10. Operational Routing: Hostel category derives HOSTEL department code',
        () {
      final hostelCat = ComplaintCategoryModel.predefinedCategories.firstWhere(
        (c) => c.title.contains('Hostel'),
      );
      expect(hostelCat.defaultDepartmentCode, 'HOSTEL');
    });

    test(
        '11. Operational Routing: Accounts category derives FIN department code',
        () {
      final feeCat = ComplaintCategoryModel.predefinedCategories.firstWhere(
        (c) => c.title.contains('Accounts'),
      );
      expect(feeCat.defaultDepartmentCode, 'FIN');
    });

    test(
        '12. Operational Routing: Infrastructure category derives INFRA department code',
        () {
      final infraCat = ComplaintCategoryModel.predefinedCategories.firstWhere(
        (c) => c.title.contains('Infrastructure'),
      );
      expect(infraCat.defaultDepartmentCode, 'INFRA');
    });
  });
}
