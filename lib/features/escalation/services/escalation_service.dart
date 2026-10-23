import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/escalation/models/escalation_record_model.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Escalation & Cutoff Service
/// Interfaces with Supabase stored functions and escalation audit views.
class EscalationService {
  final SupabaseClient? _supabaseClient;

  EscalationService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _client {
    if (_supabaseClient != null) return _supabaseClient!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw StateError('Supabase client has not been initialized.');
    }
  }

  /// Fetches complaints currently frozen under the 20-day cutoff
  Future<List<GrievanceModel>> fetchCutoffPausedComplaints() async {
    try {
      final response = await _client
          .from('complaints')
          .select('''
            *,
            departments(name, code),
            authority_levels(level_number, title),
            student_profile:profiles!complaints_student_id_fkey(full_name),
            authority_profile:profiles!complaints_assigned_authority_id_fkey(full_name)
          ''')
          .or('status.eq.CUTOFF_PAUSED,is_cutoff_paused.eq.true')
          .order('paused_at', ascending: false);

      return (response as List<dynamic>)
          .map((json) => GrievanceModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure(e.message, code: e.code);
      }
      return _getMockPausedComplaints();
    } catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load cutoff-paused complaints: $e');
      }
      debugPrint(
          'EscalationService.fetchCutoffPausedComplaints: $e. Falling back to mock data.');
      return _getMockPausedComplaints();
    }
  }

  /// Fetches the escalation history records for a specific complaint
  Future<List<EscalationRecordModel>> fetchEscalationHistory(
      String complaintId) async {
    try {
      final response = await _client
          .from('complaint_escalations')
          .select('''
            *,
            from_level:authority_levels!complaint_escalations_from_level_id_fkey(level_number, title),
            to_level:authority_levels!complaint_escalations_to_level_id_fkey(level_number, title),
            escalated_by_profile:profiles!complaint_escalations_escalated_by_fkey(full_name)
          ''')
          .eq('complaint_id', complaintId)
          .order('created_at', ascending: true);

      return (response as List<dynamic>)
          .map((json) =>
              EscalationRecordModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure(e.message, code: e.code);
      }
      return [];
    } catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load escalation history: $e');
      }
      debugPrint(
          'EscalationService.fetchEscalationHistory: $e. Falling back to empty history.');
      return [];
    }
  }

  /// Authorized resumption of a paused complaint by Dean/Administrator
  Future<Map<String, dynamic>> resumePausedComplaint({
    required String complaintId,
    required String resumptionNotes,
    DateTime? simulatedNow,
  }) async {
    try {
      final response = await _client.rpc<dynamic>(
        'resume_paused_complaint',
        params: {
          'p_complaint_id': complaintId,
          'p_resumption_notes': resumptionNotes,
          if (simulatedNow != null)
            'p_simulated_now': simulatedNow.toIso8601String(),
        },
      );
      return response as Map<String, dynamic>;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      throw DatabaseFailure('Administrative resumption failed: $e');
    }
  }

  /// Manually triggers server-side escalation engine worker (for test mode / admin triage)
  Future<Map<String, dynamic>> triggerEscalationWorker(
      {DateTime? simulatedNow}) async {
    try {
      final response = await _client.rpc<dynamic>(
        'process_daily_complaint_escalations',
        params: {
          if (simulatedNow != null)
            'p_simulated_now': simulatedNow.toIso8601String(),
        },
      );
      return response as Map<String, dynamic>;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      throw DatabaseFailure('Escalation processing failed: $e');
    }
  }

  List<GrievanceModel> _getMockPausedComplaints() {
    final now = DateTime.now();
    return [
      GrievanceModel(
        id: 'mock-paused-1',
        trackingNumber: 'SMT-2026-PAUSED',
        studentId: 'student-uuid-demo',
        studentName: 'Aarav Patel',
        departmentId: 'd-1',
        departmentName: 'Hostel & Residential',
        departmentCode: 'HOSTEL',
        currentAuthorityLevelId: 'lvl-3',
        currentAuthorityLevelNumber: 3,
        currentAuthorityLevelTitle: 'Level 3: Dean of Student Welfare',
        title: 'Severe water salinity & filter damage in Hostel Block C',
        description:
            'Drinking water filters have been contaminated with high salinity. Multiple reports submitted across 20 days remain unresolved.',
        category: 'Hostel & Residential Life',
        incidentDate: now.subtract(const Duration(days: 22)),
        status: ComplaintStatus.cutoffPaused,
        priority: 'HIGH',
        currentTierDeadline: now.subtract(const Duration(days: 2)),
        cutoffDeadline: now.subtract(const Duration(hours: 10)),
        isCutoffPaused: true,
        pausedAt: now.subtract(const Duration(hours: 10)),
        createdAt: now.subtract(const Duration(days: 20, hours: 10)),
        updatedAt: now.subtract(const Duration(hours: 10)),
      ),
    ];
  }

  /// Exposes mock paused complaint for regression testing
  List<GrievanceModel> getMockPausedComplaintsForTesting() =>
      _getMockPausedComplaints();
}
