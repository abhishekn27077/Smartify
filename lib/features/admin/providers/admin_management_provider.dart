import 'package:flutter/material.dart';
import 'package:smartify/features/admin/models/admin_user_model.dart';
import 'package:smartify/features/admin/models/audit_log_model.dart';
import 'package:smartify/features/admin/services/admin_service.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';

/// SMARTIFY Admin Governance & Role Management Provider
class AdminManagementProvider extends ChangeNotifier {
  final AdminService _service;

  AdminManagementProvider({AdminService? service})
      : _service = service ?? AdminService();

  List<AdminUserModel> _profiles = [];
  List<AuditLogModel> _auditLogs = [];
  List<AuthorityTierModel> _authorityLevels = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;
  String? _selectedActionFilter;

  List<AdminUserModel> get profiles => _profiles;
  List<AuditLogModel> get auditLogs => _auditLogs;
  List<AuthorityTierModel> get authorityLevels => _authorityLevels;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  String? get selectedActionFilter => _selectedActionFilter;

  Future<void> loadAdminData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.fetchProfiles(),
        _service.fetchAuditLogs(actionFilter: _selectedActionFilter),
        _service.fetchAuthorityLevels(),
      ]);

      _profiles = results[0] as List<AdminUserModel>;
      _auditLogs = results[1] as List<AuditLogModel>;
      _authorityLevels = results[2] as List<AuthorityTierModel>;
    } catch (e) {
      _errorMessage = 'Failed to load administrative governance data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUserRole({
    required String targetUserId,
    required String newRole,
    String? departmentId,
    String? authorityLevelId,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ok = await _service.updateUserRole(
        targetUserId: targetUserId,
        newRole: newRole,
        departmentId: departmentId,
        authorityLevelId: authorityLevelId,
      );

      if (ok) {
        _successMessage = 'User role updated successfully.';
        final idx = _profiles.indexWhere((p) => p.id == targetUserId);
        if (idx != -1) {
          _profiles[idx] = _profiles[idx].copyWith(
            role: newRole,
            departmentId: departmentId,
            authorityLevelId: authorityLevelId,
          );
        }
      }
      return ok;
    } catch (e) {
      _errorMessage = 'Role update failed: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateSla(
      {required String levelId, required int newSlaDays}) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ok = await _service.updateAuthoritySla(
          levelId: levelId, newSlaDays: newSlaDays);
      if (ok) {
        _successMessage = 'Tier SLA updated successfully.';
        await loadAdminData();
      }
      return ok;
    } catch (e) {
      _errorMessage = 'SLA update failed: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void filterAuditLogs(String? action) {
    if (_selectedActionFilter == action) return;
    _selectedActionFilter = action;
    loadAdminData();
  }
}
