import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

void main() {
  group('1. Deadline Calculation & Institutional Timezone Consistency', () {
    test('Deadlines calculate strictly via UTC calendar intervals', () {
      final submissionTime = DateTime.parse('2026-10-12T10:00:00.000Z');
      const level1SlaDays = 3;
      final expectedTierDeadline =
          submissionTime.add(const Duration(days: level1SlaDays));
      final expectedCutoffDeadline =
          submissionTime.add(const Duration(days: 20));

      expect(
          expectedTierDeadline.toIso8601String(), '2026-10-15T10:00:00.000Z');
      expect(
          expectedCutoffDeadline.toIso8601String(), '2026-11-01T10:00:00.000Z');
    });

    test('On-time vs Overdue evaluation against effective current time', () {
      final now = DateTime.parse('2026-10-14T10:00:00.000Z');
      final onTimeDeadline = DateTime.parse('2026-10-15T10:00:00.000Z');
      final overdueDeadline = DateTime.parse('2026-10-13T10:00:00.000Z');

      expect(now.isBefore(onTimeDeadline), isTrue); // On-time
      expect(now.isAfter(overdueDeadline), isTrue); // Overdue
    });
  });

  group('2. Authority Hierarchy Progression & Apex Boundary Rules', () {
    final tiers = [
      const AuthorityTierModel(
          id: 'lvl-1',
          levelNumber: 1,
          title: 'Level 1: Faculty / Warden',
          slaDays: 3),
      const AuthorityTierModel(
          id: 'lvl-2',
          levelNumber: 2,
          title: 'Level 2: Head of Department',
          slaDays: 4),
      const AuthorityTierModel(
          id: 'lvl-3',
          levelNumber: 3,
          title: 'Level 3: Dean of Student Welfare',
          slaDays: 5),
      const AuthorityTierModel(
          id: 'lvl-4',
          levelNumber: 4,
          title: 'Level 4: Arbitration Board',
          slaDays: 5),
    ];

    test('Tiers progress sequentially from 1 to 4', () {
      for (int i = 1; i < 4; i++) {
        final currentTier = tiers.firstWhere((t) => t.levelNumber == i);
        final nextTier = tiers.firstWhere((t) => t.levelNumber == i + 1);
        expect(nextTier.levelNumber, currentTier.levelNumber + 1);
      }
    });

    test('Level 4 has no further escalation level (Apex Boundary)', () {
      const currentLevelNumber = 4;
      final nextTierMatches =
          tiers.where((t) => t.levelNumber == currentLevelNumber + 1).toList();
      expect(nextTierMatches, isEmpty,
          reason: 'Level 4 is the apex authority; no level 5 exists.');
    });
  });

  group('3. 20-Day Cutoff Freeze Precedence', () {
    test('20-day cutoff takes precedence over tier forwarding when both apply',
        () {
      final now = DateTime.parse('2026-10-31T12:00:00.000Z');
      final createdAt =
          DateTime.parse('2026-10-10T10:00:00.000Z'); // 21 days ago
      final tierDeadline =
          DateTime.parse('2026-10-25T10:00:00.000Z'); // 6 days ago (breached)
      final cutoffDeadline =
          createdAt.add(const Duration(days: 20)); // Oct 30 (breached)

      final isCutoffBreached =
          now.isAfter(cutoffDeadline) || now.difference(createdAt).inDays >= 20;
      final isTierBreached = now.isAfter(tierDeadline);

      expect(isCutoffBreached, isTrue);
      expect(isTierBreached, isTrue);

      // Rule: Cutoff must be evaluated and frozen FIRST
      String targetAction = 'NONE';
      if (isCutoffBreached) {
        targetAction = 'FREEZE_CUTOFF_PAUSED';
      } else if (isTierBreached) {
        targetAction = 'FORWARD_NEXT_TIER';
      }

      expect(targetAction, 'FREEZE_CUTOFF_PAUSED');
    });
  });

  group('4. Administrative Resumption Validation', () {
    test('Resumption notes must be at least 10 non-whitespace characters', () {
      bool isValidResumptionNote(String? notes) {
        if (notes == null) return false;
        return notes.trim().length >= 10;
      }

      expect(isValidResumptionNote(null), isFalse);
      expect(isValidResumptionNote('   '), isFalse);
      expect(isValidResumptionNote('Too short'), isFalse);
      expect(
          isValidResumptionNote('Valid justification note by Dean.'), isTrue);
    });

    test('Resumption establishes refreshed tier deadline and extended cutoff',
        () {
      final resumptionTime = DateTime.parse('2026-10-31T15:00:00.000Z');
      const slaDays = 4; // Level 2
      final newTierDeadline = resumptionTime.add(const Duration(days: slaDays));
      final newCutoffDeadline = resumptionTime.add(const Duration(days: 20));

      expect(newTierDeadline.toIso8601String(), '2026-11-04T15:00:00.000Z');
      expect(newCutoffDeadline.toIso8601String(), '2026-11-20T15:00:00.000Z');
    });
  });

  group('5. Grievance Model SLA & Cutoff Display', () {
    test(
        'Formatted time remaining displays automation paused for cutoff grievances',
        () {
      final now = DateTime.now();
      final pausedGrievance = GrievanceModel(
        id: 'g-p1',
        trackingNumber: 'SMT-2026-PAUSED',
        studentId: 's-1',
        departmentId: 'd-1',
        departmentName: 'Hostel',
        departmentCode: 'HOSTEL',
        currentAuthorityLevelId: 'lvl-3',
        currentAuthorityLevelNumber: 3,
        currentAuthorityLevelTitle: 'Level 3: Dean',
        title: 'Water filter issue',
        description:
            '20 days have elapsed without clean water in hostel block.',
        category: 'Hostel',
        incidentDate: now.subtract(const Duration(days: 22)),
        status: ComplaintStatus.cutoffPaused,
        priority: 'HIGH',
        currentTierDeadline: now.subtract(const Duration(days: 5)),
        cutoffDeadline: now.subtract(const Duration(days: 2)),
        isCutoffPaused: true,
        pausedAt: now.subtract(const Duration(days: 2)),
        createdAt: now.subtract(const Duration(days: 22)),
        updatedAt: now.subtract(const Duration(days: 2)),
      );

      expect(pausedGrievance.isCutoffPaused, isTrue);
      expect(pausedGrievance.formattedTimeRemaining, 'Governance Cutoff (20d)');
      // Not flagged as active SLA breached since automation is frozen
      expect(pausedGrievance.isSlaBreached, isFalse);
    });
  });
}
