import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_theme.dart';
import 'package:smartify/features/admin/models/admin_user_model.dart';
import 'package:smartify/features/admin/models/audit_log_model.dart';
import 'package:smartify/features/admin/providers/admin_management_provider.dart';
import 'package:smartify/features/admin/screens/tier_sla_screen.dart';
import 'package:smartify/features/admin/services/admin_service.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';
import 'package:smartify/features/escalation/providers/escalation_provider.dart';
import 'package:smartify/features/escalation/services/escalation_service.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

class MockAdminService extends AdminService {
  final List<AuthorityTierModel> tiers;
  MockAdminService({required this.tiers});

  @override
  Future<List<AdminUserModel>> fetchProfiles() async {
    return [];
  }

  @override
  Future<List<AuditLogModel>> fetchAuditLogs(
      {int limit = 50, String? actionFilter}) async {
    return [];
  }

  @override
  Future<List<AuthorityTierModel>> fetchAuthorityLevels() async {
    return tiers;
  }

  @override
  Future<bool> updateAuthoritySla({
    required String levelId,
    required int newSlaDays,
  }) async {
    return true;
  }
}

class MockEscalationService extends EscalationService {
  @override
  Future<List<GrievanceModel>> fetchCutoffPausedComplaints() async {
    return [];
  }
}

void main() {
  final canonicalTiers = [
    const AuthorityTierModel(
      id: 'lvl-1',
      levelNumber: 1,
      title: 'Level 1: Faculty / Department Officer',
      slaDays: 3,
    ),
    const AuthorityTierModel(
      id: 'lvl-2',
      levelNumber: 2,
      title: 'Level 2: Head of Department (HoD)',
      slaDays: 4,
    ),
    const AuthorityTierModel(
      id: 'lvl-3',
      levelNumber: 3,
      title: 'Level 3: Dean / Academic Dean',
      slaDays: 5,
    ),
    const AuthorityTierModel(
      id: 'lvl-4',
      levelNumber: 4,
      title: 'Level 4: Higher Authority / Arbitration Board',
      slaDays: 5,
    ),
  ];

  Widget buildTestScreen({
    required AdminManagementProvider adminProv,
    required EscalationProvider escProv,
    Size screenSize = const Size(360, 800),
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AdminManagementProvider>.value(value: adminProv),
        ChangeNotifierProvider<EscalationProvider>.value(value: escProv),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(size: screenSize),
          child: const TierSlaScreen(),
        ),
      ),
    );
  }

  group('TierSlaScreen Mobile Layout & Semantic Correctness Tests', () {
    testWidgets(
        '1. Renders header, institutional policy banner, and explanation',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final adminService = MockAdminService(tiers: canonicalTiers);
      final adminProv = AdminManagementProvider(service: adminService);
      final escProv = EscalationProvider(service: MockEscalationService());
      await adminProv.loadAdminData();

      await tester.pumpWidget(buildTestScreen(
        adminProv: adminProv,
        escProv: escProv,
      ));
      await tester.pumpAndSettle();

      // Header
      expect(find.text('Tier SLA Policies'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Institutional Policy Card
      expect(find.text('Institutional Forwarding Policies'), findsOneWidget);
      expect(
        find.textContaining('Defines how long each authority tier has to act'),
        findsOneWidget,
      );

      // Explanations present
      expect(find.textContaining('Action window:'), findsOneWidget);
      expect(find.textContaining('Manual forwarding:'), findsOneWidget);
      expect(find.textContaining('SLA escalation:'), findsOneWidget);
      expect(find.textContaining('20-day cutoff:'), findsOneWidget);
    });

    testWidgets(
        '2. Displays all 4 canonical tiers with proper action windows and escalation targets',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final adminService = MockAdminService(tiers: canonicalTiers);
      final adminProv = AdminManagementProvider(service: adminService);
      final escProv = EscalationProvider(service: MockEscalationService());
      await adminProv.loadAdminData();

      await tester.pumpWidget(buildTestScreen(
        adminProv: adminProv,
        escProv: escProv,
      ));
      await tester.scrollUntilVisible(find.text('LEVEL 1'), 100);
      await tester.pumpAndSettle();

      // Badges
      expect(find.text('LEVEL 1'), findsOneWidget);
      expect(find.text('LEVEL 2'), findsOneWidget);

      // Clean Role Titles (Not duplicated like Level 1: Level 1...)
      expect(find.text('Faculty / Department Officer'), findsOneWidget);
      expect(find.text('Head of Department (HoD)'), findsOneWidget);

      // Action Windows
      expect(find.text('3 calendar days'), findsOneWidget);
      expect(find.text('4 calendar days'), findsOneWidget);

      // Escalation paths
      expect(find.text('Forward to Level 2 (HoD)'), findsOneWidget);
      expect(find.text('Forward to Level 3 (Dean / Grievance Cell)'),
          findsOneWidget);

      // Scroll down to view Level 3 & Level 4
      await tester.scrollUntilVisible(find.text('LEVEL 4'), 150);
      await tester.pumpAndSettle();

      expect(find.text('LEVEL 3'), findsOneWidget);
      expect(find.text('LEVEL 4'), findsOneWidget);
      expect(find.text('Dean / Grievance Cell'), findsOneWidget);
      expect(find.text('Higher Authority / Grievance Board'), findsOneWidget);
      expect(
          find.text('Forward to Level 4 (Arbitration Board)'), findsOneWidget);
      expect(find.text('Final tier / governance review'), findsOneWidget);
    });

    testWidgets(
        '3. Displays 20-Day Governance Cutoff card with navigation button',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final adminService = MockAdminService(tiers: canonicalTiers);
      final adminProv = AdminManagementProvider(service: adminService);
      final escProv = EscalationProvider(service: MockEscalationService());
      await adminProv.loadAdminData();

      await tester.pumpWidget(buildTestScreen(
        adminProv: adminProv,
        escProv: escProv,
      ));
      await tester.pumpAndSettle();

      // Scroll to bottom to ensure the 20-day cutoff card is visible in ListView
      await tester.scrollUntilVisible(
          find.text('20-Day Governance Cutoff'), 200);
      await tester.pumpAndSettle();

      expect(find.text('20-Day Governance Cutoff'), findsOneWidget);
      expect(
        find.textContaining(
            'Automated escalation/progression is frozen when a grievance reaches the institutional 20-day cutoff.'),
        findsOneWidget,
      );
      expect(find.text('View Escalation Center'), findsOneWidget);
    });

    testWidgets(
        '4. Responsive test across 360dp, 390dp, and 412dp viewports without overflow',
        (tester) async {
      final viewports = [
        const Size(360, 800), // OPPO A53 / budget Android
        const Size(390, 844), // Standard modern device
        const Size(412, 915), // Pixel / Flagship Android
      ];

      for (final vp in viewports) {
        tester.view.physicalSize = vp;
        tester.view.devicePixelRatio = 1.0;

        final adminService = MockAdminService(tiers: canonicalTiers);
        final adminProv = AdminManagementProvider(service: adminService);
        final escProv = EscalationProvider(service: MockEscalationService());
        await adminProv.loadAdminData();

        await tester.pumpWidget(buildTestScreen(
          adminProv: adminProv,
          escProv: escProv,
          screenSize: vp,
        ));
        await tester.pumpAndSettle();

        // No overflow error triggered
        expect(tester.takeException(), isNull);
        expect(find.text('Tier SLA Policies'), findsOneWidget);

        await tester.scrollUntilVisible(find.text('LEVEL 1'), 100);
        await tester.pumpAndSettle();
        expect(find.text('LEVEL 1'), findsOneWidget);
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets(
        '5. Edit Policy opens modal dialog, allows stepper changes, and shows confirmation',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final adminService = MockAdminService(tiers: canonicalTiers);
      final adminProv = AdminManagementProvider(service: adminService);
      final escProv = EscalationProvider(service: MockEscalationService());
      await adminProv.loadAdminData();

      await tester.pumpWidget(buildTestScreen(
        adminProv: adminProv,
        escProv: escProv,
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Edit Policy'), 100);
      await tester.pumpAndSettle();

      // Tap "Edit Policy" on the first card (Level 1)
      final editButtons = find.text('Edit Policy');
      expect(editButtons, findsWidgets);
      await tester.tap(editButtons.first);
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Action Window'), findsOneWidget);
      expect(find.text('Save Policy'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // current SLA

      // Tap + button to increment to 4
      final addButton = find.byIcon(Icons.add);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);

      // Tap "Save Policy"
      await tester.tap(find.text('Save Policy'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Confirm SLA Policy Update'), findsOneWidget);
      expect(
        find.textContaining(
            'Update Level 1 (Faculty / Department Officer) SLA from 3 days to 4 calendar days?'),
        findsOneWidget,
      );

      // Confirm update
      await tester.tap(find.text('Confirm Update'));
      await tester.pumpAndSettle();

      // Success SnackBar should be displayed
      expect(
          find.text('Level 1 SLA updated to 4 calendar days.'), findsOneWidget);
    });
  });
}
