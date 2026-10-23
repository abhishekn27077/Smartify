import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/sla_countdown_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/services/admin_service.dart';
import 'package:smartify/features/complaints/models/department_model.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Department Grievances Screen
/// Lists grievances strictly belonging to the specified department with search,
/// status filtering, and detail navigation.
class DepartmentGrievancesScreen extends StatefulWidget {
  final DepartmentModel department;

  const DepartmentGrievancesScreen({super.key, required this.department});

  @override
  State<DepartmentGrievancesScreen> createState() =>
      _DepartmentGrievancesScreenState();
}

class _DepartmentGrievancesScreenState
    extends State<DepartmentGrievancesScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _searchController = TextEditingController();

  List<GrievanceModel> _complaints = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedStatus = 'ALL';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadComplaints() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _adminService.fetchComplaints(
        departmentId: widget.department.id,
        statusFilter: _selectedStatus == 'ALL' ? null : _selectedStatus,
        searchQuery: _searchQuery,
      );

      if (mounted) {
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        setState(() {
          _complaints = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load complaints: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _getConciseTitle(String code, String name) {
    final upper = code.toUpperCase().trim();
    if (upper == 'MCA') return 'MCA';
    if (upper == 'MBA') return 'MBA';
    if (upper == 'MCOM' || upper == 'M.COM') return 'M.Com';
    if (upper == 'HOSTEL') return 'Hostel';
    if (upper == 'INFRA') return 'Facilities';
    if (upper == 'FIN' || upper == 'ACCOUNTS') return 'Finance';
    if (upper == 'IT' || upper == 'LIBRARY') return 'Library & IT';
    if (name.startsWith('Department of ')) {
      return name.replaceFirst('Department of ', '');
    }
    return code;
  }

  void _onStatusSelected(String status) {
    if (_selectedStatus == status) return;
    setState(() => _selectedStatus = status);
    _loadComplaints();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dept = widget.department;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_getConciseTitle(dept.code, dept.name)} Grievances',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadComplaints,
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
            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                  AppSpacing.space12, AppSpacing.space16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  _searchQuery = val;
                  _loadComplaints();
                },
                decoration: InputDecoration(
                  hintText: 'Search by ID, title, or student...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _loadComplaints();
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),

            // Status Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
              child: Row(
                children: [
                  _buildChip('ALL', 'All'),
                  _buildChip('PENDING', 'Pending'),
                  _buildChip('UNDER_REVIEW', 'Under Review'),
                  _buildChip('RESOLVED', 'Resolved'),
                  _buildChip('REJECTED', 'Rejected'),
                  _buildChip('ESCALATED', 'Escalated'),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.space16),
                      child: StateLoadingShimmer(height: 250),
                    )
                  : _errorMessage != null
                      ? StateErrorView(
                          message: _errorMessage!,
                          onRetry: _loadComplaints,
                        )
                      : _complaints.isEmpty
                          ? StateEmptyView(
                              title: 'No Grievances Found',
                              subtitle:
                                  'No grievances found for ${dept.name} matching the active criteria.',
                              icon: Icons.inbox_outlined,
                            )
                          : RefreshIndicator(
                              onRefresh: _loadComplaints,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.all(AppSpacing.space16),
                                itemCount: _complaints.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.space12),
                                itemBuilder: (context, index) {
                                  final g = _complaints[index];
                                  return _buildGrievanceCard(g, theme);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String status, String label) {
    final isSelected = _selectedStatus == status;
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
        onSelected: (_) => _onStatusSelected(status),
      ),
    );
  }

  Widget _buildGrievanceCard(GrievanceModel grievance, ThemeData theme) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        side:
            BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        onTap: () {
          context.read<StudentTrackingProvider>().selectComplaint(grievance);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComplaintDetailScreen(grievance: grievance),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Text(
                grievance.title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 13,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Text(
                    (grievance.studentName != null &&
                            grievance.studentName!.trim().isNotEmpty)
                        ? grievance.studentName!
                        : 'Student information unavailable',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.85),
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
                      grievance.category,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Logged: ${AppDateTimeUtils.formatLocalDateTime(grievance.createdAt)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  SlaCountdownBadge(grievance: grievance),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
