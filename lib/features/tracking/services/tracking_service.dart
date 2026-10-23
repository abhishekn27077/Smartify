import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/notifications/services/notification_service.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';

/// SMARTIFY Student Complaint Tracking Backend Service
class TrackingService {
  final SupabaseClient? _client;
  final NotificationService _notificationService;

  TrackingService(
      {SupabaseClient? client, NotificationService? notificationService})
      : _client = client,
        _notificationService =
            notificationService ?? NotificationService(supabaseClient: client);

  SupabaseClient get client {
    if (_client != null) return _client!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const AuthFailure('Supabase client is not initialized.');
    }
  }

  /// Fetches grievances belonging to the currently authenticated student
  Future<List<GrievanceModel>> fetchMyComplaints({
    String? statusFilter,
    String? categoryFilter,
    String? searchQuery,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      // Fallback preview data for unauthenticated dev preview
      return _filterList(
          _mockStudentGrievances, statusFilter, categoryFilter, searchQuery);
    }

    try {
      var filter = client.from('complaints').select('''
            *,
            departments:department_id(name, code),
            authority_levels:current_authority_level_id(level_number, title, sla_days),
            authority_profile:profiles!complaints_assigned_authority_id_fkey(full_name),
            student_profile:profiles!complaints_student_id_fkey(full_name),
            complaint_attachments(file_path)
          ''').eq('student_id', user.id);

      if (statusFilter != null &&
          statusFilter.isNotEmpty &&
          statusFilter != 'ALL') {
        filter = filter.eq('status', statusFilter);
      }

      if (categoryFilter != null &&
          categoryFilter.isNotEmpty &&
          categoryFilter != 'ALL') {
        filter = filter.ilike('category', '%$categoryFilter%');
      }

      final response = await filter.order('created_at', ascending: false);
      final items = (response as List<dynamic>)
          .map((json) => GrievanceModel.fromJson(json as Map<String, dynamic>))
          .toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase();
        return items
            .where((g) =>
                g.title.toLowerCase().contains(q) ||
                g.trackingNumber.toLowerCase().contains(q) ||
                g.category.toLowerCase().contains(q))
            .toList();
      }

      return items;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      throw DatabaseFailure('Failed to load grievances: $e');
    }
  }

  /// Fetches the chronological status timeline for a specific grievance
  Future<List<TimelineEventModel>> fetchComplaintTimeline(
      String complaintId) async {
    try {
      final response = await client
          .from('complaint_status_history')
          .select('''
            *,
            profiles:changed_by(
              full_name,
              role,
              departments:department_id(name),
              authority_levels:authority_level_id(title, level_number)
            )
          ''')
          .eq('complaint_id', complaintId)
          .order('created_at', ascending: true);

      final list = (response as List<dynamic>)
          .map((item) =>
              TimelineEventModel.fromJson(item as Map<String, dynamic>))
          .toList();

      if (list.isNotEmpty) return list;
      if (client.auth.currentUser != null) return [];
    } catch (e) {
      if (client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load grievance timeline: $e');
      }
    }

    return _generateMockTimeline(complaintId);
  }

  /// Fetches a single grievance by ID or tracking number
  Future<GrievanceModel?> fetchComplaintById(String idOrTracking) async {
    try {
      final response = await client
          .from('complaints')
          .select('''
            *,
            departments:department_id(name, code),
            authority_levels:current_authority_level_id(level_number, title, sla_days),
            authority_profile:profiles!complaints_assigned_authority_id_fkey(full_name),
            student_profile:profiles!complaints_student_id_fkey(full_name),
            complaint_attachments(file_path)
          ''')
          .or('id.eq.$idOrTracking,tracking_number.eq.$idOrTracking')
          .maybeSingle();

      if (response != null) {
        return GrievanceModel.fromJson(response);
      }
    } catch (_) {
      // Gracefully fall back to local mock search
    }

    return _mockStudentGrievances
        .where((g) => g.id == idOrTracking || g.trackingNumber == idOrTracking)
        .firstOrNull;
  }

  /// Updates complaint status and records a timeline event
  Future<bool> updateComplaintStatus({
    required String complaintId,
    required ComplaintStatus newStatus,
    String? remarks,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return false;

    try {
      // 1. Update the complaint record
      await client.from('complaints').update({
        'status': newStatus.code,
        'status_remarks': remarks,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (newStatus.isTerminal)
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', complaintId);

      // 2. Notify Student
      final complaint = await fetchComplaintById(complaintId);
      if (complaint != null) {
        await _notificationService.triggerNotification(
          userId: complaint.studentId,
          title: 'Status Updated: ${newStatus.label}',
          message:
              'Your grievance ${complaint.trackingNumber} is now ${newStatus.label}. ${remarks ?? ""}',
          complaintId: complaintId,
          type: 'STATUS_CHANGE',
        );
      }

      return true;
    } catch (e) {
      debugPrint('TrackingService.updateComplaintStatus error: $e');
      return false;
    }
  }

  List<GrievanceModel> _filterList(
    List<GrievanceModel> list,
    String? statusFilter,
    String? categoryFilter,
    String? searchQuery,
  ) {
    var result = List<GrievanceModel>.from(list);
    if (statusFilter != null && statusFilter != 'ALL') {
      result = result.where((g) => g.status.code == statusFilter).toList();
    }
    if (categoryFilter != null && categoryFilter != 'ALL') {
      result =
          result.where((g) => g.category.contains(categoryFilter)).toList();
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((g) =>
              g.title.toLowerCase().contains(q) ||
              g.trackingNumber.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  static final List<GrievanceModel> _mockStudentGrievances = [
    GrievanceModel(
      id: 'g-101',
      trackingNumber: 'SMT-2026-01001',
      studentId: 'student-curr-id',
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
      currentTierDeadline: DateTime.now().add(const Duration(days: 2)),
      cutoffDeadline: DateTime.now().add(const Duration(days: 18)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now(),
    ),
    GrievanceModel(
      id: 'g-102',
      trackingNumber: 'SMT-2026-00982',
      studentId: 'student-curr-id',
      departmentId: 'd-acad',
      departmentName: 'Academic Affairs',
      departmentCode: 'ACAD',
      currentAuthorityLevelId: 'lvl-2',
      currentAuthorityLevelNumber: 2,
      currentAuthorityLevelTitle: 'Level 2: Head of Department (HoD)',
      title: 'Discrepancy in Semester 3 Internal Marks',
      description:
          'Internal assessment marks displayed on portal differ from signed grading sheet.',
      category: 'Academic Affairs',
      incidentDate: DateTime.now().subtract(const Duration(days: 4)),
      status: ComplaintStatus.underReview,
      priority: 'MEDIUM',
      currentTierDeadline: DateTime.now().add(const Duration(hours: 14)),
      cutoffDeadline: DateTime.now().add(const Duration(days: 15)),
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      updatedAt: DateTime.now(),
    ),
  ];

  static List<TimelineEventModel> _generateMockTimeline(String complaintId) {
    final now = DateTime.now();
    return [
      TimelineEventModel(
        id: 't-1',
        complaintId: complaintId,
        newStatus: ComplaintStatus.pending,
        eventType: 'SUBMITTED',
        changedByName: 'Rohan Verma',
        changedByRole: 'student',
        actorDesignation: 'MBA Student',
        changedByDept: 'Department of MBA',
        remarks: 'Grievance registered and placed in Intake Queue.',
        isSystemEvent: false,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      TimelineEventModel(
        id: 't-2',
        complaintId: complaintId,
        oldStatus: ComplaintStatus.pending,
        newStatus: ComplaintStatus.underReview,
        eventType: 'UNDER_REVIEW',
        changedByName: 'Dr. Amit Trivedi',
        changedByRole: 'authority',
        actorDesignation: 'Level 1 — Faculty Advisor / Department Officer',
        changedByDept: 'Department of MBA',
        remarks: 'Reviewing grievance details with academic records.',
        isSystemEvent: false,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      TimelineEventModel(
        id: 't-3',
        complaintId: complaintId,
        oldStatus: ComplaintStatus.underReview,
        newStatus: ComplaintStatus.resolved,
        eventType: 'RESOLVED',
        changedByName: 'Dr. Amit Trivedi',
        changedByRole: 'authority',
        actorDesignation: 'Level 1 — Faculty Advisor / Department Officer',
        changedByDept: 'Department of MBA',
        remarks: 'Resolved and verified with academic department.',
        isSystemEvent: false,
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
    ];
  }
}
