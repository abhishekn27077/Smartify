import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/escalation/providers/escalation_provider.dart';
import 'package:smartify/features/escalation/widgets/admin_resume_dialog.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Admin Cutoff Review & Escalation Management Screen
/// Displays 20-day cutoff frozen grievances, manual worker trigger, and test simulation tools.
class AdminCutoffReviewScreen extends StatefulWidget {
  const AdminCutoffReviewScreen({super.key});

  @override
  State<AdminCutoffReviewScreen> createState() =>
      _AdminCutoffReviewScreenState();
}

class _AdminCutoffReviewScreenState extends State<AdminCutoffReviewScreen> {
  DateTime? _simulatedTestDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EscalationProvider>().loadPausedComplaints();
    });
  }

  void _pickSimulatedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _simulatedTestDate ?? DateTime.now().add(const Duration(days: 21)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() => _simulatedTestDate = picked);
    }
  }

  void _clearSimulation() {
    setState(() => _simulatedTestDate = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<EscalationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escalation Center',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Queue',
            onPressed: provider.loadPausedComplaints,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: theme.colorScheme.outline, height: 1),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: provider.loadPausedComplaints,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Administrative Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  decoration: BoxDecoration(
                    color: AppColors.statusCutoffPaused.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMedium),
                    border: Border.all(
                        color: AppColors.statusCutoffPaused
                            .withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.statusCutoffPaused,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSmall),
                            ),
                            child: const Icon(
                                Icons.security_update_good_rounded,
                                color: Colors.white,
                                size: 20),
                          ),
                          const SizedBox(width: AppSpacing.space12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '20-Day Cutoff Governance',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Automated escalation freezes when a complaint reaches 20 calendar days.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.space12),
                      const Divider(height: 1),
                      const SizedBox(height: AppSpacing.space12),

                      // Primary Administrative Action: Run Escalation Worker
                      FilledButton.icon(
                        icon: provider.isTriggeringWorker
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.bolt, size: 16),
                        label: Text(
                          provider.isTriggeringWorker
                              ? 'Executing Governance Worker...'
                              : 'Run Escalation Worker',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.statusCutoffPaused,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSmall),
                          ),
                        ),
                        onPressed: provider.isTriggeringWorker
                            ? null
                            : () => provider.runEscalationWorker(
                                simulatedNow: _simulatedTestDate),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Process eligible grievances using the server-side escalation rules.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),

                      if (provider.lastWorkerResult != null) ...[
                        const SizedBox(height: AppSpacing.space8),
                        Text(
                          'Last Worker Run: Paused: ${provider.lastWorkerResult!['cutoff_paused_count'] ?? 0}, Escalated: ${provider.lastWorkerResult!['escalated_count'] ?? 0}, Apex Flags: ${provider.lastWorkerResult!['apex_admin_review_count'] ?? 0}',
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.space12),

                      // Distinct Developer / QA Test Tools Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.space12),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surface.withValues(alpha: 0.6),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSmall),
                          border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.science_outlined,
                                    size: 15, color: theme.colorScheme.outline),
                                const SizedBox(width: 6),
                                Text(
                                  'Developer / QA Test Tools',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.outline,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Simulate future calendar dates to test time-based SLA breaches and cutoff freezes.',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ActionChip(
                                  avatar: Icon(
                                    _simulatedTestDate == null
                                        ? Icons.schedule
                                        : Icons.calendar_today,
                                    size: 14,
                                  ),
                                  label: Text(
                                    _simulatedTestDate == null
                                        ? 'Simulate Date'
                                        : '+${_simulatedTestDate!.difference(DateTime.now()).inDays}d test',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: _pickSimulatedDate,
                                ),
                                if (_simulatedTestDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.cancel, size: 18),
                                    tooltip: 'Clear test simulation',
                                    onPressed: _clearSimulation,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.space20),

                // 2. Queue Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Paused Complaints Queue (${provider.pausedComplaints.length})',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space12),

                // 3. Queue List / States
                if (provider.isLoading)
                  const StateLoadingShimmer(height: 240)
                else if (provider.errorMessage != null)
                  StateErrorView(
                    message: provider.errorMessage!,
                    onRetry: provider.loadPausedComplaints,
                  )
                else if (provider.pausedComplaints.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 40, horizontal: 20),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 48, color: AppColors.success),
                        const SizedBox(height: AppSpacing.space12),
                        const Text(
                          'No Frozen Grievances',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No grievances have breached the 20-day cutoff threshold without resolution.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.pausedComplaints.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.space12),
                    itemBuilder: (context, index) {
                      final item = provider.pausedComplaints[index];
                      return _buildPausedCard(context, item, theme);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPausedCard(
    BuildContext context,
    GrievanceModel item,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(
            color: AppColors.statusCutoffPaused.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.trackingNumber,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              GrievanceStatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: AppSpacing.space8),
          Text(
            item.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            item.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: AppSpacing.space12),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.space12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Student: ${(item.studentName != null && item.studentName!.trim().isNotEmpty) ? item.studentName! : "Student information unavailable"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.currentAuthorityLevelTitle,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Department: ${item.departmentName.trim().isNotEmpty ? item.departmentName : "Department unavailable"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Cutoff limit reached (20d+)',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.statusCutoffPaused,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ComplaintDetailScreen(grievance: item),
                      ),
                    );
                  },
                  child: const Text('View Timeline',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock_open, size: 14),
                  label: const Text('Authorize Resume',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusCutoffPaused,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => AdminResumeDialog.show(context, item),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
