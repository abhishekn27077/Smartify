import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/sla_countdown_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/complaints/screens/complaint_registration_screen.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Student Complaint Tracking Screen ("My Complaints")
/// Features search, status filtering, multi-option sorting (Newest default),
/// and comprehensive case cards showing department, authority level, and SLA.
class MyComplaintsScreen extends StatefulWidget {
  const MyComplaintsScreen({super.key});

  @override
  State<MyComplaintsScreen> createState() => _MyComplaintsScreenState();
}

class _MyComplaintsScreenState extends State<MyComplaintsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _sortOption = 'NEWEST';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentTrackingProvider>().loadComplaints();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GrievanceModel> _getSortedComplaints(List<GrievanceModel> raw) {
    final list = List<GrievanceModel>.from(raw);
    if (_sortOption == 'OLDEST') {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else if (_sortOption == 'RECENT_UPDATE') {
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      // Default: NEWEST
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<StudentTrackingProvider>();
    final sortedComplaints = _getSortedComplaints(provider.complaints);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Grievances',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Register New Grievance',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const ComplaintRegistrationScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: provider.loadComplaints,
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
            // 1. Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                  AppSpacing.space12, AppSpacing.space16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: provider.setSearchQuery,
                decoration: InputDecoration(
                  hintText: 'Search by reference or title...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            provider.setSearchQuery('');
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),

            // 2. Sort Control Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space16, AppSpacing.space8, AppSpacing.space16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${sortedComplaints.length} case${sortedComplaints.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sort: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSmall),
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sortOption,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, size: 18),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'NEWEST', child: Text('Newest')),
                              DropdownMenuItem(
                                  value: 'OLDEST', child: Text('Oldest')),
                              DropdownMenuItem(
                                  value: 'RECENT_UPDATE',
                                  child: Text('Most Recent Update')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _sortOption = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. Status Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
              child: Row(
                children: [
                  _buildFilterChip('ALL', 'All', provider),
                  _buildFilterChip(
                      ComplaintStatus.pending.code, 'Pending', provider),
                  _buildFilterChip(ComplaintStatus.underReview.code,
                      'Under Review', provider),
                  _buildFilterChip(
                      ComplaintStatus.resolved.code, 'Resolved', provider),
                  _buildFilterChip(
                      ComplaintStatus.rejected.code, 'Rejected', provider),
                  _buildFilterChip(
                      ComplaintStatus.escalated.code, 'Escalated', provider),
                  const SizedBox(width: AppSpacing.space8),
                ],
              ),
            ),

            // 4. Error Banner
            if (provider.errorMessage != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.space16),
                child: FeedbackBanner(
                  message: provider.errorMessage!,
                  isError: true,
                  onRetry: provider.loadComplaints,
                ),
              ),

            // 5. Main Complaint List
            Expanded(
              child: provider.isLoading
                  ? _buildLoadingSkeleton()
                  : sortedComplaints.isEmpty
                      ? StateEmptyView(
                          title: 'No Grievances Found',
                          subtitle: provider.searchQuery.isNotEmpty ||
                                  provider.selectedStatus != 'ALL'
                              ? 'No complaints match the active filter criteria.'
                              : 'You have not registered any campus grievances yet.',
                          actionText: 'Register Grievance',
                          onAction: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const ComplaintRegistrationScreen(),
                              ),
                            );
                          },
                        )
                      : RefreshIndicator(
                          onRefresh: provider.loadComplaints,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.space16),
                            itemCount: sortedComplaints.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.space12),
                            itemBuilder: (context, index) {
                              final grievance = sortedComplaints[index];
                              return _buildComplaintCard(context, grievance);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      String status, String label, StudentTrackingProvider provider) {
    final isSelected = provider.selectedStatus == status;
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
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        onSelected: (_) => provider.setStatusFilter(status),
      ),
    );
  }

  Widget _buildComplaintCard(BuildContext context, GrievanceModel grievance) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label:
          'Grievance ${grievance.trackingNumber}, title ${grievance.title}, status ${grievance.status.label}.',
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          side: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            context.read<StudentTrackingProvider>().selectComplaint(grievance);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => ComplaintDetailScreen(grievance: grievance)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Tracking Reference & Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        grievance.trackingNumber,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GrievanceStatusBadge(
                        status: grievance.status, isCompact: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.space8),

                // Row 2: Title
                Text(
                  grievance.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.space8),

                // Row 3: Department & Current Authority Level
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_outlined,
                          size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${grievance.departmentName} • ${grievance.currentAuthorityLevelTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space12),

                const Divider(height: 1),
                const SizedBox(height: AppSpacing.space12),

                // Row 4: Last Updated & SLA Countdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Updated: ${AppDateTimeUtils.formatLocalDateTime(grievance.updatedAt)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SlaCountdownBadge(grievance: grievance),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.space16),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space12),
      itemBuilder: (_, __) => const StateLoadingShimmer(height: 140),
    );
  }
}
