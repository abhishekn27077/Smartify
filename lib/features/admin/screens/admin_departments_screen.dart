import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/screens/department_dashboard_screen.dart';
import 'package:smartify/features/admin/services/admin_service.dart';
import 'package:smartify/features/complaints/models/department_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Admin Departments Screen
/// Presents Academic and Operational department cards with live grievance counts.
/// Tapping any card opens the dedicated DepartmentDashboardScreen for that department.
class AdminDepartmentsScreen extends StatefulWidget {
  const AdminDepartmentsScreen({super.key});

  @override
  State<AdminDepartmentsScreen> createState() => _AdminDepartmentsScreenState();
}

class _AdminDepartmentsScreenState extends State<AdminDepartmentsScreen> {
  final AdminService _adminService = AdminService();

  List<DepartmentModel> _departments = [];
  List<GrievanceModel> _allComplaints = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _adminService.fetchDepartments(),
        _adminService.fetchComplaints(),
      ]);

      if (mounted) {
        setState(() {
          _departments = results[0] as List<DepartmentModel>;
          _allComplaints = results[1] as List<GrievanceModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load departments: $e';
          _isLoading = false;
        });
      }
    }
  }

  bool _isAcademic(DepartmentModel dept) {
    final code = dept.code.toUpperCase();
    return code == 'MCA' || code == 'MBA' || code == 'MCOM' || code == 'ACAD';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final academicDepts = _departments.where(_isAcademic).toList();
    final operationalDepts =
        _departments.where((d) => !_isAcademic(d)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Departments',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Departments',
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
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.space16),
                child: StateLoadingShimmer(height: 300),
              )
            : _errorMessage != null
                ? StateErrorView(
                    message: _errorMessage!,
                    onRetry: _loadData,
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(AppSpacing.space16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Academic Departments Section
                          Row(
                            children: [
                              Icon(Icons.school_outlined,
                                  size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              const Text(
                                'Academic Departments',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Programs with dedicated department officers, HoD (L2) and Deans (L3)',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space12),

                          ...academicDepts
                              .map((dept) => _buildDeptCard(dept, theme)),

                          const SizedBox(height: AppSpacing.space24),

                          // Operational Departments Section
                          const Row(
                            children: [
                              Icon(Icons.business_center_outlined,
                                  size: 20, color: AppColors.secondary),
                              SizedBox(width: 8),
                              Text(
                                'Operational & Campus Facilities',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cross-cutting student services and physical campus operations',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space12),

                          ...operationalDepts
                              .map((dept) => _buildDeptCard(dept, theme)),

                          const SizedBox(height: AppSpacing.space32),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildDeptCard(DepartmentModel dept, ThemeData theme) {
    // Derive exact counts for this department from real grievances
    final deptComplaints =
        _allComplaints.where((c) => c.departmentId == dept.id).toList();

    final total = deptComplaints.length;
    final pending =
        deptComplaints.where((c) => c.status == ComplaintStatus.pending).length;
    final underReview = deptComplaints
        .where((c) =>
            c.status == ComplaintStatus.underReview ||
            c.status == ComplaintStatus.inProgress)
        .length;
    final resolved = deptComplaints
        .where((c) => c.status == ComplaintStatus.resolved)
        .length;
    final escalated = deptComplaints
        .where((c) => c.status == ComplaintStatus.escalated)
        .length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        side:
            BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DepartmentDashboardScreen(department: dept),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Name & Arrow
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isAcademic(dept)
                                ? Icons.school_rounded
                                : Icons.domain_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dept.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Code: ${dept.code}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                ],
              ),
              const SizedBox(height: AppSpacing.space12),

              // KPI Row: Total, Pending, Under Review, Resolved, Escalated
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _buildCountCol(
                          '$total', 'Total', theme.colorScheme.onSurface),
                    ),
                    _buildDivider(theme),
                    Expanded(
                      child: _buildCountCol(
                          '$pending', 'Pending', AppColors.statusPending),
                    ),
                    _buildDivider(theme),
                    Expanded(
                      child: _buildCountCol('$underReview', 'Review',
                          AppColors.statusUnderReview),
                    ),
                    _buildDivider(theme),
                    Expanded(
                      child: _buildCountCol(
                          '$resolved', 'Resolved', AppColors.statusResolved),
                    ),
                    _buildDivider(theme),
                    Expanded(
                      child: _buildCountCol(
                          '$escalated', 'Escalated', AppColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Container(
      height: 24,
      width: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.4),
    );
  }

  Widget _buildCountCol(String count, String label, Color color) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
