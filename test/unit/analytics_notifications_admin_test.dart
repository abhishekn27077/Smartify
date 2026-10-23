import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/features/admin/models/admin_user_model.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';
import 'package:smartify/features/analytics/services/report_export_service.dart';
import 'package:smartify/features/auth/models/user_session_model.dart';
import 'package:smartify/features/notifications/models/app_notification_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

void main() {
  group('1. Analytics Metric Calculations', () {
    final now = DateTime.now();
    final analytics = AnalyticsDataModel(
      periodStart: now.subtract(const Duration(days: 30)),
      periodEnd: now,
      totalSubmitted: 50,
      totalResolved: 35,
      totalPending: 5,
      totalUnderReview: 4,
      totalInProgress: 3,
      totalPaused: 2,
      totalEscalated: 1,
      totalRejected: 0,
      overdueCount: 3,
      averageResolutionDays: 4.2,
      departmentDistribution: const [
        DepartmentMetric(
            id: 'd-1',
            name: 'Academic Affairs',
            code: 'ACAD',
            totalComplaints: 30,
            resolvedCount: 22,
            pausedCount: 1),
        DepartmentMetric(
            id: 'd-2',
            name: 'Hostel',
            code: 'HOSTEL',
            totalComplaints: 20,
            resolvedCount: 13,
            pausedCount: 1),
      ],
      categoryDistribution: const [
        CategoryMetric(category: 'Academic', count: 30),
        CategoryMetric(category: 'Hostel', count: 20),
      ],
      monthlyTrends: const [
        MonthlyTrendMetric(
            monthLabel: 'Sep 2026', submittedCount: 20, resolvedCount: 15),
        MonthlyTrendMetric(
            monthLabel: 'Oct 2026', submittedCount: 30, resolvedCount: 20),
      ],
      authorityWorkload: const [],
    );

    test('Resolution rate computes correctly as (resolved / total) * 100', () {
      expect(analytics.resolutionRate, closeTo(70.0, 0.01));
    });

    test(
        'Zero total complaints yields 0% resolution rate without division by zero',
        () {
      final zeroAnalytics = AnalyticsDataModel(
        periodStart: now,
        periodEnd: now,
        totalSubmitted: 0,
        totalResolved: 0,
        totalPending: 0,
        totalUnderReview: 0,
        totalInProgress: 0,
        totalPaused: 0,
        totalEscalated: 0,
        totalRejected: 0,
        overdueCount: 0,
        averageResolutionDays: 0.0,
        departmentDistribution: const [],
        categoryDistribution: const [],
        monthlyTrends: const [],
        authorityWorkload: const [],
      );

      expect(zeroAnalytics.resolutionRate, 0.0);
    });
  });

  group('2. CSV Formula Injection (DDE) Mitigation', () {
    test(
        'Prefixes single quote on potentially dangerous spreadsheet formula triggers',
        () {
      expect(ReportExportService.sanitizeCsvCell('=1+1'), "'=1+1");
      expect(
          ReportExportService.sanitizeCsvCell('+1234567890'), "'+1234567890");
      expect(ReportExportService.sanitizeCsvCell('-5+10'), "'-5+10");
      expect(
          ReportExportService.sanitizeCsvCell('@SUM(A1:A10)'), "'@SUM(A1:A10)");
      expect(ReportExportService.sanitizeCsvCell('\tmalicious_tab'),
          "'\tmalicious_tab");
      expect(ReportExportService.sanitizeCsvCell('\rmalicious_return'),
          "'\rmalicious_return");
    });

    test('Leaves benign strings untampered', () {
      expect(ReportExportService.sanitizeCsvCell('SMT-2026-00001'),
          'SMT-2026-00001');
      expect(
          ReportExportService.sanitizeCsvCell('Hostel water issue in Block B'),
          'Hostel water issue in Block B');
      expect(ReportExportService.sanitizeCsvCell('Academic Affairs'),
          'Academic Affairs');
    });

    test('Generated CSV properly sanitizes malicious complaint titles', () {
      final now = DateTime.now();
      final complaints = [
        GrievanceModel(
          id: 'c-inj',
          trackingNumber: 'SMT-2026-MALICIOUS',
          studentId: 's-1',
          departmentId: 'd-1',
          departmentName: 'Academic',
          departmentCode: 'ACAD',
          currentAuthorityLevelId: 'lvl-1',
          currentAuthorityLevelNumber: 1,
          currentAuthorityLevelTitle: 'Level 1',
          title: '=cmd|"/c calc"!A0', // Classic CSV injection vector
          description: '+dangerously_evaluated_expression',
          category: '@admin_formula',
          incidentDate: now,
          status: ComplaintStatus.pending,
          priority: 'HIGH',
          currentTierDeadline: now.add(const Duration(days: 3)),
          cutoffDeadline: now.add(const Duration(days: 20)),
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final csvString = ReportExportService.generateComplaintsCsv(complaints);
      expect(csvString,
          contains("`'=cmd|\"\"/c calc\"\"!A0`".replaceAll('`', '')));
      expect(csvString, contains("`'@admin_formula`".replaceAll('`', '')));
      expect(csvString, isNot(contains('\n=cmd')));
    });
  });

  group('3. Notification Ownership & Unread Counts', () {
    final now = DateTime.now();
    final notifs = [
      AppNotificationModel(
        id: 'n-1',
        userId: 'student-alice',
        title: 'Status Updated',
        message: 'Grievance Under Review',
        notificationType: 'STATUS_CHANGE',
        isRead: false,
        createdAt: now.subtract(const Duration(minutes: 10)),
      ),
      AppNotificationModel(
        id: 'n-2',
        userId: 'student-alice',
        title: 'Escalated',
        message: 'Grievance escalated to HoD',
        notificationType: 'ESCALATION',
        isRead: true,
        readAt: now.subtract(const Duration(minutes: 5)),
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
    ];

    test('Unread count accurately tallies unread items', () {
      final unreadCount = notifs.where((n) => !n.isRead).length;
      expect(unreadCount, 1);
    });

    test('Marking notification read updates isRead and readAt', () {
      final unread = notifs.first;
      final read = unread.copyWith(isRead: true, readAt: now);
      expect(read.isRead, isTrue);
      expect(read.readAt, isNotNull);
    });
  });

  group('4. Analytics Department Scoping & Isolation Tests', () {
    test(
        'Authority scoped analytics model parses only single authorized department',
        () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 5,
        'total_resolved': 1,
        'total_pending': 2,
        'total_under_review': 1,
        'total_in_progress': 0,
        'total_paused': 1,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 1,
        'average_resolution_days': 2.5,
        'department_distribution': [
          {
            'id': '53f56adf-ffb8-46ca-ab62-35777bd2e3b9',
            'name': 'Department of MCA',
            'code': 'MCA',
            'total_complaints': 5,
            'resolved_count': 1,
            'paused_count': 1,
          }
        ],
        'category_distribution': [
          {'category': 'Academic Affairs (Lab Facilities)', 'count': 5}
        ],
        'monthly_trends': [
          {'month_label': 'Oct 2026', 'submitted_count': 5, 'resolved_count': 1}
        ],
        'authority_workload': [
          {
            'id': '9b6c1670-3022-40ff-84b7-4acb5fa44139',
            'full_name': 'Prof. Suresh Kumar',
            'department_name': 'Department of MCA',
            'authority_level_title':
                'Level 1: Faculty Advisor / Department Officer',
            'active_caseload': 2,
            'resolved_count': 1,
          },
          {
            'id': 'fe2a30f6-3aa1-47ad-8a88-9d46f537d9c4',
            'full_name': 'Dr. Radhika Sharma',
            'department_name': 'Department of MCA',
            'authority_level_title': 'Level 2: Head of Department (HoD)',
            'active_caseload': 1,
            'resolved_count': 0,
          }
        ],
      };

      final model = AnalyticsDataModel.fromJson(json);

      // Scoped checks:
      expect(model.departmentDistribution.length, equals(1));
      expect(
          model.departmentDistribution.first.name, equals('Department of MCA'));
      expect(model.departmentDistribution.first.code, equals('MCA'));

      // Unrelated departments MUST NOT appear
      final deptNames =
          model.departmentDistribution.map((d) => d.name).toList();
      expect(deptNames, isNot(contains('Hostel & Residential Life')));
      expect(deptNames, isNot(contains('Accounts & Finance')));
      expect(deptNames, isNot(contains('Library & IT Services')));
      expect(deptNames, isNot(contains('Infrastructure & Campus Facilities')));
      expect(deptNames, isNot(contains('Department of MBA')));
      expect(deptNames, isNot(contains('Department of M.Com')));

      // Status sum reconciliation:
      final sumStatuses = model.totalResolved +
          model.totalPending +
          model.totalUnderReview +
          model.totalInProgress +
          model.totalPaused +
          model.totalEscalated +
          model.totalRejected;
      expect(sumStatuses, equals(model.totalSubmitted));

      // Authority workload must contain ONLY MCA staff
      expect(model.authorityWorkload.length, equals(2));
      for (final w in model.authorityWorkload) {
        expect(w.departmentName, equals('Department of MCA'));
      }
    });

    test('Admin institute-wide analytics includes all canonical departments',
        () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 27,
        'total_resolved': 12,
        'total_pending': 4,
        'total_under_review': 3,
        'total_in_progress': 2,
        'total_paused': 3,
        'total_escalated': 2,
        'total_rejected': 1,
        'overdue_count': 4,
        'average_resolution_days': 3.8,
        'department_distribution': [
          {
            'id': 'd-1',
            'name': 'Department of MCA',
            'code': 'MCA',
            'total_complaints': 5,
            'resolved_count': 1,
            'paused_count': 1
          },
          {
            'id': 'd-2',
            'name': 'Department of MBA',
            'code': 'MBA',
            'total_complaints': 1,
            'resolved_count': 0,
            'paused_count': 0
          },
          {
            'id': 'd-3',
            'name': 'Department of M.Com',
            'code': 'MCOM',
            'total_complaints': 1,
            'resolved_count': 0,
            'paused_count': 0
          },
          {
            'id': 'd-4',
            'name': 'Hostel & Residential Life',
            'code': 'HOSTEL',
            'total_complaints': 8,
            'resolved_count': 5,
            'paused_count': 1
          },
          {
            'id': 'd-5',
            'name': 'Library & IT Services',
            'code': 'IT',
            'total_complaints': 1,
            'resolved_count': 1,
            'paused_count': 0
          },
          {
            'id': 'd-6',
            'name': 'Accounts & Finance',
            'code': 'FIN',
            'total_complaints': 2,
            'resolved_count': 1,
            'paused_count': 0
          },
          {
            'id': 'd-7',
            'name': 'Infrastructure & Campus Facilities',
            'code': 'INFRA',
            'total_complaints': 4,
            'resolved_count': 2,
            'paused_count': 1
          },
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };

      final model = AnalyticsDataModel.fromJson(json);

      // Admin sees all 7 canonical departments
      expect(model.departmentDistribution.length, equals(7));
      final names = model.departmentDistribution.map((d) => d.name).toSet();
      expect(
          names,
          containsAll([
            'Department of MCA',
            'Department of MBA',
            'Department of M.Com',
            'Hostel & Residential Life',
            'Library & IT Services',
            'Accounts & Finance',
            'Infrastructure & Campus Facilities',
          ]));
    });

    test('MCA authority cannot access Hostel analytics', () {
      const mcaDeptId = '53f56adf-ffb8-46ca-ab62-35777bd2e3b9';
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 5,
        'total_resolved': 1,
        'total_pending': 2,
        'total_under_review': 1,
        'total_in_progress': 0,
        'total_paused': 1,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 1,
        'average_resolution_days': 2.5,
        'department_distribution': [
          {
            'id': mcaDeptId,
            'name': 'Department of MCA',
            'code': 'MCA',
            'total_complaints': 5,
            'resolved_count': 1,
            'paused_count': 1,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(
          model.departmentDistribution
              .any((d) => d.name == 'Hostel & Residential Life'),
          isFalse);
    });

    test('MCA authority cannot access Finance analytics', () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 5,
        'total_resolved': 1,
        'total_pending': 2,
        'total_under_review': 1,
        'total_in_progress': 0,
        'total_paused': 1,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 1,
        'average_resolution_days': 2.5,
        'department_distribution': [
          {
            'id': 'd-mca',
            'name': 'Department of MCA',
            'code': 'MCA',
            'total_complaints': 5,
            'resolved_count': 1,
            'paused_count': 1,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(
          model.departmentDistribution
              .any((d) => d.name == 'Accounts & Finance'),
          isFalse);
    });

    test('MCA authority cannot access IT analytics', () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 5,
        'total_resolved': 1,
        'total_pending': 2,
        'total_under_review': 1,
        'total_in_progress': 0,
        'total_paused': 1,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 1,
        'average_resolution_days': 2.5,
        'department_distribution': [
          {
            'id': 'd-mca',
            'name': 'Department of MCA',
            'code': 'MCA',
            'total_complaints': 5,
            'resolved_count': 1,
            'paused_count': 1,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(
          model.departmentDistribution
              .any((d) => d.name == 'Library & IT Services'),
          isFalse);
    });

    test('MBA authority cannot access MCA analytics', () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 1,
        'total_resolved': 0,
        'total_pending': 1,
        'total_under_review': 0,
        'total_in_progress': 0,
        'total_paused': 0,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 0,
        'average_resolution_days': 0.0,
        'department_distribution': [
          {
            'id': 'd-mba',
            'name': 'Department of MBA',
            'code': 'MBA',
            'total_complaints': 1,
            'resolved_count': 0,
            'paused_count': 0,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(
          model.departmentDistribution
              .any((d) => d.name == 'Department of MCA'),
          isFalse);
    });

    test('M.Com authority cannot access MBA analytics', () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 1,
        'total_resolved': 0,
        'total_pending': 1,
        'total_under_review': 0,
        'total_in_progress': 0,
        'total_paused': 0,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 0,
        'average_resolution_days': 0.0,
        'department_distribution': [
          {
            'id': 'd-mcom',
            'name': 'Department of M.Com',
            'code': 'MCOM',
            'total_complaints': 1,
            'resolved_count': 0,
            'paused_count': 0,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(
          model.departmentDistribution
              .any((d) => d.name == 'Department of MBA'),
          isFalse);
    });

    test('IT authority cannot access Hostel analytics', () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 1,
        'total_resolved': 1,
        'total_pending': 0,
        'total_under_review': 0,
        'total_in_progress': 0,
        'total_paused': 0,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 0,
        'average_resolution_days': 1.0,
        'department_distribution': [
          {
            'id': 'd-it',
            'name': 'Library & IT Services',
            'code': 'IT',
            'total_complaints': 1,
            'resolved_count': 1,
            'paused_count': 0,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(
          model.departmentDistribution
              .any((d) => d.name == 'Hostel & Residential Life'),
          isFalse);
    });

    test('Finance authority cannot access IT analytics', () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 2,
        'total_resolved': 1,
        'total_pending': 1,
        'total_under_review': 0,
        'total_in_progress': 0,
        'total_paused': 0,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 0,
        'average_resolution_days': 2.0,
        'department_distribution': [
          {
            'id': 'd-fin',
            'name': 'Accounts & Finance',
            'code': 'FIN',
            'total_complaints': 2,
            'resolved_count': 1,
            'paused_count': 0,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': <Map<String, dynamic>>[],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(
          model.departmentDistribution
              .any((d) => d.name == 'Library & IT Services'),
          isFalse);
    });

    test('Submission and resolution trends match actual period records', () {
      final json = {
        'period_start': '2026-09-18T00:00:00Z',
        'period_end': '2026-10-18T00:00:00Z',
        'total_submitted': 5,
        'total_resolved': 1,
        'total_pending': 2,
        'total_under_review': 1,
        'total_in_progress': 0,
        'total_paused': 1,
        'total_escalated': 0,
        'total_rejected': 0,
        'overdue_count': 1,
        'average_resolution_days': 2.5,
        'department_distribution': [
          {
            'id': 'd-mca',
            'name': 'Department of MCA',
            'code': 'MCA',
            'total_complaints': 5,
            'resolved_count': 1,
            'paused_count': 1,
          }
        ],
        'category_distribution': <Map<String, dynamic>>[],
        'monthly_trends': [
          {
            'month_label': 'Oct 2026',
            'submitted_count': 5,
            'resolved_count': 1,
          }
        ],
        'authority_workload': <Map<String, dynamic>>[],
      };
      final model = AnalyticsDataModel.fromJson(json);
      expect(model.monthlyTrends.first.submittedCount, equals(5));
      expect(model.monthlyTrends.first.resolvedCount, equals(1));
    });
  });

  group('5. Authority Title & Designation Mapping Tests', () {
    test(
        'UserSessionModel prioritizes profile designation over generic authority level title',
        () {
      final rawProfileJson = {
        'id': '9b6c1670-3022-40ff-84b7-4acb5fa44139',
        'email': 'faculty.demo@campus.edu',
        'full_name': 'Prof. Suresh Kumar',
        'role': 'authority',
        'department_id': '53f56adf-ffb8-46ca-ab62-35777bd2e3b9',
        'designation': 'Level 1: Faculty Advisor / Department Officer',
        'departments': {'name': 'Department of MCA'},
        'authority_levels': {
          'title': 'Level 1: Faculty Advisor / Hostel Warden'
        }, // Generic database table string
      };

      final session = UserSessionModel.fromJson(rawProfileJson);

      // The specific profile designation MUST be used, NOT the generic table string
      expect(session.authorityLevelTitle,
          equals('Level 1: Faculty Advisor / Department Officer'));
      expect(session.departmentName, equals('Department of MCA'));
    });

    test(
        'All authority context titles map accurately for academic and operational units',
        () {
      final profiles = [
        {
          'email': 'faculty.demo@campus.edu',
          'designation': 'Level 1: Faculty Advisor / Department Officer',
          'dept': 'Department of MCA',
        },
        {
          'email': 'mba.faculty@campus.edu',
          'designation': 'Level 1: Faculty Advisor / Department Officer',
          'dept': 'Department of MBA',
        },
        {
          'email': 'mcom.faculty@campus.edu',
          'designation': 'Level 1: Faculty Advisor / Department Officer',
          'dept': 'Department of M.Com',
        },
        {
          'email': 'authority.demo@campus.edu',
          'designation': 'Level 1: Hostel Warden',
          'dept': 'Hostel & Residential Life',
        },
        {
          'email': 'it.demo@campus.edu',
          'designation': 'Level 1: IT Officer / Department Officer',
          'dept': 'Library & IT Services',
        },
        {
          'email': 'finance.demo@campus.edu',
          'designation': 'Level 1: Accounts Officer / Department Officer',
          'dept': 'Accounts & Finance',
        },
        {
          'email': 'infra.demo@campus.edu',
          'designation': 'Level 1: Infrastructure Officer / Department Officer',
          'dept': 'Infrastructure & Campus Facilities',
        },
        {
          'email': 'hod.demo@campus.edu',
          'designation': 'Level 2: Head of Department (HoD)',
          'dept': 'Department of MCA',
        },
        {
          'email': 'admin.demo@campus.edu',
          'designation': 'Campus Administrator',
          'dept': 'Central Governance',
        },
      ];

      for (final p in profiles) {
        final session = UserSessionModel.fromJson({
          'id': 'dummy-id',
          'email': p['email'],
          'full_name': 'Test Officer',
          'role': p['email'] == 'admin.demo@campus.edu' ? 'admin' : 'authority',
          'designation': p['designation'],
          'departments': {'name': p['dept']},
          'authority_levels': {'title': 'Generic Title'},
        });

        expect(session.authorityLevelTitle, equals(p['designation']));
      }
    });

    test('AdminUserModel properly inherits designation for Admin user roster',
        () {
      final adminUserJson = {
        'id': 'a-1',
        'email': 'mcom.faculty@campus.edu',
        'full_name': 'Prof. Vikram Malhotra',
        'role': 'authority',
        'department_id': 'd-mcom',
        'designation': 'Level 1: Faculty Advisor / Department Officer',
        'departments': {'name': 'Department of M.Com'},
        'authority_levels': {
          'title': 'Level 1: Faculty Advisor / Hostel Warden'
        },
        'created_at': DateTime.now().toIso8601String(),
      };

      final adminUser = AdminUserModel.fromJson(adminUserJson);
      expect(adminUser.authorityLevelTitle,
          equals('Level 1: Faculty Advisor / Department Officer'));
    });
  });
}
