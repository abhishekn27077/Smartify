import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/models/admin_user_model.dart';
import 'package:smartify/features/admin/services/admin_service.dart';

/// SMARTIFY Admin Student Accounts Screen
/// Enables administrators to view and manage registered student accounts institution-wide.
class AdminStudentsScreen extends StatefulWidget {
  const AdminStudentsScreen({super.key});

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _searchController = TextEditingController();

  List<AdminUserModel> _students = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _selectedProgramFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final allProfiles = await _adminService.fetchProfiles();
      final students = allProfiles.where((p) => p.role == 'student').toList();

      if (mounted) {
        setState(() {
          _students = students;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load registered students: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showStudentDetail(AdminUserModel student) {
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        padding: const EdgeInsets.all(AppSpacing.space20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusMedium),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      student.fullName.isNotEmpty
                          ? student.fullName[0].toUpperCase()
                          : 'S',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                student.fullName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                'Student ID: ${student.registrationNumber ?? "N/A"}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.secondary,
                ),
              ),
              Text(
                student.email,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),

              // Program & Department badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                    child: Text(
                      'Program: ${student.academicProgram ?? "Unassigned"}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: student.isActive
                          ? AppColors.statusResolved.withValues(alpha: 0.15)
                          : AppColors.statusRejected.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                    child: Text(
                      student.isActive ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: student.isActive
                            ? AppColors.statusResolved
                            : AppColors.statusRejected,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Info items
              _buildDetailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Registered On',
                value: AppDateTimeUtils.formatLocalDate(student.createdAt),
                theme: theme,
              ),
              const SizedBox(height: 12),
              _buildDetailRow(
                icon: Icons.domain_outlined,
                label: 'Associated Academic Dept',
                value: student.departmentName ?? 'Department of ${student.academicProgram ?? "MCA"}',
                theme: theme,
              ),
              const SizedBox(height: 24),

              // Account Status Toggle Action
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: student.isActive ? AppColors.error : AppColors.statusResolved,
                    side: BorderSide(
                      color: student.isActive ? AppColors.error : AppColors.statusResolved,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: Icon(
                    student.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                  ),
                  label: Text(
                    student.isActive ? 'DEACTIVATE STUDENT ACCOUNT' : 'ACTIVATE STUDENT ACCOUNT',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await _adminService.toggleStaffActive(
                        targetUserId: student.id,
                        isActive: !student.isActive,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Student account updated to ${!student.isActive ? "Active" : "Inactive"}.',
                            ),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                        unawaited(_loadStudents());
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to update student status: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filteredStudents = _students.where((s) {
      if (_selectedProgramFilter != 'ALL') {
        final prog = (s.academicProgram ?? '').toUpperCase().trim();
        final filter = _selectedProgramFilter.toUpperCase().trim();
        if (filter == 'M.COM') {
          if (prog != 'M.COM' && prog != 'MCOM') return false;
        } else if (prog != filter) {
          return false;
        }
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.fullName.toLowerCase().contains(q) ||
          s.email.toLowerCase().contains(q) ||
          (s.academicProgram?.toLowerCase().contains(q) ?? false) ||
          (s.registrationNumber?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Registered Students',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadStudents,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
            height: 1,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16,
                AppSpacing.space12,
                AppSpacing.space16,
                0,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by student name, ID, or email...',
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

            // Program Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space16, vertical: 8),
              child: Row(
                children: [
                  _buildProgramChip('ALL', 'All Programs (${_students.length})'),
                  const SizedBox(width: 8),
                  _buildProgramChip('MCA', 'MCA'),
                  const SizedBox(width: 8),
                  _buildProgramChip('MBA', 'MBA'),
                  const SizedBox(width: 8),
                  _buildProgramChip('M.Com', 'M.Com'),
                ],
              ),
            ),

            // Student List
            Expanded(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.space16),
                      child: StateLoadingShimmer(height: 250),
                    )
                  : _errorMessage != null
                      ? StateErrorView(
                          message: _errorMessage!,
                          onRetry: _loadStudents,
                        )
                      : filteredStudents.isEmpty
                          ? const StateEmptyView(
                              title: 'No Students Found',
                              subtitle:
                                  'No registered student accounts match the selected filter.',
                              icon: Icons.school_outlined,
                            )
                          : RefreshIndicator(
                              onRefresh: _loadStudents,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(AppSpacing.space16),
                                itemCount: filteredStudents.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.space10),
                                itemBuilder: (context, index) {
                                  final student = filteredStudents[index];

                                  return Card(
                                    elevation: 0,
                                    margin: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusSmall),
                                      side: BorderSide(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusSmall),
                                      onTap: () => _showStudentDetail(student),
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                            AppSpacing.space12),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 20,
                                              backgroundColor: theme
                                                  .colorScheme.primary
                                                  .withValues(alpha: 0.12),
                                              child: Text(
                                                student.fullName.isNotEmpty
                                                    ? student.fullName[0]
                                                        .toUpperCase()
                                                    : 'S',
                                                style: TextStyle(
                                                  color: theme.colorScheme.primary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    student.fullName,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${student.registrationNumber ?? "No ID"} • ${student.email}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: theme
                                                          .colorScheme.onSurface
                                                          .withValues(alpha: 0.65),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: theme
                                                        .colorScheme.primary
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            AppSpacing
                                                                .radiusSmall),
                                                  ),
                                                  child: Text(
                                                    student.academicProgram ??
                                                        'MCA',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: theme
                                                          .colorScheme.primary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  student.isActive
                                                      ? 'ACTIVE'
                                                      : 'INACTIVE',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    color: student.isActive
                                                        ? AppColors
                                                            .statusResolved
                                                        : AppColors
                                                            .statusRejected,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
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

  Widget _buildProgramChip(String filterKey, String label) {
    final theme = Theme.of(context);
    final isSelected = _selectedProgramFilter == filterKey;

    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface.withValues(alpha: 0.8),
      ),
      selectedColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.outline.withValues(alpha: 0.5),
      ),
      onSelected: (_) {
        setState(() => _selectedProgramFilter = filterKey);
      },
    );
  }
}
