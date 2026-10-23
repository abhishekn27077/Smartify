import 'dart:io';
import 'package:flutter/material.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';
import 'package:smartify/features/analytics/services/analytics_service.dart';
import 'package:smartify/features/analytics/services/report_export_service.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Analytics Provider
/// Manages state for grievance metrics, period filters, charts, and report exports.
class AnalyticsProvider extends ChangeNotifier {
  final AnalyticsService _service;

  AnalyticsProvider({AnalyticsService? service})
      : _service = service ?? AnalyticsService();

  AnalyticsDataModel? _analytics;
  bool _isLoading = false;
  bool _isExporting = false;
  String? _errorMessage;
  String? _exportMessage;

  int _selectedPeriodDays = 30; // Default: last 30 days
  String? _selectedDepartmentId;

  AnalyticsDataModel? get analytics => _analytics;
  bool get isLoading => _isLoading;
  bool get isExporting => _isExporting;
  String? get errorMessage => _errorMessage;
  String? get exportMessage => _exportMessage;
  int get selectedPeriodDays => _selectedPeriodDays;
  String? get selectedDepartmentId => _selectedDepartmentId;

  Future<void> loadAnalytics() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final start = now.subtract(Duration(days: _selectedPeriodDays));
      _analytics = await _service.fetchAnalytics(
        startDate: start,
        endDate: now,
        departmentId: _selectedDepartmentId,
      );
    } catch (e) {
      _errorMessage = 'Failed to load grievance analytics: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setPeriod(int days) {
    if (_selectedPeriodDays == days) return;
    _selectedPeriodDays = days;
    loadAnalytics();
  }

  void setDepartmentFilter(String? deptId) {
    if (_selectedDepartmentId == deptId) return;
    _selectedDepartmentId = deptId;
    loadAnalytics();
  }

  Future<File?> exportToCsv(List<GrievanceModel> complaints) async {
    _isExporting = true;
    _exportMessage = null;
    notifyListeners();

    try {
      final file =
          await ReportExportService.exportComplaintsToCsvFile(complaints);
      _exportMessage = 'CSV exported successfully to ${file.path}';
      return file;
    } catch (e) {
      _errorMessage = 'CSV export failed: $e';
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<File?> exportToPdf(List<GrievanceModel> complaints) async {
    if (_analytics == null) return null;

    _isExporting = true;
    _exportMessage = null;
    notifyListeners();

    try {
      final file = await ReportExportService.generatePdfReport(
        analytics: _analytics!,
        sampleComplaints: complaints,
      );
      _exportMessage = 'PDF report generated at ${file.path}';
      return file;
    } catch (e) {
      _errorMessage = 'PDF generation failed: $e';
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }
}
