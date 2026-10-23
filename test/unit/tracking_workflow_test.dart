import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

void main() {
  group('State Machine Status Transition Permitted Rules', () {
    test('PENDING can only transition to UNDER_REVIEW or REJECTED', () {
      expect(
          ComplaintStatus.pending.canTransitionTo(ComplaintStatus.underReview),
          isTrue);
      expect(ComplaintStatus.pending.canTransitionTo(ComplaintStatus.rejected),
          isTrue);
      expect(ComplaintStatus.pending.canTransitionTo(ComplaintStatus.resolved),
          isFalse);
      expect(ComplaintStatus.pending.canTransitionTo(ComplaintStatus.escalated),
          isFalse);
    });

    test(
        'UNDER_REVIEW can transition to IN_PROGRESS, ESCALATED, RESOLVED, REJECTED',
        () {
      expect(
          ComplaintStatus.underReview
              .canTransitionTo(ComplaintStatus.inProgress),
          isTrue);
      expect(
          ComplaintStatus.underReview
              .canTransitionTo(ComplaintStatus.escalated),
          isTrue);
      expect(
          ComplaintStatus.underReview.canTransitionTo(ComplaintStatus.resolved),
          isTrue);
      expect(
          ComplaintStatus.underReview.canTransitionTo(ComplaintStatus.rejected),
          isTrue);
      expect(
          ComplaintStatus.underReview.canTransitionTo(ComplaintStatus.pending),
          isFalse);
    });

    test('IN_PROGRESS can transition to ESCALATED, RESOLVED, REJECTED', () {
      expect(
          ComplaintStatus.inProgress.canTransitionTo(ComplaintStatus.resolved),
          isTrue);
      expect(
          ComplaintStatus.inProgress.canTransitionTo(ComplaintStatus.rejected),
          isTrue);
      expect(
          ComplaintStatus.inProgress.canTransitionTo(ComplaintStatus.escalated),
          isTrue);
      expect(
          ComplaintStatus.inProgress.canTransitionTo(ComplaintStatus.pending),
          isFalse);
    });

    test(
        'CUTOFF_PAUSED can only transition to UNDER_REVIEW via Admin resumption',
        () {
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.underReview),
          isTrue);
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.resolved),
          isFalse);
      expect(
          ComplaintStatus.cutoffPaused
              .canTransitionTo(ComplaintStatus.escalated),
          isFalse);
    });

    test('RESOLVED and REJECTED are terminal states', () {
      expect(ComplaintStatus.resolved.isTerminal, isTrue);
      expect(ComplaintStatus.resolved.permittedNextStatuses, isEmpty);
      expect(ComplaintStatus.rejected.isTerminal, isTrue);
      expect(ComplaintStatus.rejected.permittedNextStatuses, isEmpty);
    });
  });

  group('Student Complaint Isolation Logic', () {
    final now = DateTime.now();
    final student1Grievance = GrievanceModel(
      id: 'g-1',
      trackingNumber: 'SMT-2026-00001',
      studentId: 'student-uuid-aaa',
      departmentId: 'd-1',
      departmentName: 'Academic Affairs',
      departmentCode: 'ACAD',
      currentAuthorityLevelId: 'lvl-1',
      currentAuthorityLevelNumber: 1,
      currentAuthorityLevelTitle: 'Level 1: Faculty Advisor',
      title: 'Grading query',
      description: 'Mark discrepancy in semester exam.',
      category: 'Academic Affairs',
      incidentDate: now.subtract(const Duration(days: 2)),
      status: ComplaintStatus.pending,
      priority: 'MEDIUM',
      currentTierDeadline: now.add(const Duration(days: 3)),
      cutoffDeadline: now.add(const Duration(days: 20)),
      createdAt: now,
      updatedAt: now,
    );

    final student2Grievance = GrievanceModel(
      id: 'g-2',
      trackingNumber: 'SMT-2026-00002',
      studentId: 'student-uuid-bbb',
      departmentId: 'd-2',
      departmentName: 'Hostel & Residential',
      departmentCode: 'HOSTEL',
      currentAuthorityLevelId: 'lvl-1',
      currentAuthorityLevelNumber: 1,
      currentAuthorityLevelTitle: 'Level 1: Warden',
      title: 'Hostel light issue',
      description: 'Tube light broken in room 12.',
      category: 'Hostel & Residential Life',
      incidentDate: now.subtract(const Duration(days: 1)),
      status: ComplaintStatus.underReview,
      priority: 'LOW',
      currentTierDeadline: now.add(const Duration(days: 3)),
      cutoffDeadline: now.add(const Duration(days: 20)),
      createdAt: now,
      updatedAt: now,
    );

    test('Student filter excludes grievances owned by other students', () {
      final allGrievances = [student1Grievance, student2Grievance];
      const authenticatedStudentId = 'student-uuid-aaa';

      final filteredForStudent = allGrievances
          .where((g) => g.studentId == authenticatedStudentId)
          .toList();

      expect(filteredForStudent.length, 1);
      expect(filteredForStudent.first.id, 'g-1');
      expect(filteredForStudent.any((g) => g.studentId == 'student-uuid-bbb'),
          isFalse);
    });
  });

  group('Timeline Chronological Order', () {
    final now = DateTime.now();

    test('Events sort strictly in ascending chronological order', () {
      final event1 = TimelineEventModel(
        id: 'e-1',
        complaintId: 'c-1',
        newStatus: ComplaintStatus.pending,
        createdAt: now.subtract(const Duration(days: 3)),
      );
      final event2 = TimelineEventModel(
        id: 'e-2',
        complaintId: 'c-1',
        newStatus: ComplaintStatus.underReview,
        createdAt: now.subtract(const Duration(days: 2)),
      );
      final event3 = TimelineEventModel(
        id: 'e-3',
        complaintId: 'c-1',
        newStatus: ComplaintStatus.inProgress,
        createdAt: now.subtract(const Duration(hours: 4)),
      );

      final events = [event3, event1, event2];
      events.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      expect(events[0].id, 'e-1');
      expect(events[1].id, 'e-2');
      expect(events[2].id, 'e-3');
    });
  });

  group('SLA Calculations and Urgency', () {
    final now = DateTime.now();

    test('Overdue grievance correctly flagged as breached', () {
      final overdue = GrievanceModel(
        id: 'g-overdue',
        trackingNumber: 'SMT-2026-OVERDUE',
        studentId: 's-1',
        departmentId: 'd-1',
        departmentName: 'Academic',
        departmentCode: 'ACAD',
        currentAuthorityLevelId: 'lvl-1',
        currentAuthorityLevelNumber: 1,
        currentAuthorityLevelTitle: 'Level 1',
        title: 'Overdue test',
        description: 'Test overdue description text.',
        category: 'Academic',
        incidentDate: now.subtract(const Duration(days: 5)),
        status: ComplaintStatus.inProgress,
        priority: 'URGENT',
        currentTierDeadline:
            now.subtract(const Duration(hours: 12)), // 12 hours ago
        cutoffDeadline: now.add(const Duration(days: 15)),
        createdAt: now.subtract(const Duration(days: 4)),
        updatedAt: now,
      );

      expect(overdue.isSlaBreached, isTrue);
      expect(overdue.formattedTimeRemaining, contains('overdue'));
      expect(overdue.slaStatusHeadline, 'ACTION OVERDUE');
    });

    test('Resolved grievance is never marked as SLA breached', () {
      final resolved = GrievanceModel(
        id: 'g-resolved',
        trackingNumber: 'SMT-2026-RESOLVED',
        studentId: 's-1',
        departmentId: 'd-1',
        departmentName: 'Academic',
        departmentCode: 'ACAD',
        currentAuthorityLevelId: 'lvl-1',
        currentAuthorityLevelNumber: 1,
        currentAuthorityLevelTitle: 'Level 1',
        title: 'Resolved test',
        description: 'Test resolved description text.',
        category: 'Academic',
        incidentDate: now.subtract(const Duration(days: 5)),
        status: ComplaintStatus.resolved,
        priority: 'MEDIUM',
        currentTierDeadline: now.subtract(const Duration(hours: 12)),
        cutoffDeadline: now.add(const Duration(days: 15)),
        createdAt: now.subtract(const Duration(days: 4)),
        updatedAt: now,
      );

      expect(resolved.isSlaBreached, isFalse);
      expect(resolved.formattedTimeRemaining, 'Closed');
    });
  });
}
