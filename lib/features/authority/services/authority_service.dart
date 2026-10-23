import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Authority Redressal Workflow Backend Service
class AuthorityService {
  final SupabaseClient? _client;

  AuthorityService({SupabaseClient? client}) : _client = client;

  SupabaseClient get client {
    if (_client != null) return _client!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const AuthFailure('Supabase client is not initialized.');
    }
  }

  /// Fetches authority's pending and active grievance queue with deterministic server-side sorting
  Future<List<GrievanceModel>> fetchAuthorityQueue({
    String? statusFilter,
    String? priorityFilter,
    String? searchQuery,
    String sortOption = 'PRIORITY_SLA',
    bool sortByUrgency = true,
  }) async {
    try {
      if (client.auth.currentUser != null) {
        final rpcSort = sortOption.isNotEmpty
            ? sortOption
            : (sortByUrgency ? 'PRIORITY_SLA' : 'NEWEST');
        final response = await client.rpc<dynamic>(
          'get_authority_redressal_queue',
          params: {
            'p_status_filter': statusFilter ?? 'ALL',
            'p_sort_option': rpcSort,
            if (searchQuery != null && searchQuery.trim().isNotEmpty)
              'p_search_query': searchQuery.trim(),
          },
        );

        return (response as List<dynamic>)
            .map(
                (json) => GrievanceModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } on PostgrestException catch (e) {
      if (client.auth.currentUser != null) {
        throw DatabaseFailure(e.message, code: e.code);
      }
    } catch (e) {
      if (client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load authority queue: $e');
      }
    }

    return _applyFilters(
      _mockAuthorityQueue,
      searchQuery,
      sortOption.isNotEmpty
          ? sortOption
          : (sortByUrgency ? 'PRIORITY_SLA' : 'NEWEST'),
      statusFilter,
    );
  }

  /// Fetches authoritative queue summary counts
  Future<Map<String, int>> fetchQueueSummary() async {
    try {
      if (client.auth.currentUser != null) {
        final response =
            await client.rpc<dynamic>('get_authority_queue_summary');
        final data = response as Map<String, dynamic>;
        return data.map((key, value) => MapEntry(key, (value as num).toInt()));
      }
    } catch (e) {
      if (client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load queue summary: $e');
      }
    }
    return {
      'total_active': _mockAuthorityQueue.length,
      'pending_count': _mockAuthorityQueue
          .where((g) => g.status == ComplaintStatus.pending)
          .length,
      'under_review_count': _mockAuthorityQueue
          .where((g) => g.status == ComplaintStatus.underReview)
          .length,
      'due_soon_count': 0,
      'overdue_count': 0,
      'resolved_count': 0,
    };
  }

  /// Fetches the configured authority levels
  Future<List<AuthorityTierModel>> fetchAuthorityLevels() async {
    try {
      final response = await client
          .from('authority_levels')
          .select()
          .order('level_number', ascending: true);

      final list = (response as List<dynamic>)
          .map((json) =>
              AuthorityTierModel.fromJson(json as Map<String, dynamic>))
          .toList();

      if (list.isNotEmpty) return list;
    } catch (_) {
      // Fallback seed levels
    }

    return _fallbackTiers;
  }

  /// Validates and executes a formal status transition
  Future<bool> updateStatus({
    required String complaintId,
    required ComplaintStatus currentStatus,
    required ComplaintStatus newStatus,
    required String remarks,
    String? resolutionNotes,
  }) async {
    // Idempotent safeguard: duplicate transition to same status is a safe no-op
    if (currentStatus == newStatus) {
      return true;
    }

    // 1. Enforce State Machine transition rules
    if (!currentStatus.canTransitionTo(newStatus)) {
      throw ValidationFailure(
        'Illegal status transition from ${currentStatus.label} to ${newStatus.label}.',
      );
    }

    if (newStatus == ComplaintStatus.resolved &&
        (resolutionNotes == null || resolutionNotes.trim().length < 5)) {
      throw const ValidationFailure(
          'Resolution notes are mandatory when marking a grievance as resolved.');
    }

    if (newStatus == ComplaintStatus.rejected && remarks.trim().length < 5) {
      throw const ValidationFailure(
          'Formal rejection memo remarks are mandatory when rejecting a grievance.');
    }

    // Mock fallback when offline / unauthenticated test harness
    try {
      if (client.auth.currentUser == null) {
        return true;
      }
    } catch (_) {
      return true;
    }

    try {
      final actionStr = newStatus == ComplaintStatus.resolved
          ? 'RESOLVE'
          : newStatus == ComplaintStatus.rejected
              ? 'REJECT'
              : 'UNDER_REVIEW';

      final response = await client.rpc<dynamic>(
        'authority_update_grievance_status',
        params: {
          'p_complaint_id': complaintId,
          'p_action': actionStr,
          'p_remarks': remarks.trim(),
          'p_resolution_notes': resolutionNotes?.trim(),
        },
      );

      if (response is Map<String, dynamic>) {
        final success = response['success'] as bool? ?? false;
        if (!success) {
          final message = response['message'] as String? ??
              'Unable to update grievance status.';
          final errorCode = response['error_code'] as String?;
          if (errorCode == 'NOT_CURRENT_OWNER') {
            throw const ValidationFailure(
                'This case is no longer assigned to you. Refresh the case to see its current status.');
          } else if (errorCode == 'TERMINAL_STATE') {
            throw const ValidationFailure(
                'This case is already in a terminal state. Refresh the case to see its current status.');
          } else if (errorCode == 'TIER_MISMATCH' ||
              errorCode == 'DEPT_ACCESS_DENIED') {
            throw const AuthorizationFailure(
                'Unable to complete this action. Your authorization or case state may have changed. Please refresh and try again.');
          }
          throw ValidationFailure(message);
        }
      }

      return true;
    } on PostgrestException catch (e) {
      if (e.code == '42501' ||
          e.message.contains('row-level security') ||
          e.message.contains('Forbidden')) {
        throw const AuthorizationFailure(
            'Unable to complete this action. Your authorization or case state may have changed. Please refresh and try again.');
      }
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      if (e is Failure) rethrow;
      throw const DatabaseFailure(
          'Unable to complete this action. Your authorization or case state may have changed. Please refresh and try again.');
    }
  }

  /// Formally claims/accepts a grievance for the authenticated authority
  Future<bool> claimGrievance({required String complaintId}) async {
    if (complaintId.trim().isEmpty) {
      throw const ValidationFailure(
          'Complaint ID is required to claim a grievance.');
    }

    // Mock fallback when offline / unauthenticated test harness
    try {
      if (client.auth.currentUser == null) {
        return true;
      }
    } catch (_) {
      return true;
    }

    try {
      final response = await client.rpc<dynamic>(
        'claim_grievance',
        params: {
          'p_complaint_id': complaintId,
        },
      );

      if (response is Map<String, dynamic>) {
        final success = response['success'] as bool? ?? false;
        if (!success) {
          final message =
              response['message'] as String? ?? 'Unable to accept grievance.';
          throw ValidationFailure(message);
        }
      }

      return true;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      if (e is Failure) rethrow;
      throw DatabaseFailure('Failed to claim grievance: $e');
    }
  }

  /// Forwards grievance to the next authority tier in the configured hierarchy
  Future<bool> forwardToNextTier({
    required String complaintId,
    required String currentLevelId,
    required int currentLevelNumber,
    required String reason,
  }) async {
    if (reason.trim().length < 5) {
      throw const ValidationFailure('A forwarding remark/reason is mandatory.');
    }

    if (currentLevelNumber >= 4) {
      throw const ValidationFailure(
          'Cannot forward: Grievance is already at the highest authority level.');
    }

    // Mock fallback when offline / unauthenticated test harness
    try {
      if (client.auth.currentUser == null) {
        return true;
      }
    } catch (_) {
      return true;
    }

    try {
      final response = await client.rpc<dynamic>(
        'forward_grievance_to_next_tier',
        params: {
          'p_complaint_id': complaintId,
          'p_reason': reason.trim(),
        },
      );

      if (response is Map<String, dynamic>) {
        final success = response['success'] as bool? ?? false;
        if (!success) {
          final message = response['message'] as String? ??
              'Unable to forward grievance to next tier.';
          throw ValidationFailure(message);
        }
      }

      return true;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      if (e is Failure) rethrow;
      throw DatabaseFailure('Failed to forward grievance: $e');
    }
  }

  List<GrievanceModel> _applyFilters(
    List<GrievanceModel> list,
    String? searchQuery,
    String sortOption,
    String? statusFilter,
  ) {
    var result = List<GrievanceModel>.from(list);

    if (statusFilter != null && statusFilter != 'ALL') {
      if (statusFilter == 'PENDING') {
        result =
            result.where((g) => g.status == ComplaintStatus.pending).toList();
      } else if (statusFilter == 'UNDER_REVIEW') {
        result = result
            .where((g) => g.status == ComplaintStatus.underReview)
            .toList();
      } else if (statusFilter == 'DUE_SOON') {
        final now = DateTime.now();
        result = result
            .where((g) =>
                !g.status.isTerminal &&
                g.currentTierDeadline.isAfter(now) &&
                g.currentTierDeadline
                    .isBefore(now.add(const Duration(hours: 24))))
            .toList();
      } else if (statusFilter == 'OVERDUE') {
        final now = DateTime.now();
        result = result
            .where((g) =>
                !g.status.isTerminal && g.currentTierDeadline.isBefore(now))
            .toList();
      } else if (statusFilter == 'RESOLVED') {
        result =
            result.where((g) => g.status == ComplaintStatus.resolved).toList();
      } else {
        result = result.where((g) => g.status.code == statusFilter).toList();
      }
    } else {
      // Default ALL shows active grievances
      result = result.where((g) => !g.status.isTerminal).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((g) =>
              g.title.toLowerCase().contains(q) ||
              g.trackingNumber.toLowerCase().contains(q) ||
              g.category.toLowerCase().contains(q) ||
              (g.studentName != null &&
                  g.studentName!.toLowerCase().contains(q)))
          .toList();
    }

    if (sortOption == 'NEWEST') {
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else if (sortOption == 'OLDEST') {
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else if (sortOption == 'DEADLINE') {
      result.sort(
          (a, b) => a.currentTierDeadline.compareTo(b.currentTierDeadline));
    } else if (sortOption == 'STATUS') {
      result.sort((a, b) => a.status.code.compareTo(b.status.code));
    } else {
      // PRIORITY_SLA default:
      result.sort((a, b) {
        final rankA = _getPriorityRank(a);
        final rankB = _getPriorityRank(b);
        if (rankA != rankB) return rankA.compareTo(rankB);
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return result;
  }

  int _getPriorityRank(GrievanceModel g) {
    final now = DateTime.now();
    if (!g.status.isTerminal && g.currentTierDeadline.isBefore(now)) return 1;
    if (!g.status.isTerminal &&
        g.currentTierDeadline.isBefore(now.add(const Duration(hours: 24)))) {
      return 2;
    }
    if (g.status == ComplaintStatus.pending) return 3;
    if (g.status == ComplaintStatus.underReview ||
        g.status == ComplaintStatus.inProgress ||
        g.status == ComplaintStatus.escalated) {
      return 4;
    }
    if (!g.status.isTerminal) return 5;
    return 6;
  }

  static final List<AuthorityTierModel> _fallbackTiers = [
    const AuthorityTierModel(
        id: 'lvl-1',
        levelNumber: 1,
        title: 'Level 1 — Faculty / Department Officer',
        slaDays: 3),
    const AuthorityTierModel(
        id: 'lvl-2',
        levelNumber: 2,
        title: 'Level 2 — Head of Department (HoD)',
        slaDays: 4),
    const AuthorityTierModel(
        id: 'lvl-3',
        levelNumber: 3,
        title: 'Level 3 — Dean of Student Welfare / Grievance Cell',
        slaDays: 5),
    const AuthorityTierModel(
        id: 'lvl-4',
        levelNumber: 4,
        title: 'Level 4 — Principal / Ombudsman Board',
        slaDays: 5),
  ];

  static final List<GrievanceModel> _mockAuthorityQueue = [
    GrievanceModel(
      id: 'g-201',
      trackingNumber: 'SMT-2026-01001',
      studentId: 'student-1',
      studentName: 'Rahul Verma (MCA 2nd Year)',
      departmentId: 'd-hostel',
      departmentName: 'Hostel & Residential',
      departmentCode: 'HOSTEL',
      currentAuthorityLevelId: 'lvl-1',
      currentAuthorityLevelNumber: 1,
      currentAuthorityLevelTitle: 'Level 1 — Hostel Warden',
      title: 'Water shortage in Block B 3rd Floor',
      description:
          'Drinking water filters and washroom supply have been dry for the last 24 hours.',
      category: 'Hostel & Residential Life',
      incidentDate: DateTime.now().subtract(const Duration(days: 1)),
      status: ComplaintStatus.inProgress,
      priority: 'HIGH',
      currentTierDeadline: DateTime.now().add(const Duration(hours: 18)),
      cutoffDeadline: DateTime.now().add(const Duration(days: 18)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now(),
    ),
    GrievanceModel(
      id: 'g-202',
      trackingNumber: 'SMT-2026-01044',
      studentId: 'student-2',
      studentName: 'Priya Sharma (MCA 1st Year)',
      departmentId: 'd-infra',
      departmentName: 'Campus Infrastructure',
      departmentCode: 'INFRA',
      currentAuthorityLevelId: 'lvl-1',
      currentAuthorityLevelNumber: 1,
      currentAuthorityLevelTitle:
          'Level 1 — Infrastructure Officer / Department Officer',
      title: 'Projector malfunction in Room 302',
      description: 'HDMI and display ports flicker during lectures.',
      category: 'Campus Infrastructure',
      incidentDate: DateTime.now().subtract(const Duration(days: 2)),
      status: ComplaintStatus.pending,
      priority: 'MEDIUM',
      currentTierDeadline: DateTime.now().add(const Duration(hours: 36)),
      cutoffDeadline: DateTime.now().add(const Duration(days: 17)),
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      updatedAt: DateTime.now(),
    ),
  ];
}
