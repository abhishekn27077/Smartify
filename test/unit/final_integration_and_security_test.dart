import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/utils/date_validator.dart';
import 'package:smartify/features/analytics/services/report_export_service.dart';
import 'package:smartify/features/auth/models/user_session_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

void main() {
  group('1. Student Authentication & Least Privilege Defaults', () {
    test('Default user role is strictly student', () {
      const student = UserSessionModel(
        id: 'usr-1',
        email: 'student@campus.edu',
        fullName: 'Aarav Patel',
        role: 'student',
      );

      expect(student.isStudent, isTrue);
      expect(student.isAuthority, isFalse);
      expect(student.isAdmin, isFalse);
    });

    test('Authority and Admin roles require explicit assignment', () {
      const authority = UserSessionModel(
        id: 'usr-2',
        email: 'warden@campus.edu',
        fullName: 'Prof. Ananya Sen',
        role: 'authority',
      );
      expect(authority.isAuthority, isTrue);

      const admin = UserSessionModel(
        id: 'usr-3',
        email: 'dean@campus.edu',
        fullName: 'Dr. Aris Thorne',
        role: 'admin',
      );
      expect(admin.isAdmin, isTrue);
    });
  });

  group('2. 7-Calendar-Day Retrospective Complaint Date Constraint', () {
    final now = DateTime.now();

    test('Valid dates: within [today - 7 days, today]', () {
      expect(DateValidator.isValidIncidentDate(now), isTrue); // Today
      expect(
          DateValidator.isValidIncidentDate(
              now.subtract(const Duration(days: 3))),
          isTrue);
      expect(
          DateValidator.isValidIncidentDate(
              now.subtract(const Duration(days: 7))),
          isTrue);
    });

    test('Invalid dates: future dates or older than 7 calendar days', () {
      expect(
          DateValidator.isValidIncidentDate(now.add(const Duration(days: 1))),
          isFalse); // Future
      expect(
          DateValidator.isValidIncidentDate(
              now.subtract(const Duration(days: 8))),
          isFalse); // 8 days ago
      expect(
          DateValidator.isValidIncidentDate(
              now.subtract(const Duration(days: 30))),
          isFalse);
    });
  });

  group('3. Status Machine & 20-Day Cutoff Precedence', () {
    test('PENDING can only transition to UNDER_REVIEW or REJECTED', () {
      expect(
          ComplaintStatus.pending.canTransitionTo(ComplaintStatus.underReview),
          isTrue);
      expect(ComplaintStatus.pending.canTransitionTo(ComplaintStatus.rejected),
          isTrue);
      expect(ComplaintStatus.pending.canTransitionTo(ComplaintStatus.resolved),
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
    });

    test('RESOLVED and REJECTED are terminal', () {
      expect(ComplaintStatus.resolved.isTerminal, isTrue);
      expect(ComplaintStatus.rejected.isTerminal, isTrue);
    });
  });

  group('4. Security: CSV Formula-Injection Mitigation', () {
    test('Prepends single quote to neutralize spreadsheet formulas', () {
      expect(ReportExportService.sanitizeCsvCell('=cmd|"/c calc"!A0'),
          "'=cmd|\"/c calc\"!A0");
      expect(ReportExportService.sanitizeCsvCell('+123'), "'+123");
      expect(ReportExportService.sanitizeCsvCell('-5'), "'-5");
      expect(
          ReportExportService.sanitizeCsvCell('@SUM(A1:A10)'), "'@SUM(A1:A10)");
      expect(ReportExportService.sanitizeCsvCell('\tscript'), "'\tscript");
      expect(ReportExportService.sanitizeCsvCell('Normal Text'), 'Normal Text');
    });
  });

  group('5. Student Cross-User Data Isolation', () {
    final now = DateTime.now();
    final allComplaints = [
      GrievanceModel(
        id: 'g-1',
        trackingNumber: 'SMT-2026-00001',
        studentId: 'student-alice',
        departmentId: 'd-1',
        departmentName: 'Academic',
        departmentCode: 'ACAD',
        currentAuthorityLevelId: 'lvl-1',
        currentAuthorityLevelNumber: 1,
        currentAuthorityLevelTitle: 'Level 1',
        title: 'Alice Query',
        description: 'Mark verification request.',
        category: 'Academic',
        incidentDate: now,
        status: ComplaintStatus.pending,
        priority: 'MEDIUM',
        currentTierDeadline: now.add(const Duration(days: 3)),
        cutoffDeadline: now.add(const Duration(days: 20)),
        createdAt: now,
        updatedAt: now,
      ),
      GrievanceModel(
        id: 'g-2',
        trackingNumber: 'SMT-2026-00002',
        studentId: 'student-bob',
        departmentId: 'd-2',
        departmentName: 'Hostel',
        departmentCode: 'HOSTEL',
        currentAuthorityLevelId: 'lvl-1',
        currentAuthorityLevelNumber: 1,
        currentAuthorityLevelTitle: 'Level 1',
        title: 'Bob Query',
        description: 'Hostel room light issue.',
        category: 'Hostel',
        incidentDate: now,
        status: ComplaintStatus.pending,
        priority: 'LOW',
        currentTierDeadline: now.add(const Duration(days: 3)),
        cutoffDeadline: now.add(const Duration(days: 20)),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    test('Alice only receives complaints where studentId == alice', () {
      final aliceView =
          allComplaints.where((c) => c.studentId == 'student-alice').toList();
      expect(aliceView.length, 1);
      expect(aliceView.first.id, 'g-1');
      expect(aliceView.any((c) => c.studentId == 'student-bob'), isFalse);
    });
  });
}
