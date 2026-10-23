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

/// SMARTIFY Admin All Grievances Screen
/// Comprehensive campus-wide case browser with department scoping and status filters.
class AdminAllComplaintsScreen extends StatefulWidget {
  const AdminAllComplaintsScreen({super.key});

  @override
  State<AdminAllComplaintsScreen> createState() =>
      _AdminAllComplaintsScreenState();
}

class _AdminAllComplaintsScreenState extends State<AdminAllComplaintsScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _searchController = TextEditingController();

  List<GrievanceModel> _complaints = [];
  List<DepartmentModel> _departments = [];
  String? _selectedDeptId;
  String _selectedStatus = 'ALL';
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _adminService.fetchComplaints(
          departmentId: _selectedDeptId,
          statusFilter: _selectedStatus == 'ALL' ? null : _selectedStatus,
          searchQuery: _searchQuery,
        ),
        _adminService.fetchDepartments(),
      ]);

      if (mounted) {
        final list = results[0] as List<GrievanceModel>;
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        setState(() {
          _complaints = list;
          _departments = results[1] as List<DepartmentModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load grievances: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Campus Grievances',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
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
                  _loadData();
                },
                decoration: InputDecoration(
                  hintText: 'Search by ID, title, student, or department...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _loadData();
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),

            // Department Selector Dropdown & Status Chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Department: ',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSmall),
                        border: Border.all(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedDeptId,
                          isDense: true,
                          isExpanded: true,
                          hint: const Text('All Departments',
                              style: TextStyle(fontSize: 12)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Departments',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            ..._departments.map(
                              (d) => DropdownMenuItem<String?>(
                                value: d.id,
                                child: Text(d.name,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedDeptId = val);
                            _loadData();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
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
            const Divider(height: 1),

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
                          onRetry: _loadData,
                        )
                      : _complaints.isEmpty
                          ? const StateEmptyView(
                              title: 'No Grievances Found',
                              subtitle:
                                  'No complaints match the selected filter criteria.',
                              icon: Icons.inbox_outlined,
                            )
                          : RefreshIndicator(
                              onRefresh: _loadData,
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
        onSelected: (_) {
          setState(() => _selectedStatus = status);
          _loadData();
        },
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
                      '${grievance.departmentName} (${grievance.category})',
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
