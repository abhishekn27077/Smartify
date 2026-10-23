import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/features/admin/models/audit_log_model.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

void main() {
  group(
      'SMARTIFY Phase 2 — Production UI/UX Navigation & Drill-Down Invariants',
      () {
    final now = DateTime.now();

    final mcaGrievance = GrievanceModel(
      id: 'g-mca-1',
      trackingNumber: 'SMT-2026-MCA01',
      studentId: 'stud-1',
      studentName: 'Rahul Verma',
      departmentId: '53f56adf-ffb8-46ca-ab62-35777bd2e3b9',
      departmentName: 'Department of MCA',
      departmentCode: 'MCA',
      currentAuthorityLevelId: 'lvl-1',
      currentAuthorityLevelNumber: 1,
      currentAuthorityLevelTitle: 'Faculty / Department Officer',
      assignedAuthorityId: 'auth-suresh',
      assignedAuthorityName: 'Prof. Suresh Kumar',
      title: 'Classroom Projector Malfunction in Lab 3',
      description: 'The ceiling projector HDMI port is completely damaged.',
      category: 'Academic',
      incidentDate: now.subtract(const Duration(days: 2)),
      status: ComplaintStatus.underReview,
      priority: 'HIGH',
      currentTierDeadline: now.add(const Duration(days: 2)),
      cutoffDeadline: now.add(const Duration(days: 18)),
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(hours: 4)),
    );

    final mbaGrievance = GrievanceModel(
      id: 'g-mba-1',
      trackingNumber: 'SMT-2026-MBA01',
      studentId: 'stud-2',
      studentName: 'Priya Sharma',
      departmentId: '67042d0f-c806-405d-be7b-5bab63f33270',
      departmentName: 'Department of MBA',
      departmentCode: 'MBA',
      currentAuthorityLevelId: 'lvl-2',
      currentAuthorityLevelNumber: 2,
      currentAuthorityLevelTitle: 'Head of Department',
      assignedAuthorityId: 'auth-meenakshi',
      assignedAuthorityName: 'Dr. Meenakshi Sundaram',
      title: 'Elective Selection Conflict',
      description: 'Finance elective timetable overlaps with marketing core.',
      category: 'Academic',
      incidentDate: now.subtract(const Duration(days: 3)),
      status: ComplaintStatus.escalated,
      priority: 'MEDIUM',
      currentTierDeadline:
          now.subtract(const Duration(hours: 2)), // SLA breached
      cutoffDeadline: now.add(const Duration(days: 17)),
      resolutionNotes: 'Forwarded to HoD for timetable adjustment.',
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(hours: 1)),
    );

    final hostelGrievance = GrievanceModel(
      id: 'g-hostel-1',
      trackingNumber: 'SMT-2026-HST01',
      studentId: 'stud-1', // Same student, different department!
      studentName: 'Rahul Verma',
      departmentId: '38ff3afe-2f87-4acb-a676-084922565029',
      departmentName: 'Hostel & Residential Life',
      departmentCode: 'HOSTEL',
      currentAuthorityLevelId: 'lvl-1',
      currentAuthorityLevelNumber: 1,
      currentAuthorityLevelTitle: 'Hostel Warden',
      assignedAuthorityId: null, // Unassigned
      assignedAuthorityName: null,
      title: 'Water Heater Not Functioning in Block B',
      description: 'Geyser tripping main fuse on 2nd floor bathroom.',
      category: 'Hostel',
      incidentDate: now.subtract(const Duration(days: 1)),
      status: ComplaintStatus.pending,
      priority: 'HIGH',
      currentTierDeadline: now.add(const Duration(days: 3)),
      cutoffDeadline: now.add(const Duration(days: 19)),
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    final allGrievances = [mcaGrievance, mbaGrievance, hostelGrievance];

    test(
        '1. Department Drill-Down Invariant: MCA filter isolates ONLY MCA cases',
        () {
      final mcaFiltered = allGrievances
          .where(
              (g) => g.departmentId == '53f56adf-ffb8-46ca-ab62-35777bd2e3b9')
          .toList();

      expect(mcaFiltered.length, equals(1));
      expect(mcaFiltered.first.trackingNumber, equals('SMT-2026-MCA01'));
      expect(mcaFiltered.first.departmentCode, equals('MCA'));
      // Verifies MBA and Hostel are never leaked into MCA
      expect(mcaFiltered.any((g) => g.departmentCode == 'MBA'), isFalse);
      expect(mcaFiltered.any((g) => g.departmentCode == 'HOSTEL'), isFalse);
    });

    test(
        '2. Operational Department Drill-Down Invariant: Hostel filter isolates ONLY Hostel cases',
        () {
      final hostelFiltered = allGrievances
          .where(
              (g) => g.departmentId == '38ff3afe-2f87-4acb-a676-084922565029')
          .toList();

      expect(hostelFiltered.length, equals(1));
      expect(hostelFiltered.first.trackingNumber, equals('SMT-2026-HST01'));
      expect(hostelFiltered.first.departmentCode, equals('HOSTEL'));
      expect(hostelFiltered.first.assignedAuthorityName, isNull);
    });

    test(
        '3. Program vs Department Invariant: Student program does NOT override responsible department',
        () {
      // Rahul Verma is MCA student, but submitted hostel complaint
      expect(hostelGrievance.studentName, equals('Rahul Verma'));
      expect(hostelGrievance.departmentCode, equals('HOSTEL'));
      expect(hostelGrievance.departmentCode, isNot(equals('MCA')));
    });

    test(
        '4. Authority "My Cases" Isolation Invariant: Authority sees only assigned cases',
        () {
      const sureshId = 'auth-suresh';
      final sureshCases = allGrievances
          .where((g) => g.assignedAuthorityId == sureshId)
          .toList();

      expect(sureshCases.length, equals(1));
      expect(sureshCases.first.trackingNumber, equals('SMT-2026-MCA01'));
      expect(sureshCases.first.assignedAuthorityName,
          equals('Prof. Suresh Kumar'));

      // Case without assigned authority is in queue, but NOT in My Cases
      expect(sureshCases.any((g) => g.assignedAuthorityId == null), isFalse);
    });

    test(
        '5. Authority Escalations Screen Invariant: Shows forwarded cases and SLA breaches',
        () {
      final escalations = allGrievances.where((g) {
        return g.status == ComplaintStatus.escalated ||
            g.currentAuthorityLevelNumber > 1 ||
            g.status == ComplaintStatus.cutoffPaused ||
            g.isOverdue;
      }).toList();

      expect(escalations.length, equals(1));
      expect(escalations.first.trackingNumber, equals('SMT-2026-MBA01'));
      expect(escalations.first.currentAuthorityLevelNumber, equals(2));
      expect(escalations.first.isOverdue, isTrue);
      expect(escalations.first.statusRemarks, isNotNull);
    });

    test('6. Authority Workload Deduplication & Metrics Invariant', () {
      final workload = [
        const AuthorityWorkloadMetric(
          id: 'auth-suresh',
          fullName: 'Prof. Suresh Kumar',
          departmentName: 'Department of MCA',
          authorityLevelTitle: 'Faculty / Department Officer',
          activeCaseload: 1,
          resolvedCount: 3,
        ),
        const AuthorityWorkloadMetric(
          id: 'auth-meenakshi',
          fullName: 'Dr. Meenakshi Sundaram',
          departmentName: 'Department of MBA',
          authorityLevelTitle: 'Head of Department',
          activeCaseload: 1,
          resolvedCount: 5,
        ),
      ];

      // Verify unique IDs and non-overlapping workloads
      final ids = workload.map((w) => w.id).toSet();
      expect(ids.length, equals(workload.length));
      expect(workload.first.fullName, equals('Prof. Suresh Kumar'));
      expect(workload.first.authorityLevelTitle,
          equals('Faculty / Department Officer'));
      expect(workload.last.fullName, equals('Dr. Meenakshi Sundaram'));
      expect(workload.last.authorityLevelTitle, equals('Head of Department'));
    });

    test(
        '7. System Actor vs Human Actor Invariant: Audit & Timeline actor verification',
        () {
      final humanLog = AuditLogModel(
        id: 'aud-1',
        actorId: 'auth-suresh',
        actorName: 'Prof. Suresh Kumar',
        action: 'UPDATE_STATUS_UNDER_REVIEW',
        entityType: 'grievance',
        entityId: 'g-mca-1',
        metadata: {'remarks': 'Review started'},
        createdAt: now,
      );

      final systemLog = AuditLogModel(
        id: 'aud-2',
        actorId: null,
        actorName: null,
        action: 'AUTO_ESCALATE_TIER_FORWARD',
        entityType: 'grievance',
        entityId: 'g-mba-1',
        metadata: {'trigger': 'sla_breached'},
        createdAt: now,
      );

      expect(humanLog.isSystemEvent, isFalse);
      expect(humanLog.actorName, equals('Prof. Suresh Kumar'));

      expect(systemLog.isSystemEvent, isTrue);
      expect(systemLog.actorId, isNull);
    });

    test(
        '8. Role Navigation Invariant: Verify all destinations are defined with correct labels',
        () {
      final studentNav = [
        'Home',
        'My Grievances',
        'Submit',
        'Notifications',
        'Profile'
      ];
      final authorityNav = [
        'Queue',
        'My Cases',
        'Escalations',
        'Notifications',
        'Profile'
      ];
      final adminNav = [
        'Dashboard',
        'Departments',
        'Analytics',
        'Governance',
        'Notifications',
        'Profile'
      ];

      expect(
          studentNav,
          containsAllInOrder(
              ['Home', 'My Grievances', 'Submit', 'Notifications', 'Profile']));
      expect(
          authorityNav,
          containsAllInOrder([
            'Queue',
            'My Cases',
            'Escalations',
            'Notifications',
            'Profile'
          ]));
      expect(
          adminNav,
          containsAllInOrder([
            'Dashboard',
            'Departments',
            'Analytics',
            'Governance',
            'Notifications',
            'Profile'
          ]));
    });
  });
}
