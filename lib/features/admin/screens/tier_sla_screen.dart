import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/providers/admin_management_provider.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';
import 'package:smartify/features/escalation/screens/admin_cutoff_review_screen.dart';

/// SMARTIFY Tier SLA Configuration Screen
/// Dedicated administrator view for managing calendar-day forwarding policies
/// across institutional tiers (L1 -> L2 -> L3 -> L4).
class TierSlaScreen extends StatefulWidget {
  const TierSlaScreen({super.key});

  @override
  State<TierSlaScreen> createState() => _TierSlaScreenState();
}

class _TierSlaScreenState extends State<TierSlaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final prov = context.read<AdminManagementProvider>();
        if (prov.authorityLevels.isEmpty) {
          prov.loadAdminData();
        }
      }
    });
  }

  /// Extracts canonical role title cleanly without duplicate "Level X:" prefixes.
  String _getRoleTitle(AuthorityTierModel tier) {
    final raw = tier.title.trim();
    final prefix = RegExp(r'^Level\s*\d+\s*[:\-]\s*', caseSensitive: false);
    final clean =
        prefix.hasMatch(raw) ? raw.replaceFirst(prefix, '').trim() : raw;

    if (tier.levelNumber == 1 &&
        (clean.isEmpty || clean.toLowerCase().contains('faculty'))) {
      return 'Faculty / Department Officer';
    }
    if (tier.levelNumber == 2 &&
        (clean.isEmpty || clean.toLowerCase().contains('head'))) {
      return 'Head of Department (HoD)';
    }
    if (tier.levelNumber == 3 &&
        (clean.isEmpty || clean.toLowerCase().contains('dean'))) {
      return 'Dean / Grievance Cell';
    }
    if (tier.levelNumber == 4 &&
        (clean.isEmpty ||
            clean.toLowerCase().contains('arbitration') ||
            clean.toLowerCase().contains('board'))) {
      return 'Higher Authority / Grievance Board';
    }
    return clean.isNotEmpty ? clean : 'Authority Tier ${tier.levelNumber}';
  }

  /// Resolves institutional escalation target for each hierarchy level.
  String _getEscalationDestination(int levelNumber) {
    switch (levelNumber) {
      case 1:
        return 'Forward to Level 2 (HoD)';
      case 2:
        return 'Forward to Level 3 (Dean / Grievance Cell)';
      case 3:
        return 'Forward to Level 4 (Arbitration Board)';
      case 4:
      default:
        return 'Final tier / governance review';
    }
  }

  /// Displays a responsive modal dialog for configuring SLA calendar days.
  void _showSlaEditDialog(AuthorityTierModel tier) {
    final roleName = _getRoleTitle(tier);
    int days = tier.slaDays;
    final nextEscalation = _getEscalationDestination(tier.levelNumber);

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    'LEVEL ${tier.levelNumber}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onPrimaryContainer,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  roleName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Action Window',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Maximum calendar time for this tier to take required action before escalation eligibility.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space16,
                        vertical: AppSpacing.space12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: days > 1
                                  ? () => setDialogState(() => days--)
                                  : null,
                            ),
                            const SizedBox(width: AppSpacing.space16),
                            Text(
                              '$days',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.space16),
                            IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: days < 14
                                  ? () => setDialogState(() => days++)
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          days == 1 ? 'Calendar Day' : 'Calendar Days',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  const Text(
                    'Escalation Destination',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space12,
                        vertical: AppSpacing.space10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.25),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tier.levelNumber < 4
                              ? Icons.trending_up
                              : Icons.verified_user_outlined,
                          size: 16,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: AppSpacing.space8),
                        Expanded(
                          child: Text(
                            nextEscalation,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (days <= 0 || days > 14) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Action window must be between 1 and 14 days.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(dialogCtx).pop();
                  _confirmAndSaveSla(tier, days);
                },
                child: const Text('Save Policy'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Confirms SLA change with user before committing update.
  Future<void> _confirmAndSaveSla(AuthorityTierModel tier, int newDays) async {
    if (newDays == tier.slaDays) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No change made to SLA policy.')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        ),
        title: const Text(
          'Confirm SLA Policy Update',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'Update Level ${tier.levelNumber} (${_getRoleTitle(tier)}) SLA from ${tier.slaDays} days to $newDays calendar days?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Update'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await context.read<AdminManagementProvider>().updateSla(
            levelId: tier.id,
            newSlaDays: newDays,
          );
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Level ${tier.levelNumber} SLA updated to $newDays calendar days.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<AdminManagementProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Tier SLA Policies',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: prov.loadAdminData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: theme.colorScheme.outline.withValues(alpha: 0.25),
            height: 1,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: prov.loadAdminData,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.space16),
            children: [
              // Explanatory Information Card
              _buildInstitutionalPolicyCard(theme),
              const SizedBox(height: AppSpacing.space16),

              if (prov.successMessage != null) ...[
                FeedbackBanner(
                  message: prov.successMessage!,
                  isError: false,
                ),
                const SizedBox(height: AppSpacing.space12),
              ],

              if (prov.errorMessage != null) ...[
                FeedbackBanner(
                  message: prov.errorMessage!,
                  isError: true,
                  onRetry: prov.loadAdminData,
                ),
                const SizedBox(height: AppSpacing.space12),
              ],

              // Section Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Authority Hierarchy Policies',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  if (!prov.isLoading && prov.authorityLevels.isNotEmpty)
                    Text(
                      '${prov.authorityLevels.length} tiers configured',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space12),

              // SLA Policy Cards
              if (prov.isLoading)
                const StateLoadingShimmer(height: 280)
              else if (prov.authorityLevels.isEmpty)
                const StateEmptyView(
                  title: 'No Policies Found',
                  subtitle:
                      'Institutional authority tiers have not been initialized.',
                )
              else
                ...prov.authorityLevels.map(
                  (tier) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space12),
                    child: _buildTierPolicyCard(tier, theme),
                  ),
                ),

              const SizedBox(height: AppSpacing.space8),

              // 20-Day Governance Cutoff Safeguard Card
              _buildCutoffGovernanceCard(theme),

              const SizedBox(height: AppSpacing.space24),
            ],
          ),
        ),
      ),
    );
  }

  /// Informational Card explaining Action window, Manual forwarding, SLA escalation, and 20-day cutoff.
  Widget _buildInstitutionalPolicyCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                  child: Icon(
                    Icons.policy_outlined,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.space12),
                const Expanded(
                  child: Text(
                    'Institutional Forwarding Policies',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space10),
            Text(
              'Defines how long each authority tier has to act before a grievance becomes eligible for escalation.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: AppSpacing.space12),
            Container(
              padding: const EdgeInsets.all(AppSpacing.space12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPolicyPrinciple(
                    icon: Icons.timer_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: 'Action window',
                    description:
                        'The maximum configured calendar time for the current authority tier to take the required grievance action before escalation becomes eligible.',
                    theme: theme,
                  ),
                  const SizedBox(height: AppSpacing.space10),
                  _buildPolicyPrinciple(
                    icon: Icons.forward_to_inbox_outlined,
                    iconColor: theme.colorScheme.secondary,
                    title: 'Manual forwarding',
                    description:
                        'Current authority determines that higher-level review is required and forwards immediately.',
                    theme: theme,
                  ),
                  const SizedBox(height: AppSpacing.space10),
                  _buildPolicyPrinciple(
                    icon: Icons.trending_up,
                    iconColor: AppColors.statusEscalated,
                    title: 'SLA escalation',
                    description:
                        'The configured action window expires without the required action and the grievance becomes eligible for escalation according to institutional policy.',
                    theme: theme,
                  ),
                  const SizedBox(height: AppSpacing.space10),
                  _buildPolicyPrinciple(
                    icon: Icons.lock_clock_outlined,
                    iconColor: AppColors.statusCutoffPaused,
                    title: '20-day cutoff',
                    description:
                        'Once the grievance reaches the 20-day governance cutoff, automated progression is frozen and the case enters the Admin Escalation Center for governance review.',
                    theme: theme,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyPrinciple({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required ThemeData theme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: AppSpacing.space8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Vertically stacked mobile-friendly card for each tier policy.
  Widget _buildTierPolicyCard(AuthorityTierModel tier, ThemeData theme) {
    final roleTitle = _getRoleTitle(tier);
    final escalationTarget = _getEscalationDestination(tier.levelNumber);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Level Badge & Edit Policy Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    'LEVEL ${tier.levelNumber}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onPrimaryContainer,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space10, vertical: 0),
                    minimumSize: const Size(0, 32),
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                  ),
                  onPressed: () => _showSlaEditDialog(tier),
                  icon: Icon(Icons.edit_outlined,
                      size: 14, color: theme.colorScheme.primary),
                  label: Text(
                    'Edit Policy',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space12),

            // Role Title (Full Width — Never Squeezed)
            Text(
              roleTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: theme.colorScheme.onSurface,
              ),
              softWrap: true,
            ),
            const SizedBox(height: AppSpacing.space12),

            // Inner Details Box: Action Window & Escalation Target
            Container(
              padding: const EdgeInsets.all(AppSpacing.space12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: AppSpacing.space10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Action window',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${tier.slaDays} calendar days',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space10),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: AppSpacing.space10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        tier.levelNumber < 4
                            ? Icons.trending_up
                            : Icons.verified_user_outlined,
                        size: 18,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: AppSpacing.space10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Escalation',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              escalationTarget,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dedicated 20-Day Governance Cutoff Information Card with link to Escalation Center.
  Widget _buildCutoffGovernanceCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        side: BorderSide(
          color: AppColors.statusCutoffPaused.withValues(alpha: 0.35),
        ),
      ),
      color: AppColors.statusCutoffPaused.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space8),
                  decoration: BoxDecoration(
                    color: AppColors.statusCutoffPaused.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                  child: const Icon(
                    Icons.lock_clock_outlined,
                    color: AppColors.statusCutoffPaused,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.space12),
                const Expanded(
                  child: Text(
                    '20-Day Governance Cutoff',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.statusCutoffPaused,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space10),
            Text(
              'Automated escalation/progression is frozen when a grievance reaches the institutional 20-day cutoff. Governance authorization is required to resume progression.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: AppSpacing.space12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusCutoffPaused,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.space12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminCutoffReviewScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: const Text(
                  'View Escalation Center',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
