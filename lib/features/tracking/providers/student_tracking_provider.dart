import 'package:flutter/foundation.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';
import 'package:smartify/features/tracking/models/timeline_event_model.dart';
import 'package:smartify/features/tracking/services/tracking_service.dart';

/// SMARTIFY Student Complaint Tracking Provider
class StudentTrackingProvider extends ChangeNotifier {
  final TrackingService _service;

  StudentTrackingProvider({TrackingService? service})
      : _service = service ?? TrackingService();

  List<GrievanceModel> _complaints = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Active Filter States
  String _selectedStatus = 'ALL';
  String _selectedCategory = 'ALL';
  String _searchQuery = '';

  // Detail View State
  GrievanceModel? _selectedComplaint;
  List<TimelineEventModel> _timelineEvents = [];
  bool _isLoadingTimeline = false;

  // Getters
  List<GrievanceModel> get complaints => _complaints;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedStatus => _selectedStatus;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;

  GrievanceModel? get selectedComplaint => _selectedComplaint;
  List<TimelineEventModel> get timelineEvents => _timelineEvents;
  bool get isLoadingTimeline => _isLoadingTimeline;

  Future<void> loadComplaints() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _complaints = await _service.fetchMyComplaints(
        statusFilter: _selectedStatus,
        categoryFilter: _selectedCategory,
        searchQuery: _searchQuery,
      );
    } catch (e) {
      _errorMessage = 'Could not load grievances: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setStatusFilter(String status) {
    if (_selectedStatus == status) return;
    _selectedStatus = status;
    loadComplaints();
  }

  void setCategoryFilter(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    loadComplaints();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    loadComplaints();
  }

  Future<void> selectComplaint(GrievanceModel complaint) async {
    _selectedComplaint = complaint;
    _isLoadingTimeline = true;
    _timelineEvents = [];
    notifyListeners();

    try {
      _timelineEvents = await _service.fetchComplaintTimeline(complaint.id);
    } catch (_) {
      // Handled gracefully
    } finally {
      _isLoadingTimeline = false;
      notifyListeners();
    }
  }

  Future<void> refreshSelectedComplaint() async {
    if (_selectedComplaint == null) return;
    try {
      final updated = await _service.fetchComplaintById(_selectedComplaint!.id);
      if (updated != null) {
        _selectedComplaint = updated;
      }
      _timelineEvents =
          await _service.fetchComplaintTimeline(_selectedComplaint!.id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing selected complaint: $e');
    }
  }

  void clearSelection() {
    _selectedComplaint = null;
    _timelineEvents = [];
    notifyListeners();
  }
}
