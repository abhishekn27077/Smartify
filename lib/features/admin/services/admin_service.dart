import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/admin/models/admin_user_model.dart';
import 'package:smartify/features/admin/models/audit_log_model.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';
import 'package:smartify/features/complaints/models/department_model.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Admin Service
/// Interfaces with Supabase administrative governance RPCs and audit trails.
class AdminService {
  final SupabaseClient? _supabaseClient;

  AdminService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _client {
    if (_supabaseClient != null) return _supabaseClient!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw StateError('Supabase client has not been initialized.');
    }
  }

  /// Fetches campus user profiles with department and authority tier info
  Future<List<AdminUserModel>> fetchProfiles() async {
    try {
      final response = await _client.from('profiles').select('''
            *,
            departments(name),
            authority_levels(level_number, title)
          ''').order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((json) => AdminUserModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load user profiles: $e');
      }
      debugPrint(
          'AdminService.fetchProfiles error: $e. Falling back to mock data.');
      return _getMockProfiles();
    }
  }

  /// Administrative role and department reassignment
  Future<bool> updateUserRole({
    required String targetUserId,
    required String newRole,
    String? departmentId,
    String? authorityLevelId,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'admin_update_profile_role',
        params: {
          'p_target_user_id': targetUserId,
          'p_new_role': newRole,
          if (departmentId != null) 'p_department_id': departmentId,
          if (authorityLevelId != null)
            'p_authority_level_id': authorityLevelId,
        },
      );
      return true;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      throw DatabaseFailure('Role reassignment failed: $e');
    }
  }

  /// Administrator creates an AUTHORITY account with verified role, department, and level
  Future<Map<String, dynamic>> createAuthorityStaff({
    required String email,
    required String password,
    required String fullName,
    required String departmentId,
    required String authorityLevelId,
    bool isActive = true,
  }) async {
    try {
      final res = await _client.rpc<dynamic>(
        'admin_create_authority_staff',
        params: {
          'p_email': email.trim().toLowerCase(),
          'p_password': password,
          'p_full_name': fullName.trim(),
          'p_department_id': departmentId,
          'p_authority_level_id': authorityLevelId,
          'p_is_active': isActive,
        },
      );
      return (res is Map<String, dynamic>)
          ? res
          : Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      if (e is DatabaseFailure) rethrow;
      throw DatabaseFailure('Failed to create authority staff: $e');
    }
  }

  /// Administrator toggles active/inactive status of an authority staff member
  Future<bool> toggleStaffActive({
    required String targetUserId,
    required bool isActive,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'admin_toggle_staff_active',
        params: {
          'p_target_user_id': targetUserId,
          'p_is_active': isActive,
        },
      );
      return true;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      if (e is DatabaseFailure) rethrow;
      throw DatabaseFailure('Failed to toggle staff status: $e');
    }
  }

  /// Fetches immutable audit logs
  Future<List<AuditLogModel>> fetchAuditLogs(
      {int limit = 50, String? actionFilter}) async {
    try {
      var query = _client.from('audit_logs').select('''
        *,
        profiles!audit_logs_actor_id_fkey(full_name)
      ''');

      if (actionFilter != null && actionFilter.isNotEmpty) {
        query = query.eq('action', actionFilter);
      }

      final response =
          await query.order('created_at', ascending: false).limit(limit);
      return (response as List<dynamic>)
          .map((json) => AuditLogModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure(e.message, code: e.code);
      }
      return _getMockAuditLogs();
    } catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load audit logs: $e');
      }
      debugPrint(
          'AdminService.fetchAuditLogs error: $e. Falling back to mock audit logs.');
      return _getMockAuditLogs();
    }
  }

  /// Fetches authority levels
  Future<List<AuthorityTierModel>> fetchAuthorityLevels() async {
    try {
      final response = await _client
          .from('authority_levels')
          .select('*')
          .order('level_number', ascending: true);
      return (response as List<dynamic>)
          .map((json) =>
              AuthorityTierModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
          'AdminService.fetchAuthorityLevels error: $e. Falling back to mock tiers.');
      return const [
        AuthorityTierModel(
            id: 'lvl-1',
            levelNumber: 1,
            title: 'Level 1: Faculty / Warden',
            slaDays: 3),
        AuthorityTierModel(
            id: 'lvl-2',
            levelNumber: 2,
            title: 'Level 2: Head of Department',
            slaDays: 4),
        AuthorityTierModel(
            id: 'lvl-3',
            levelNumber: 3,
            title: 'Level 3: Dean of Student Welfare',
            slaDays: 5),
        AuthorityTierModel(
            id: 'lvl-4',
            levelNumber: 4,
            title: 'Level 4: Arbitration Board',
            slaDays: 5),
      ];
    }
  }

  /// Updates SLA days for an authority tier
  Future<bool> updateAuthoritySla(
      {required String levelId, required int newSlaDays}) async {
    try {
      await _client.rpc<dynamic>(
        'admin_update_authority_sla',
        params: {
          'p_level_id': levelId,
          'p_new_sla_days': newSlaDays,
        },
      );
      return true;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      throw DatabaseFailure('Failed to update authority SLA: $e');
    }
  }

  /// Toggles department active state
  Future<bool> toggleDepartment(
      {required String departmentId, required bool isActive}) async {
    try {
      await _client.rpc<dynamic>(
        'admin_toggle_department',
        params: {
          'p_department_id': departmentId,
          'p_is_active': isActive,
        },
      );
      return true;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      throw DatabaseFailure('Failed to toggle department: $e');
    }
  }

  /// Fetches institutional departments from public.departments
  Future<List<DepartmentModel>> fetchDepartments() async {
    try {
      final response = await _client
          .from('departments')
          .select('*')
          .order('code', ascending: true);
      return (response as List<dynamic>)
          .map((json) => DepartmentModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('AdminService.fetchDepartments error: $e');
      return [];
    }
  }

  /// Fetches campus-wide complaints or department-specific complaints for administrators
  Future<List<GrievanceModel>> fetchComplaints({
    String? departmentId,
    String? statusFilter,
    String? searchQuery,
  }) async {
    try {
      var query = _client.from('complaints').select('''
            *,
            departments:department_id(name, code),
            authority_levels:current_authority_level_id(level_number, title, sla_days),
            authority_profile:profiles!complaints_assigned_authority_id_fkey(full_name),
            student_profile:profiles!complaints_student_id_fkey(full_name),
            complaint_attachments(file_path)
          ''');

      if (departmentId != null && departmentId.isNotEmpty) {
        query = query.eq('department_id', departmentId);
      }
      if (statusFilter != null &&
          statusFilter.isNotEmpty &&
          statusFilter != 'ALL') {
        query = query.eq('status', statusFilter);
      }

      final response = await query.order('created_at', ascending: false);
      final items = (response as List<dynamic>)
          .map((json) => GrievanceModel.fromJson(json as Map<String, dynamic>))
          .toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase();
        return items
            .where((g) =>
                g.title.toLowerCase().contains(q) ||
                g.trackingNumber.toLowerCase().contains(q) ||
                (g.studentName?.toLowerCase().contains(q) ?? false) ||
                g.departmentName.toLowerCase().contains(q))
            .toList();
      }
      return items;
    } catch (e) {
      debugPrint('AdminService.fetchComplaints error: $e');
      return [];
    }
  }

  List<AdminUserModel> _getMockProfiles() {
    final now = DateTime.now();
    return [
      AdminUserModel(
        id: 'usr-admin-1',
        email: 'admin.demo@campus.edu',
        fullName: 'Campus Administrator',
        role: 'admin',
        departmentId: null,
        departmentName: 'Central Institutional Governance',
        authorityLevelId: null,
        authorityLevelTitle: null,
        createdAt: now.subtract(const Duration(days: 100)),
      ),
      AdminUserModel(
        id: 'usr-auth-1',
        email: 'authority.demo@campus.edu',
        fullName: 'Hostel Warden',
        role: 'authority',
        departmentId: 'd-2',
        departmentName: 'Hostel & Residential Life',
        authorityLevelId: 'lvl-1',
        authorityLevelTitle: 'Level 1: Hostel Warden',
        createdAt: now.subtract(const Duration(days: 60)),
      ),
      AdminUserModel(
        id: 'usr-auth-2',
        email: 'suresh.advisor@campus.edu',
        fullName: 'Prof. Suresh Kumar',
        role: 'authority',
        departmentId: 'd-1',
        departmentName: 'Academic Affairs',
        authorityLevelId: 'lvl-1',
        authorityLevelTitle: 'Level 1: Faculty Advisor',
        createdAt: now.subtract(const Duration(days: 45)),
      ),
      AdminUserModel(
        id: 'usr-auth-3',
        email: 'academic.hod@campus.edu',
        fullName: 'Dr. K. Ramanathan (HoD)',
        role: 'authority',
        departmentId: 'd-1',
        departmentName: 'Academic Affairs',
        authorityLevelId: 'lvl-2',
        authorityLevelTitle: 'Level 2: Head of Department',
        createdAt: now.subtract(const Duration(days: 40)),
      ),
      AdminUserModel(
        id: 'usr-auth-4',
        email: 'dean.student@campus.edu',
        fullName: 'Dr. Aris Thorne (Dean)',
        role: 'authority',
        departmentId: null,
        departmentName: 'Cross-Departmental / Grievance Cell',
        authorityLevelId: 'lvl-3',
        authorityLevelTitle:
            'Level 3: Dean of Student Welfare / Grievance Cell',
        createdAt: now.subtract(const Duration(days: 35)),
      ),
      AdminUserModel(
        id: 'usr-stu-1',
        email: 'student.demo@campus.edu',
        fullName: 'Aarav Patel',
        role: 'student',
        departmentId: 'd-1',
        departmentName: 'Academic Affairs',
        authorityLevelId: null,
        authorityLevelTitle: null,
        createdAt: now.subtract(const Duration(days: 20)),
      ),
    ];
  }

  List<AuditLogModel> _getMockAuditLogs() {
    final now = DateTime.now();
    return [
      AuditLogModel(
        id: 'aud-1',
        actorId: 'usr-admin-1',
        actorName: 'Dr. Aris Thorne (Dean)',
        action: 'RESUMPTION_AUTHORIZED',
        entityType: 'complaints',
        entityId: 'c-2',
        metadata: {
          'tracking_number': 'SMT-2026-PAUSED',
          'notes':
              'Formal sign-off granted following hostel committee inspection.'
        },
        createdAt: now.subtract(const Duration(minutes: 30)),
      ),
      AuditLogModel(
        id: 'aud-2',
        actorName: 'System Automation',
        action: 'AUTOMATED_TIER_ESCALATION',
        entityType: 'complaints',
        entityId: 'c-1',
        metadata: {
          'from_level': 1,
          'to_level': 2,
          'tracking_number': 'SMT-2026-00001'
        },
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      AuditLogModel(
        id: 'aud-3',
        actorName: 'System Automation',
        action: 'CUTOFF_PAUSED',
        entityType: 'complaints',
        entityId: 'c-2',
        metadata: {'reason': '20-calendar-day cutoff limit exceeded'},
        createdAt: now.subtract(const Duration(hours: 4)),
      ),
    ];
  }
}
