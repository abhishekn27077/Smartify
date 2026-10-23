import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/sla_countdown_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/authority/providers/authority_workflow_provider.dart';
import 'package:smartify/features/authority/utils/authority_workflow_permissions.dart';
import 'package:smartify/features/authority/widgets/authority_action_dialog.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Authority Personal Caseload Screen ("My Cases")
/// Dedicated screen answering: "What cases am I personally responsible for?"
/// Segmented into Active Caseload, Department Intake Pool, Recently Resolved, and Recently Rejected.
class AuthorityMyCasesScreen extends StatefulWidget {
  const AuthorityMyCasesScreen({super.key});

  @override
  State<AuthorityMyCasesScreen> createState() => _AuthorityMyCasesScreenState();
}

class _AuthorityMyCasesScreenState extends State<AuthorityMyCasesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthorityWorkflowProvider>().loadQueue();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final currentUserId = user?.id ?? '';
    final prov = context.watch<AuthorityWorkflowProvider>();

    // Filter queue to cases assigned specifically to this authority
    final myCases = prov.queue.where((g) {
      final isMine = g.assignedAuthorityId == currentUserId;
      if (!isMine) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return g.title.toLowerCase().contains(q) ||
          g.trackingNumber.toLowerCase().contains(q) ||
          (g.studentName?.toLowerCase().contains(q) ?? false);
    }).toList();

    final activeCases = myCases
        .where((g) =>
            !g.status.isTerminal && g.status != ComplaintStatus.cutoffPaused)
        .toList();
    final resolvedCases =
        myCases.where((g) => g.status == ComplaintStatus.resolved).toList();
    final rejectedCases =
        myCases.where((g) => g.status == ComplaintStatus.rejected).toList();

    // Filter queue to unassigned department/tier intake cases awaiting authority pickup
    final intakeCases = prov.queue.where((g) {
      final isUnassignedAtMyTier = g.assignedAuthorityId == null;
      if (!isUnassignedAtMyTier ||
          g.status.isTerminal ||
          g.status == ComplaintStatus.cutoffPaused) {
        return false;
      }
      if (user?.departmentId != null &&
          g.departmentId.isNotEmpty &&
          user!.departmentId != g.departmentId) {
        return false;
      }
      if (user?.authorityLevelNumber != null &&
          g.currentAuthorityLevelNumber != user!.authorityLevelNumber) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return g.title.toLowerCase().contains(q) ||
          g.trackingNumber.toLowerCase().contains(q) ||
          (g.studentName?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assigned Cases',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Cases',
            onPressed: prov.loadQueue,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.6),
                tabs: [
                  Tab(text: 'Active (${activeCases.length})'),
                  Tab(text: 'Intake Pool (${intakeCases.length})'),
                  Tab(text: 'Resolved (${resolvedCases.length})'),
                  Tab(text: 'Rejected (${rejectedCases.length})'),
                ],
              ),
              Container(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                height: 1,
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                  AppSpacing.space12, AppSpacing.space16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search my cases by ID, student, or title...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Tab Views
            Expanded(
              child: prov.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.space16),
                      child: StateLoadingShimmer(height: 250),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildActiveTab(
                            activeCases, intakeCases, theme, currentUserId),
                        _buildCaseList(
                          intakeCases,
                          'No Cases in Intake Pool',
                          'All department grievances currently have assigned authorities.',
                          currentUserId: currentUserId,
                          isIntakePool: true,
                        ),
                        _buildCaseList(
                          resolvedCases,
                          'No Resolved Cases',
                          'Grievances you resolve will be archived here for reference.',
                          currentUserId: currentUserId,
                        ),
                        _buildCaseList(
                          rejectedCases,
                          'No Rejected Cases',
                          'Grievances closed with formal rejection reasons will appear here.',
                          currentUserId: currentUserId,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab(List<GrievanceModel> activeCases,
      List<GrievanceModel> intakeCases, ThemeData theme, String currentUserId) {
    if (activeCases.isEmpty) {
      if (intakeCases.isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.inbox_rounded,
                      color: AppColors.primary, size: 40),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Direct Active Cases',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'You have no assigned active cases, but there are ${intakeCases.length} department case(s) waiting in the Intake Pool.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                  label: Text('View Intake Pool (${intakeCases.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                  ),
                  onPressed: () => _tabController.animateTo(1),
                ),
              ],
            ),
          ),
        );
      }
      return const StateEmptyView(
        title: 'No Active Personal Cases',
        subtitle:
            'You do not have any active grievances assigned to your direct caseload.',
        icon: Icons.assignment_turned_in_outlined,
      );
    }

    return Column(
      children: [
        if (intakeCases.isNotEmpty)
          InkWell(
            onTap: () => _tabController.animateTo(1),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${intakeCases.length} unassigned case(s) waiting in Intake Pool',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.primary),
                ],
              ),
            ),
          ),
        Expanded(
          child: _buildCaseList(
            activeCases,
            'No Active Personal Cases',
            'You do not have any active grievances assigned to your direct caseload.',
            currentUserId: currentUserId,
          ),
        ),
      ],
    );
  }

  Widget _buildCaseList(
    List<GrievanceModel> list,
    String emptyTitle,
    String emptySubtitle, {
    required String currentUserId,
    bool isIntakePool = false,
  }) {
    if (list.isEmpty) {
      return StateEmptyView(
        title: emptyTitle,
        subtitle: emptySubtitle,
        icon: Icons.assignment_turned_in_outlined,
      );
    }

    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: context.read<AuthorityWorkflowProvider>().loadQueue,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.space16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space12),
        itemBuilder: (context, index) {
          final grievance = list[index];
          final auth = context.watch<AuthProvider>();
          final canAct = AuthorityWorkflowPermissions.canAct(
            user: auth.currentUser,
            grievance: grievance,
          );
          final isAccepted = AuthorityWorkflowPermissions.isCaseAccepted(
            user: auth.currentUser,
            grievance: grievance,
          );
          return Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Tracking ID + Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        grievance.trackingNumber,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      GrievanceStatusBadge(
                          status: grievance.status, isCompact: true),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Title
                  Text(
                    grievance.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // Student & Department Info
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(
                        (grievance.studentName != null &&
                                grievance.studentName!.trim().isNotEmpty)
                            ? grievance.studentName!
                            : 'Student information unavailable',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('•',
                          style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${grievance.departmentName} (${grievance.category})',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Received & SLA
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Received: ${AppDateTimeUtils.formatLocalDateTime(grievance.createdAt)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      SlaCountdownBadge(grievance: grievance),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSmall),
                          ),
                        ),
                        onPressed: () {
                          context
                              .read<StudentTrackingProvider>()
                              .selectComplaint(grievance);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ComplaintDetailScreen(grievance: grievance),
                            ),
                          );
                        },
                        child: const Text('Details',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      if (canAct) ...[
                        const SizedBox(width: 8),
                        if (!isAccepted) ...[
                          ElevatedButton.icon(
                            icon:
                                const Icon(Icons.how_to_reg_rounded, size: 14),
                            label: const Text('ACCEPT CASE',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                              ),
                            ),
                            onPressed: () {
                              context
                                  .read<AuthorityWorkflowProvider>()
                                  .selectComplaint(grievance);
                              AuthorityActionDialog.show(
                                context,
                                grievance,
                                initialAction: TriageActionType.claim,
                              );
                            },
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            icon: const Icon(Icons.gavel_rounded, size: 14),
                            label: const Text('Process Case',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: theme.colorScheme.secondary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSmall),
                              ),
                            ),
                            onPressed: () {
                              context
                                  .read<AuthorityWorkflowProvider>()
                                  .selectComplaint(grievance);
                              AuthorityActionDialog.show(context, grievance);
                            },
                          ),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
