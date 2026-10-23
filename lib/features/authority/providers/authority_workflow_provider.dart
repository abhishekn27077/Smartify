import 'package:flutter/foundation.dart';
import 'package:smartify/core/utils/app_error_utils.dart';
import 'package:smartify/features/authority/models/authority_tier_model.dart';
import 'package:smartify/features/authority/services/authority_service.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Authority Workflow Provider
/// Manages staff queue, triage filters, status actions, and tier forwarding.
class AuthorityWorkflowProvider extends ChangeNotifier {
  final AuthorityService _service;

  AuthorityWorkflowProvider({AuthorityService? service})
      : _service = service ?? AuthorityService();

  List<GrievanceModel> _queue = [];
  List<AuthorityTierModel> _tiers = [];
  bool _isLoading = false;
  bool _isProcessingAction = false;
  String? _errorMessage;
  String? _actionSuccessMessage;

  // Active Filters & Sorting
  String _selectedStatus = 'ALL';
  String _selectedPriority = 'ALL';
  String _searchQuery = '';
  String _sortOption = 'PRIORITY_SLA';
  bool _sortByUrgency = true;

  // Authoritative Queue Summary
  Map<String, int> _queueSummary = {
    'total_active': 0,
    'pending_count': 0,
    'under_review_count': 0,
    'due_soon_count': 0,
    'overdue_count': 0,
    'resolved_count': 0,
  };

  // Selected for Action
  GrievanceModel? _selectedComplaint;

  // Getters
  List<GrievanceModel> get queue => _queue;
  List<AuthorityTierModel> get tiers => _tiers;
  bool get isLoading => _isLoading;
  bool get isProcessingAction => _isProcessingAction;
  String? get errorMessage => _errorMessage;
  String? get actionSuccessMessage => _actionSuccessMessage;

  String get selectedStatus => _selectedStatus;
  String get selectedPriority => _selectedPriority;
  String get searchQuery => _searchQuery;
  String get sortOption => _sortOption;
  bool get sortByUrgency => _sortByUrgency;
  GrievanceModel? get selectedComplaint => _selectedComplaint;
  Map<String, int> get queueSummary => _queueSummary;

  int get activeCount => _queueSummary['total_active'] ?? _queue.length;
  int get pendingCount => _queueSummary['pending_count'] ?? 0;
  int get underReviewCount => _queueSummary['under_review_count'] ?? 0;
  int get dueSoonCount => _queueSummary['due_soon_count'] ?? 0;
  int get overdueCount => _queueSummary['overdue_count'] ?? 0;
  int get resolvedCount => _queueSummary['resolved_count'] ?? 0;

  Future<void> loadQueue() async {
    _isLoading = true;
    _errorMessage = null;
    _actionSuccessMessage = null;
    notifyListeners();

    try {
      _tiers = await _service.fetchAuthorityLevels();
      final results = await Future.wait([
        _service.fetchAuthorityQueue(
          statusFilter: _selectedStatus,
          priorityFilter: _selectedPriority,
          searchQuery: _searchQuery,
          sortOption: _sortOption,
          sortByUrgency: _sortByUrgency,
        ),
        _service.fetchQueueSummary(),
      ]);
      _queue = results[0] as List<GrievanceModel>;
      _queueSummary = results[1] as Map<String, int>;
    } catch (e) {
      _errorMessage = 'Could not load authority queue: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setStatusFilter(String status) {
    if (_selectedStatus == status) return;
    _selectedStatus = status;
    loadQueue();
  }

  void setPriorityFilter(String priority) {
    if (_selectedPriority == priority) return;
    _selectedPriority = priority;
    loadQueue();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    loadQueue();
  }

  void setSortOption(String sort) {
    if (_sortOption == sort) return;
    _sortOption = sort;
    _sortByUrgency = (sort == 'PRIORITY_SLA');
    loadQueue();
  }

  void toggleSortByUrgency() {
    _sortByUrgency = !_sortByUrgency;
    _sortOption = _sortByUrgency ? 'PRIORITY_SLA' : 'NEWEST';
    loadQueue();
  }

  void selectComplaint(GrievanceModel grievance) {
    _selectedComplaint = grievance;
    _actionSuccessMessage = null;
    _errorMessage = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedComplaint = null;
    notifyListeners();
  }

  void clearActionMessages() {
    _actionSuccessMessage = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Processes status change (Pick Up, In Progress, Resolve, Reject)
  Future<bool> processStatusChange({
    required ComplaintStatus newStatus,
    required String remarks,
    String? resolutionNotes,
  }) async {
    if (_selectedComplaint == null || _isProcessingAction) return false;

    _isProcessingAction = true;
    _errorMessage = null;
    _actionSuccessMessage = null;
    notifyListeners();

    try {
      await _service.updateStatus(
        complaintId: _selectedComplaint!.id,
        currentStatus: _selectedComplaint!.status,
        newStatus: newStatus,
        remarks: remarks,
        resolutionNotes: resolutionNotes,
      );

      _actionSuccessMessage =
          'Grievance ${_selectedComplaint!.trackingNumber} updated to ${newStatus.label}.';
      _isProcessingAction = false;
      await loadQueue();
      return true;
    } catch (e) {
      _errorMessage = AppErrorUtils.cleanErrorMessage(e);
      _isProcessingAction = false;
      notifyListeners();
      return false;
    }
  }

  /// Forwards grievance to the next authority level
  Future<bool> forwardComplaint({
    required String reason,
  }) async {
    if (_selectedComplaint == null || _isProcessingAction) return false;

    _isProcessingAction = true;
    _errorMessage = null;
    _actionSuccessMessage = null;
    notifyListeners();

    try {
      await _service.forwardToNextTier(
        complaintId: _selectedComplaint!.id,
        currentLevelId: _selectedComplaint!.currentAuthorityLevelId,
        currentLevelNumber: _selectedComplaint!.currentAuthorityLevelNumber,
        reason: reason,
      );

      _actionSuccessMessage =
          'Grievance ${_selectedComplaint!.trackingNumber} successfully forwarded to next tier.';
      _isProcessingAction = false;
      await loadQueue();
      return true;
    } catch (e) {
      _errorMessage = AppErrorUtils.cleanErrorMessage(e);
      _isProcessingAction = false;
      notifyListeners();
      return false;
    }
  }

  /// Claims / accepts ownership of an unassigned grievance
  Future<bool> claimComplaint(String complaintId) async {
    if (_isProcessingAction) return false;

    _isProcessingAction = true;
    _errorMessage = null;
    _actionSuccessMessage = null;
    notifyListeners();

    try {
      await _service.claimGrievance(complaintId: complaintId);
      _actionSuccessMessage = 'Case successfully accepted and assigned to you.';
      _isProcessingAction = false;
      await loadQueue();
      return true;
    } catch (e) {
      _errorMessage = AppErrorUtils.cleanErrorMessage(e);
      _isProcessingAction = false;
      notifyListeners();
      return false;
    }
  }
}
