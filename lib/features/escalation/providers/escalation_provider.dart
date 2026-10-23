import 'package:flutter/material.dart';
import 'package:smartify/features/escalation/models/escalation_record_model.dart';
import 'package:smartify/features/escalation/services/escalation_service.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Escalation & Cutoff Provider
/// Manages administrator state for 20-day cutoff queues, tier escalations, and worker triggers.
class EscalationProvider extends ChangeNotifier {
  final EscalationService _service;

  EscalationProvider({EscalationService? service})
      : _service = service ?? EscalationService();

  List<GrievanceModel> _pausedComplaints = [];
  final Map<String, List<EscalationRecordModel>> _historyCache = {};
  bool _isLoading = false;
  bool _isResuming = false;
  bool _isTriggeringWorker = false;
  String? _errorMessage;
  Map<String, dynamic>? _lastWorkerResult;

  List<GrievanceModel> get pausedComplaints => _pausedComplaints;
  bool get isLoading => _isLoading;
  bool get isResuming => _isResuming;
  bool get isTriggeringWorker => _isTriggeringWorker;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get lastWorkerResult => _lastWorkerResult;

  List<EscalationRecordModel> getHistory(String complaintId) =>
      _historyCache[complaintId] ?? [];

  /// Loads all currently cutoff-paused complaints
  Future<void> loadPausedComplaints() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _pausedComplaints = await _service.fetchCutoffPausedComplaints();
    } catch (e) {
      _errorMessage = 'Failed to load paused grievances: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the escalation history trail for a specific complaint
  Future<void> loadHistory(String complaintId) async {
    try {
      final records = await _service.fetchEscalationHistory(complaintId);
      _historyCache[complaintId] = records;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading escalation history for $complaintId: $e');
    }
  }

  /// Authorizes resumption of a paused grievance
  Future<bool> resumeComplaint({
    required String complaintId,
    required String resumptionNotes,
    DateTime? simulatedNow,
  }) async {
    if (resumptionNotes.trim().length < 10) {
      _errorMessage = 'Resumption notes must be at least 10 characters.';
      notifyListeners();
      return false;
    }

    _isResuming = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _service.resumePausedComplaint(
        complaintId: complaintId,
        resumptionNotes: resumptionNotes.trim(),
        simulatedNow: simulatedNow,
      );

      final success = res['success'] == true;
      if (success) {
        // Remove from paused list
        _pausedComplaints.removeWhere((c) => c.id == complaintId);
      }
      return success;
    } catch (e) {
      _errorMessage = 'Failed to authorize resumption: $e';
      return false;
    } finally {
      _isResuming = false;
      notifyListeners();
    }
  }

  /// Manually triggers the automated escalation & cutoff worker (useful for testing & admin triage)
  Future<bool> runEscalationWorker({DateTime? simulatedNow}) async {
    _isTriggeringWorker = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _lastWorkerResult = await _service.triggerEscalationWorker(
        simulatedNow: simulatedNow,
      );
      // Refresh paused complaints list after running worker
      await loadPausedComplaints();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to run escalation worker: $e';
      return false;
    } finally {
      _isTriggeringWorker = false;
      notifyListeners();
    }
  }
}
