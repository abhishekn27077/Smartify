import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/features/auth/models/user_session_model.dart';
import 'package:smartify/features/authority/utils/authority_workflow_permissions.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

void main() {
  group('SMARTIFY Canonical Authority Workflow & Permissions Invariants', () {
    const mcaDeptId = 'dept-mca-uuid';
    const mbaDeptId = 'dept-mba-uuid';

    const l1Faculty = UserSessionModel(
      id: 'faculty-suresh-id',
      email: 'suresh@mca.institution.edu',
      fullName: 'Prof. Suresh Kumar',
      role: 'authority',
      departmentId: mcaDeptId,
      departmentName: 'Department of MCA',
      authorityLevelNumber: 1,
      authorityLevelTitle: 'Faculty Advisor',
    );

    const l2Hod = UserSessionModel(
      id: 'hod-radhika-id',
      email: 'radhika@mca.institution.edu',
      fullName: 'Dr. Radhika Sharma',
      role: 'authority',
      departmentId: mcaDeptId,
      departmentName: 'Department of MCA',
      authorityLevelNumber: 2,
      authorityLevelTitle: 'Head of Department',
    );

    const l3Dean = UserSessionModel(
      id: 'dean-nair-id',
      email: 'nair@mca.institution.edu',
      fullName: 'Dr. K. S. Nair',
      role: 'authority',
      departmentId: mcaDeptId,
      departmentName: 'Department of MCA',
      authorityLevelNumber: 3,
      authorityLevelTitle: 'Dean of MCA',
    );

    const adminUser = UserSessionModel(
      id: 'admin-id',
      email: 'admin@smartify.institution.edu',
      fullName: 'Chief Administrator',
      role: 'admin',
    );

    const studentUser = UserSessionModel(
      id: 'student-id',
      email: 'student@mca.institution.edu',
      fullName: 'Aarav Patel',
      role: 'student',
      academicProgram: 'MCA',
    );

    GrievanceModel createGrievance({
      required int levelNumber,
      required String levelTitle,
      required ComplaintStatus status,
      String? assignedId,
      String? assignedName,
      bool isCutoff = false,
      String deptId = mcaDeptId,
    }) {
      return GrievanceModel(
        id: 'complaint-uuid-1',
        trackingNumber: 'SMT-2026-01074',
        studentId: 'student-id',
        studentName: 'Aarav Patel',
        departmentId: deptId,
        departmentName: 'Department of MCA',
        departmentCode: 'MCA',
        currentAuthorityLevelId: 'lvl-$levelNumber-id',
        currentAuthorityLevelNumber: levelNumber,
        currentAuthorityLevelTitle: levelTitle,
        assignedAuthorityId: assignedId,
        assignedAuthorityName: assignedName,
        title: 'Lab access permissions issue',
        description:
            'Unable to access high performance computing lab machines.',
        category: 'Lab',
        incidentDate: DateTime.now().subtract(const Duration(days: 2)),
        status: status,
        priority: 'MEDIUM',
        currentTierDeadline: DateTime.now().add(const Duration(days: 3)),
        cutoffDeadline: DateTime.now().add(const Duration(days: 15)),
        isCutoffPaused: isCutoff,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now(),
        attachmentPaths: const [],
      );
    }

    test(
        '1. L1 authority can act when grievance is active at Level 1 and assigned to them',
        () {
      final g = createGrievance(
        levelNumber: 1,
        levelTitle: 'Faculty Advisor',
        status: ComplaintStatus.underReview,
        assignedId: l1Faculty.id,
        assignedName: l1Faculty.fullName,
      );

      expect(AuthorityWorkflowPermissions.canAct(user: l1Faculty, grievance: g),
          isTrue);
      expect(
          AuthorityWorkflowPermissions.isCaseAccepted(
              user: l1Faculty, grievance: g),
          isTrue);
      expect(
          AuthorityWorkflowPermissions.canForward(
              user: l1Faculty, grievance: g),
          isTrue);
      expect(AuthorityWorkflowPermissions.nextForwardLabel(g),
          'FORWARD TO LEVEL 2');
    });

    test(
        '2. FORWARDING ISOLATION: L1 loses ALL action controls once forwarded to L2',
        () {
      final g = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.underReview,
        assignedId: l2Hod.id,
        assignedName: l2Hod.fullName,
      );

      // Previous authority (L1) CANNOT act
      expect(AuthorityWorkflowPermissions.canAct(user: l1Faculty, grievance: g),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.canUnderReview(
              user: l1Faculty, grievance: g),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.canResolve(
              user: l1Faculty, grievance: g),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.canReject(user: l1Faculty, grievance: g),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.canForward(
              user: l1Faculty, grievance: g),
          isFalse);

      // L1 receives unambiguous informational status message
      final info = AuthorityWorkflowPermissions.getInformationalStatusMessage(
          user: l1Faculty, grievance: g);
      expect(
          info,
          contains(
              'Forwarded to Level 2 (Head of Department) — no action required from you.'));

      // New authority (L2) CAN act
      expect(AuthorityWorkflowPermissions.canAct(user: l2Hod, grievance: g),
          isTrue);
      expect(AuthorityWorkflowPermissions.canResolve(user: l2Hod, grievance: g),
          isTrue);
      expect(AuthorityWorkflowPermissions.canReject(user: l2Hod, grievance: g),
          isTrue);
      expect(AuthorityWorkflowPermissions.canForward(user: l2Hod, grievance: g),
          isTrue);
      expect(AuthorityWorkflowPermissions.nextForwardLabel(g),
          'FORWARD TO LEVEL 3');
    });

    test(
        '3. IDEMPOTENCY: Under Review cannot be triggered if grievance is already UNDER_REVIEW',
        () {
      final g = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.underReview,
        assignedId: l2Hod.id,
        assignedName: l2Hod.fullName,
      );

      expect(
          AuthorityWorkflowPermissions.canUnderReview(
              user: l2Hod, grievance: g),
          isFalse);
      expect(AuthorityWorkflowPermissions.canResolve(user: l2Hod, grievance: g),
          isTrue);
    });

    test(
        '4. UNASSIGNED INTAKE: Authority at tier can claim unassigned case; other tiers cannot',
        () {
      final g = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.escalated,
        assignedId: null,
        assignedName: null,
      );

      // L2 can claim unassigned case at L2
      expect(AuthorityWorkflowPermissions.canAct(user: l2Hod, grievance: g),
          isTrue);

      // L1 and L3 cannot act on unassigned case at L2
      expect(AuthorityWorkflowPermissions.canAct(user: l1Faculty, grievance: g),
          isFalse);
      expect(AuthorityWorkflowPermissions.canAct(user: l3Dean, grievance: g),
          isFalse);
    });

    test(
        '5. DEPARTMENT ISOLATION: Authority from MBA department cannot act on MCA grievance',
        () {
      const mbaAuthority = UserSessionModel(
        id: 'mba-officer-id',
        email: 'officer@mba.institution.edu',
        fullName: 'MBA Officer',
        role: 'authority',
        departmentId: mbaDeptId,
        authorityLevelNumber: 2,
      );

      final g = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.underReview,
        deptId: mcaDeptId,
      );

      expect(
          AuthorityWorkflowPermissions.canAct(user: mbaAuthority, grievance: g),
          isFalse);
    });

    test(
        '6. TERMINAL INVARIANCE: Resolved and Rejected lock all action controls',
        () {
      final resolvedG = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.resolved,
        assignedId: l2Hod.id,
        assignedName: l2Hod.fullName,
      );

      expect(
          AuthorityWorkflowPermissions.canAct(
              user: l2Hod, grievance: resolvedG),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.canAct(
              user: adminUser, grievance: resolvedG),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.getInformationalStatusMessage(
              user: l2Hod, grievance: resolvedG),
          contains('Resolved by Dr. Radhika Sharma. Case closed.'));

      final rejectedG = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.rejected,
        assignedId: l2Hod.id,
        assignedName: l2Hod.fullName,
      );

      expect(
          AuthorityWorkflowPermissions.canAct(
              user: l2Hod, grievance: rejectedG),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.getInformationalStatusMessage(
              user: l2Hod, grievance: rejectedG),
          contains('Rejected by Dr. Radhika Sharma. Case closed.'));
    });

    test(
        '7. 20-DAY CUTOFF FREEZE: Cutoff paused case freezes all authority actions',
        () {
      final frozenG = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.cutoffPaused,
        assignedId: l2Hod.id,
        assignedName: l2Hod.fullName,
        isCutoff: true,
      );

      expect(
          AuthorityWorkflowPermissions.canAct(user: l2Hod, grievance: frozenG),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.getInformationalStatusMessage(
              user: l2Hod, grievance: frozenG),
          contains('20-day governance cutoff reached.'));
    });

    test(
        '8. MAX CONFIGURED TIER: Level 3 cannot forward beyond configured maximum (L3 in 3-tier dept)',
        () {
      final g = createGrievance(
        levelNumber: 3,
        levelTitle: 'Dean of MCA',
        status: ComplaintStatus.underReview,
        assignedId: l3Dean.id,
        assignedName: l3Dean.fullName,
      );

      expect(AuthorityWorkflowPermissions.canAct(user: l3Dean, grievance: g),
          isTrue);
      expect(
          AuthorityWorkflowPermissions.canForward(
              user: l3Dean, grievance: g, maxConfiguredLevel: 3),
          isFalse);
    });

    test(
        '9. STUDENTS CANNOT ACT: Student role is strictly denied triage action controls',
        () {
      final g = createGrievance(
        levelNumber: 1,
        levelTitle: 'Faculty Advisor',
        status: ComplaintStatus.pending,
      );

      expect(
          AuthorityWorkflowPermissions.canAct(user: studentUser, grievance: g),
          isFalse);
    });

    test(
        '10. ADMIN GOVERNANCE SEPARATION: Admin cannot act as normal grievance reviewer',
        () {
      final g = createGrievance(
        levelNumber: 2,
        levelTitle: 'Head of Department',
        status: ComplaintStatus.underReview,
        assignedId: l2Hod.id,
        assignedName: l2Hod.fullName,
      );

      expect(AuthorityWorkflowPermissions.canAct(user: adminUser, grievance: g),
          isFalse);
      expect(
          AuthorityWorkflowPermissions.getInformationalStatusMessage(
              user: adminUser, grievance: g),
          contains('Governance & Audit mode'));
    });
  });
}
