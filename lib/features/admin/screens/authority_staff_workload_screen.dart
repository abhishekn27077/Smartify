import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/grievance_status_badge.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/admin/models/admin_user_model.dart';
import 'package:smartify/features/admin/services/admin_service.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';
import 'package:smartify/features/complaints/models/department_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';

/// SMARTIFY Authority Staff Workload Screen
/// Dedicated administrator view of all authority officers, their active caseloads,
/// resolution metrics, and case assignments. Deduplicated by user ID.
class AuthorityStaffWorkloadScreen extends StatefulWidget {
  final String? departmentId;
  final String? departmentName;

  const AuthorityStaffWorkloadScreen({
    super.key,
    this.departmentId,
    this.departmentName,
  });

  @override
  State<AuthorityStaffWorkloadScreen> createState() =>
      _AuthorityStaffWorkloadScreenState();
}

class _AuthorityStaffWorkloadScreenState
    extends State<AuthorityStaffWorkloadScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _searchController = TextEditingController();

  List<AdminUserModel> _authorities = [];
  List<GrievanceModel> _complaints = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadStaffWorkload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStaffWorkload() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _adminService.fetchProfiles(),
        _adminService.fetchComplaints(departmentId: widget.departmentId),
      ]);

      final allProfiles = results[0] as List<AdminUserModel>;
      final allComplaints = results[1] as List<GrievanceModel>;

      // Deduplicate authority and admin profiles by ID
      final seenIds = <String>{};
      final uniqueStaff = <AdminUserModel>[];

      for (final p in allProfiles) {
        if (!seenIds.contains(p.id)) {
          if (widget.departmentId != null) {
            // Department-specific staff: ONLY include authority officers assigned to this specific department
            if (p.role != 'authority' || p.departmentId != widget.departmentId) {
              continue;
            }
          } else {
            // Campus-wide staff directory: Include all authority officers and campus administrators
            if (p.role != 'authority' && p.role != 'admin') {
              continue;
            }
          }
          seenIds.add(p.id);
          uniqueStaff.add(p);
        }
      }

      // Sort deterministically by authority tier (L1 -> L2 -> L3) then name
      uniqueStaff.sort((a, b) {
        final lvlA = a.authorityLevelNumber ?? 99;
        final lvlB = b.authorityLevelNumber ?? 99;
        if (lvlA != lvlB) return lvlA.compareTo(lvlB);
        return a.fullName.compareTo(b.fullName);
      });

      if (mounted) {
        setState(() {
          _authorities = uniqueStaff;
          _complaints = allComplaints;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load authority staff workload: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showAddStaffDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    bool isActive = true;
    bool isSubmitting = false;

    // Load active departments and authority levels
    List<DepartmentModel> departments = [];
    List<AuthorityTierModel> levels = [];
    try {
      final results = await Future.wait([
        _adminService.fetchDepartments(),
        _adminService.fetchAuthorityLevels(),
      ]);
      departments = (results[0] as List<DepartmentModel>)
          .where((d) => d.isActive)
          .toList();
      levels = results[1] as List<AuthorityTierModel>;
    } catch (e) {
      debugPrint('Error prefetching departments/levels: $e');
    }

    String? selectedDeptId = widget.departmentId ??
        (departments.isNotEmpty ? departments.first.id : null);
    String? selectedLevelId =
        levels.isNotEmpty ? levels.first.id : null;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_add_rounded, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Add Authority Staff',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 16, color: AppColors.primary),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Role is strictly locked to AUTHORITY. Staff will receive cases matching their assigned department and tier.',
                                  style: TextStyle(fontSize: 11, color: AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full Name *',
                            hintText: 'e.g. Prof. R. Sharma',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter full legal name.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Institutional Email *',
                            hintText: 'staff@campus.edu',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter institutional email.';
                            }
                            if (!v.contains('@') || !v.contains('.')) {
                              return 'Please enter a valid campus email.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: pwdCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Temporary Password *',
                            hintText: 'Minimum 6 characters',
                          ),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'Password must be at least 6 characters.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedDeptId,
                          decoration: const InputDecoration(
                            labelText: 'Assigned Department *',
                          ),
                          items: departments
                              .map((d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text('${d.name} (${d.code})',
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedDeptId = val);
                            }
                          },
                          validator: (v) =>
                              v == null ? 'Please select a department.' : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedLevelId,
                          decoration: const InputDecoration(
                            labelText: 'Authority Tier Level *',
                          ),
                          items: levels
                              .where((l) => l.levelNumber <= 3)
                              .map((l) => DropdownMenuItem(
                                    value: l.id,
                                    child: Text('Level ${l.levelNumber}: ${l.title}',
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedLevelId = val);
                            }
                          },
                          validator: (v) =>
                              v == null ? 'Please select an authority tier.' : null,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Account Active',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Authorized to access queue and act on grievances',
                              style: TextStyle(fontSize: 11)),
                          value: isActive,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDialogState(() => isActive = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSubmitting ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSubmitting = true);

                          try {
                            await _adminService.createAuthorityStaff(
                              email: emailCtrl.text.trim(),
                              password: pwdCtrl.text,
                              fullName: nameCtrl.text.trim(),
                              departmentId: selectedDeptId!,
                              authorityLevelId: selectedLevelId!,
                              isActive: isActive,
                            );

                            if (dialogCtx.mounted) {
                              Navigator.of(dialogCtx).pop();
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Authority staff account created successfully!'),
                                  backgroundColor: AppColors.primary,
                                ),
                              );
                              unawaited(_loadStaffWorkload());
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Staff creation failed: $e'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('CREATE STAFF'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAuthorityDetail(
      AdminUserModel staff, List<GrievanceModel> assigned) {
    final theme = Theme.of(context);
    final active = assigned
        .where((g) =>
            !g.status.isTerminal && g.status != ComplaintStatus.cutoffPaused)
        .length;
    final pending =
        assigned.where((g) => g.status == ComplaintStatus.pending).length;
    final underReview = assigned
        .where((g) =>
            g.status == ComplaintStatus.underReview ||
            g.status == ComplaintStatus.inProgress)
        .length;
    final resolved =
        assigned.where((g) => g.status == ComplaintStatus.resolved).length;
    final total = assigned.length;
    final rate =
        total > 0 ? ((resolved / total) * 100).toStringAsFixed(1) : '0.0';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(AppSpacing.space20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusMedium)),
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
                    backgroundColor: theme.colorScheme.secondary,
                    child: Text(
                      staff.fullName.isNotEmpty
                          ? staff.fullName[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: Colors.white,
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
                staff.fullName,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                '${staff.authorityLevelTitle ?? "Central Officer"} • ${staff.departmentName ?? "Central Governance"}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.secondary,
                ),
              ),
              Text(
                staff.email,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: staff.isActive
                          ? AppColors.statusResolved.withValues(alpha: 0.15)
                          : AppColors.statusRejected.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                    child: Text(
                      staff.isActive ? 'ACCOUNT ACTIVE' : 'ACCOUNT INACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: staff.isActive
                            ? AppColors.statusResolved
                            : AppColors.statusRejected,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: Icon(
                      staff.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                      size: 14,
                      color: staff.isActive ? AppColors.error : AppColors.statusResolved,
                    ),
                    label: Text(
                      staff.isActive ? 'Deactivate' : 'Activate',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: staff.isActive ? AppColors.error : AppColors.statusResolved,
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await _adminService.toggleStaffActive(
                          targetUserId: staff.id,
                          isActive: !staff.isActive,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Staff status updated to ${!staff.isActive ? "Active" : "Inactive"}.'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                          unawaited(_loadStaffWorkload());
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update status: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space16),

              // KPI Row
              Container(
                padding: const EdgeInsets.all(AppSpacing.space12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildKpiMini('$active', 'Active Cases', AppColors.primary),
                    _buildKpiMini(
                        '$pending', 'Pending', AppColors.statusPending),
                    _buildKpiMini('$underReview', 'Under Review',
                        AppColors.statusUnderReview),
                    _buildKpiMini(
                        '$resolved', 'Resolved', AppColors.statusResolved),
                    _buildKpiMini(
                        '$rate%', 'Resolution Rate', AppColors.statusResolved),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // Assigned Cases List
              Text(
                'Assigned Cases (${assigned.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              if (assigned.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'No grievances currently assigned to this officer.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                )
              else
                ...assigned.map((g) {
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                      side: BorderSide(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.4)),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(g.trackingNumber,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                              fontSize: 12)),
                      subtitle: Text(g.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      trailing: GrievanceStatusBadge(
                          status: g.status, isCompact: true),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ComplaintDetailScreen(grievance: g),
                          ),
                        );
                      },
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiMini(String count, String label, Color color) {
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
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.departmentName != null
        ? '${widget.departmentName} Staff'
        : 'Authority Staff';

    final filteredStaff = _authorities.where((staff) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return staff.fullName.toLowerCase().contains(q) ||
          staff.email.toLowerCase().contains(q) ||
          (staff.departmentName?.toLowerCase().contains(q) ?? false) ||
          (staff.authorityLevelTitle?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadStaffWorkload,
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
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search staff by name, department, or tier...',
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
                          onRetry: _loadStaffWorkload,
                        )
                      : filteredStaff.isEmpty
                          ? const StateEmptyView(
                              title: 'No Authority Staff Found',
                              subtitle:
                                  'No staff members match the current search or department scope.',
                              icon: Icons.people_outline,
                            )
                          : RefreshIndicator(
                              onRefresh: _loadStaffWorkload,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.all(AppSpacing.space16),
                                itemCount: filteredStaff.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.space12),
                                itemBuilder: (context, index) {
                                  final staff = filteredStaff[index];
                                  final assigned = _complaints
                                      .where((g) =>
                                          g.assignedAuthorityId == staff.id)
                                      .toList();
                                  final active = assigned
                                      .where((g) =>
                                          !g.status.isTerminal &&
                                          g.status !=
                                              ComplaintStatus.cutoffPaused)
                                      .length;

                                  return Card(
                                    elevation: 0,
                                    margin: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusSmall),
                                      side: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.5)),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusSmall),
                                      onTap: () =>
                                          _showAuthorityDetail(staff, assigned),
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                            AppSpacing.space14),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 22,
                                              backgroundColor: theme
                                                  .colorScheme.secondary
                                                  .withValues(alpha: 0.15),
                                              child: Text(
                                                staff.fullName.isNotEmpty
                                                    ? staff.fullName[0]
                                                        .toUpperCase()
                                                    : 'A',
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme.secondary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
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
                                                    staff.fullName,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 14,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    staff.authorityLevelTitle ??
                                                        'Department Officer',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: theme
                                                          .colorScheme.primary,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    staff.departmentName ??
                                                        'Institutional Scope',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: theme
                                                          .colorScheme.onSurface
                                                          .withValues(
                                                              alpha: 0.65),
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: active > 0
                                                        ? AppColors.primary
                                                            .withValues(
                                                                alpha: 0.12)
                                                        : AppColors
                                                            .statusResolved
                                                            .withValues(
                                                                alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            AppSpacing
                                                                .radiusPill),
                                                  ),
                                                  child: Text(
                                                    '$active Active',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: active > 0
                                                          ? AppColors.primary
                                                          : AppColors
                                                              .statusResolved,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: staff.isActive
                                                        ? AppColors
                                                            .statusResolved
                                                            .withValues(
                                                                alpha: 0.1)
                                                        : AppColors
                                                            .statusRejected
                                                            .withValues(
                                                                alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            AppSpacing
                                                                .radiusSmall),
                                                  ),
                                                  child: Text(
                                                    staff.isActive
                                                        ? 'ENABLED'
                                                        : 'DISABLED',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: staff.isActive
                                                          ? AppColors
                                                              .statusResolved
                                                          : AppColors
                                                              .statusRejected,
                                                    ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStaffDialog,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Staff',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
