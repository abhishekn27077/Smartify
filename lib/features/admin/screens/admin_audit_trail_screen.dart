import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/models/audit_log_model.dart';
import 'package:smartify/features/admin/providers/admin_management_provider.dart';

/// SMARTIFY Admin Audit Trail Screen
/// Displays immutable institutional audit records with filtering by action category.
/// Human actors display verified names; automated events display "System Redressal Engine (AUTOMATED)".
class AdminAuditTrailScreen extends StatefulWidget {
  const AdminAuditTrailScreen({super.key});

  @override
  State<AdminAuditTrailScreen> createState() => _AdminAuditTrailScreenState();
}

class _AdminAuditTrailScreenState extends State<AdminAuditTrailScreen> {
  String _selectedCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminManagementProvider>().loadAdminData();
    });
  }

  List<AuditLogModel> _filterLogs(List<AuditLogModel> logs) {
    if (_selectedCategory == 'ALL') return logs;
    return logs.where((l) {
      final act = l.action.toUpperCase();
      switch (_selectedCategory) {
        case 'AUTH':
          return act.contains('LOGIN') ||
              act.contains('AUTH') ||
              act.contains('PASSWORD');
        case 'GRIEVANCE':
          return act.contains('COMPLAINT') ||
              act.contains('STATUS') ||
              act.contains('RESOLVE') ||
              act.contains('FORWARD') ||
              act.contains('SUBMIT');
        case 'AUTHORITY':
          return act.contains('ROLE') ||
              act.contains('PROFILE') ||
              act.contains('ASSIGN');
        case 'SLA':
          return act.contains('SLA') || act.contains('DEADLINE');
        case 'CUTOFF':
          return act.contains('CUTOFF') || act.contains('RESUM');
        case 'SYSTEM':
          return l.isSystemEvent ||
              act.contains('AUTOMATED') ||
              act.contains('SYSTEM');
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<AdminManagementProvider>();

    final displayLogs = _filterLogs(prov.auditLogs);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Immutable Audit Trail',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Audit Log',
            onPressed: prov.loadAdminData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
              height: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16, vertical: AppSpacing.space10),
              child: Row(
                children: [
                  _buildChip('ALL', 'All Events'),
                  _buildChip('AUTH', 'Authentication'),
                  _buildChip('GRIEVANCE', 'Grievance Actions'),
                  _buildChip('AUTHORITY', 'Authority Changes'),
                  _buildChip('SLA', 'SLA Changes'),
                  _buildChip('CUTOFF', 'Cutoff Actions'),
                  _buildChip('SYSTEM', 'System Events'),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content List
            Expanded(
              child: prov.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.space16),
                      child: StateLoadingShimmer(height: 300),
                    )
                  : displayLogs.isEmpty
                      ? const StateEmptyView(
                          title: 'No Audit Records',
                          subtitle:
                              'No audit events match the selected category filter.',
                          icon: Icons.history_edu_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: prov.loadAdminData,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.space16),
                            itemCount: displayLogs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.space10),
                            itemBuilder: (context, i) {
                              final log = displayLogs[i];
                              final isSystem = log.isSystemEvent ||
                                  (log.actorName?.contains('System') ??
                                      false) ||
                                  (log.actorName?.contains('Automation') ??
                                      false);
                              final actorDisplayName = isSystem
                                  ? 'System Redressal Engine (AUTOMATED)'
                                  : ((log.actorName != null &&
                                          log.actorName!.isNotEmpty)
                                      ? log.actorName!
                                      : 'Campus Administrator');

                              return Card(
                                elevation: 0,
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusSmall),
                                  side: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(AppSpacing.space14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Action Badge + Timestamp
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isSystem
                                                  ? AppColors.secondary
                                                      .withValues(alpha: 0.12)
                                                  : theme.colorScheme.primary
                                                      .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppSpacing.radiusSmall),
                                            ),
                                            child: Text(
                                              log.action,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: isSystem
                                                    ? AppColors.secondary
                                                    : theme.colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            AppDateTimeUtils
                                                .formatAuditTimestamp(
                                                    log.createdAt),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Actor Info
                                      Row(
                                        children: [
                                          Icon(
                                            isSystem
                                                ? Icons.smart_toy_outlined
                                                : Icons.person_outline,
                                            size: 14,
                                            color: isSystem
                                                ? AppColors.secondary
                                                : theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Actor: ',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              actorDisplayName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: isSystem
                                                    ? AppColors.secondary
                                                    : theme
                                                        .colorScheme.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),

                                      // Target Entity
                                      if (log.entityType.isNotEmpty) ...[
                                        Text(
                                          'Target: ${log.entityType} ${log.entityId != null ? "(${log.entityId!.substring(0, log.entityId!.length > 12 ? 12 : log.entityId!.length)}...)" : ""}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],

                                      // Metadata description / details
                                      if (log.metadata.isNotEmpty) ...[
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.3),
                                            borderRadius: BorderRadius.circular(
                                                AppSpacing.radiusSmall),
                                          ),
                                          child: Text(
                                            log.metadata.toString(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.75),
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String category, String label) {
    final isSelected = _selectedCategory == category;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: theme.colorScheme.primaryContainer,
        labelStyle: TextStyle(
          color: isSelected
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurface,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        onSelected: (_) => setState(() => _selectedCategory = category),
      ),
    );
  }
}
