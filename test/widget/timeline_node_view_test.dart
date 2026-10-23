import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/theme/app_theme.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';
import 'package:smartify/features/tracking/widgets/timeline_node_view.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  group('TimelineNodeView Visual Semantics and Actor Label Tests', () {
    final testTime = DateTime.parse('2026-10-18T16:04:11.834Z');

    testWidgets(
        '1. Student submission displays "Submitted by:" and student program, NOT "Reviewed by:"',
        (tester) async {
      final submissionEvent = TimelineEventModel(
        id: 'ev-1',
        complaintId: 'c-1',
        newStatus: ComplaintStatus.pending,
        eventType: 'SUBMITTED',
        changedByName: 'Rohan Verma',
        changedByRole: 'student',
        actorDesignation: 'MBA Student',
        changedByDept: 'Department of MBA',
        remarks: 'Grievance registered and placed in Intake Queue.',
        isSystemEvent: false,
        createdAt: testTime,
      );

      await tester.pumpWidget(buildTestableWidget(
        TimelineNodeView(event: submissionEvent),
      ));
      await tester.pumpAndSettle();

      // Must display "SUBMITTED"
      expect(find.text('SUBMITTED'), findsOneWidget);

      // Must display "Submitted by:"
      expect(find.text('Submitted by:'), findsOneWidget);

      // Must NOT display "Reviewed by:"
      expect(find.text('Reviewed by:'), findsNothing);

      // Must display student name, program, and department
      expect(find.text('Rohan Verma'), findsOneWidget);
      expect(find.text('MBA Student'), findsOneWidget);
      expect(find.text('Department of MBA'), findsOneWidget);

      // Remarks
      expect(find.text('Grievance registered and placed in Intake Queue.'),
          findsOneWidget);
    });

    testWidgets(
        '2. Under Review displays "Reviewed by:", real authority name and Level 1 designation',
        (tester) async {
      final reviewEvent = TimelineEventModel(
        id: 'ev-2',
        complaintId: 'c-1',
        oldStatus: ComplaintStatus.pending,
        newStatus: ComplaintStatus.underReview,
        eventType: 'UNDER_REVIEW',
        changedByName: 'Dr. Amit Trivedi',
        changedByRole: 'authority',
        actorDesignation: 'Level 1 — Faculty Advisor / Department Officer',
        changedByDept: 'Department of MBA',
        remarks: 'It will be updated soon',
        isSystemEvent: false,
        createdAt: testTime.add(const Duration(minutes: 2)),
      );

      await tester.pumpWidget(buildTestableWidget(
        TimelineNodeView(event: reviewEvent),
      ));
      await tester.pumpAndSettle();

      expect(find.text('UNDER REVIEW'), findsOneWidget);
      expect(find.text('Reviewed by:'), findsOneWidget);
      expect(find.text('Dr. Amit Trivedi'), findsOneWidget);
      expect(find.text('Level 1 — Faculty Advisor / Department Officer'),
          findsOneWidget);
      expect(find.text('Department of MBA'), findsOneWidget);
      expect(find.text('Remarks:'), findsOneWidget);
      expect(find.text('It will be updated soon'), findsOneWidget);

      // Never Unknown User
      expect(find.textContaining('Unknown User'), findsNothing);
    });

    testWidgets(
        '3. Resolved displays "Resolved by:", real authority, and "Resolution:" label',
        (tester) async {
      final resolveEvent = TimelineEventModel(
        id: 'ev-3',
        complaintId: 'c-1',
        oldStatus: ComplaintStatus.underReview,
        newStatus: ComplaintStatus.resolved,
        eventType: 'RESOLVED',
        changedByName: 'Dr. Amit Trivedi',
        changedByRole: 'authority',
        actorDesignation: 'Level 1 — Faculty Advisor / Department Officer',
        changedByDept: 'Department of MBA',
        remarks: 'Internal marks released. Verification complete.',
        isSystemEvent: false,
        createdAt: testTime.add(const Duration(minutes: 3)),
      );

      await tester.pumpWidget(buildTestableWidget(
        TimelineNodeView(event: resolveEvent),
      ));
      await tester.pumpAndSettle();

      expect(find.text('RESOLVED'), findsOneWidget);
      expect(find.text('Resolved by:'), findsOneWidget);
      expect(find.text('Dr. Amit Trivedi'), findsOneWidget);
      expect(find.text('Level 1 — Faculty Advisor / Department Officer'),
          findsOneWidget);
      expect(find.text('Resolution:'), findsOneWidget);
      expect(find.text('Internal marks released. Verification complete.'),
          findsOneWidget);
    });

    testWidgets('4. Forwarded displays "Forwarded by:" and "Forwarded to:"',
        (tester) async {
      final forwardEvent = TimelineEventModel(
        id: 'ev-4',
        complaintId: 'c-1',
        oldStatus: ComplaintStatus.underReview,
        newStatus: ComplaintStatus.escalated,
        eventType: 'FORWARDED',
        changedByName: 'Dr. Amit Trivedi',
        changedByRole: 'authority',
        actorDesignation: 'Level 1 — Faculty Advisor / Department Officer',
        changedByDept: 'Department of MBA',
        assignedToTier: 'Level 2 — Head of Department (HoD)',
        assignedToName: 'Dr. Neha Gupta',
        remarks: 'Referred to HoD for departmental committee approval.',
        isSystemEvent: false,
        createdAt: testTime.add(const Duration(minutes: 4)),
      );

      await tester.pumpWidget(buildTestableWidget(
        TimelineNodeView(event: forwardEvent),
      ));
      await tester.pumpAndSettle();

      expect(find.text('FORWARDED TO LEVEL 2 — HEAD OF DEPARTMENT (HOD)'),
          findsOneWidget);
      expect(find.text('Forwarded by:'), findsOneWidget);
      expect(find.text('Dr. Amit Trivedi'), findsOneWidget);
      expect(
          find.textContaining(
              'Forwarded to: Level 2 — Head of Department (HoD) — Dr. Neha Gupta'),
          findsOneWidget);
      expect(find.text('Reason:'), findsOneWidget);
    });

    testWidgets(
        '5. Automated escalation displays "AUTOMATED ESCALATION" and "System Redressal Engine (AUTOMATED)"',
        (tester) async {
      final autoEvent = TimelineEventModel(
        id: 'ev-5',
        complaintId: 'c-1',
        newStatus: ComplaintStatus.escalated,
        eventType: 'SYSTEM_ESCALATION',
        isSystemEvent: true,
        remarks: 'Auto-forwarded due to SLA expiration.',
        createdAt: testTime.add(const Duration(days: 3)),
      );

      await tester.pumpWidget(buildTestableWidget(
        TimelineNodeView(event: autoEvent),
      ));
      await tester.pumpAndSettle();

      expect(find.text('AUTOMATED ESCALATION'), findsOneWidget);
      expect(find.text('By:'), findsOneWidget);
      expect(find.text('System Redressal Engine (AUTOMATED)'), findsOneWidget);
    });
  });
}
