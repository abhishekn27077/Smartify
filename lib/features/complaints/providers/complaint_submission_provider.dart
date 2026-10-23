import 'package:flutter/foundation.dart';
import 'package:smartify/core/constants/app_constants.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/core/utils/date_validator.dart';
import 'package:smartify/features/complaints/models/attachment_file.dart';
import 'package:smartify/features/complaints/models/complaint_category_model.dart';
import 'package:smartify/features/complaints/models/complaint_draft_model.dart';
import 'package:smartify/features/complaints/models/complaint_submission_result.dart';
import 'package:smartify/features/complaints/models/department_model.dart';
import 'package:smartify/features/complaints/services/complaint_service.dart';

/// SMARTIFY Complaint Submission Provider (ChangeNotifier)
/// Manages form state, reactive validation, duplicate-submit protection, and API execution.
class ComplaintSubmissionProvider extends ChangeNotifier {
  final ComplaintService _service;

  ComplaintSubmissionProvider({ComplaintService? service})
      : _service = service ?? ComplaintService();

  // --- Form State ---
  String _title = '';
  String _description = '';
  String _category = '';
  String? _subCategory;
  String? _departmentId;
  DateTime _incidentDate = DateValidator.getLatestPermittedDate();
  AttachmentFile? _attachment;

  // --- Async & Status State ---
  bool _isSubmitting = false;
  bool _isLoadingDepartments = false;
  String? _submissionError;
  ComplaintSubmissionResult? _submissionResult;
  List<DepartmentModel> _departments = [];

  // --- Duplicate Submission Guard ---
  int _submitAttempts = 0;
  DateTime? _lastSubmitTimestamp;

  // --- Getters ---
  int get submitAttempts => _submitAttempts;
  String get title => _title;
  String get description => _description;
  String get category => _category;
  String? get subCategory => _subCategory;
  String? get departmentId => _departmentId;
  DateTime get incidentDate => _incidentDate;
  AttachmentFile? get attachment => _attachment;

  bool get isSubmitting => _isSubmitting;
  bool get isLoadingDepartments => _isLoadingDepartments;
  String? get submissionError => _submissionError;
  ComplaintSubmissionResult? get submissionResult => _submissionResult;
  List<DepartmentModel> get departments => _departments;

  DepartmentModel? get selectedDepartment =>
      _departments.where((d) => d.id == _departmentId).firstOrNull;

  // --- Validation Errors ---
  String? get titleError {
    if (_title.isEmpty) return null;
    if (_title.trim().length < AppConstants.kMinTitleLength) {
      return 'Title must be at least ${AppConstants.kMinTitleLength} characters.';
    }
    if (_title.trim().length > AppConstants.kMaxTitleLength) {
      return 'Title cannot exceed ${AppConstants.kMaxTitleLength} characters.';
    }
    return null;
  }

  String? get descriptionError {
    if (_description.isEmpty) return null;
    if (_description.trim().length < AppConstants.kMinDescriptionLength) {
      return 'Description must be at least ${AppConstants.kMinDescriptionLength} characters with specific facts.';
    }
    return null;
  }

  String? get dateError {
    return DateValidator.validateIncidentDate(_incidentDate);
  }

  String? get attachmentError {
    if (_attachment == null) return null;
    return _attachment!.validate();
  }

  bool get isFormValid {
    if (_title.trim().length < AppConstants.kMinTitleLength ||
        _title.trim().length > AppConstants.kMaxTitleLength) {
      return false;
    }
    if (_description.trim().length < AppConstants.kMinDescriptionLength) {
      return false;
    }
    if (_category.trim().isEmpty) {
      return false;
    }
    if (_departmentId == null || _departmentId!.trim().isEmpty) {
      return false;
    }
    if (DateValidator.validateIncidentDate(_incidentDate) != null) {
      return false;
    }
    if (_attachment != null && _attachment!.validate() != null) {
      return false;
    }
    return true;
  }

  // --- Department Initialization ---
  Future<void> loadDepartments({String? studentProgram}) async {
    if (_departments.isNotEmpty) return;
    _isLoadingDepartments = true;
    notifyListeners();

    try {
      _departments = await _service.fetchActiveDepartments();
      if (_departmentId == null && _departments.isNotEmpty) {
        // Default to student's program academic department or first
        if (studentProgram != null) {
          final targetCode = (studentProgram == 'MBA')
              ? 'MBA'
              : (studentProgram == 'M.Com' || studentProgram == 'MCOM')
                  ? 'MCOM'
                  : 'MCA';
          final match =
              _departments.where((d) => d.code == targetCode).firstOrNull;
          _departmentId = match?.id ?? _departments.first.id;
        } else {
          _departmentId = _departments.first.id;
        }
      }
    } catch (_) {
      // Handled gracefully via fallback departments
    } finally {
      _isLoadingDepartments = false;
      notifyListeners();
    }
  }

  // --- Form Mutation Methods ---
  void setTitle(String value) {
    _title = value;
    notifyListeners();
  }

  void setDescription(String value) {
    _description = value;
    notifyListeners();
  }

  void selectCategory(ComplaintCategoryModel model, {String? studentProgram}) {
    _category = model.title;
    _subCategory =
        model.subCategories.isNotEmpty ? model.subCategories.first : null;

    // Automatically align department based on operational code or student program
    if (_departments.isNotEmpty) {
      if (model.defaultDepartmentCode == 'ACAD') {
        // Derive academic department according to student's academic program
        final targetCode = (studentProgram == 'MBA')
            ? 'MBA'
            : (studentProgram == 'M.Com' || studentProgram == 'MCOM')
                ? 'MCOM'
                : 'MCA';

        final matchingDept =
            _departments.where((d) => d.code == targetCode).firstOrNull ??
                _departments.where((d) => d.code == 'ACAD').firstOrNull;

        if (matchingDept != null) {
          _departmentId = matchingDept.id;
        }
      } else {
        // Operational category: Wi-Fi (IT), Hostel (HOSTEL), Infra (INFRA), Fees (FIN)
        final matchingDept = _departments
            .where((d) => d.code == model.defaultDepartmentCode)
            .firstOrNull;
        if (matchingDept != null) {
          _departmentId = matchingDept.id;
        }
      }
    }
    notifyListeners();
  }

  void selectSubCategory(String? subCategory) {
    _subCategory = subCategory;
    notifyListeners();
  }

  void selectDepartmentId(String departmentId) {
    _departmentId = departmentId;
    notifyListeners();
  }

  void selectIncidentDate(DateTime date) {
    _incidentDate = DateValidator.stripTime(date);
    notifyListeners();
  }

  void setAttachment(AttachmentFile? file) {
    _attachment = file;
    notifyListeners();
  }

  void removeAttachment() {
    _attachment = null;
    notifyListeners();
  }

  void clearError() {
    _submissionError = null;
    notifyListeners();
  }

  // --- Submit Execution ---
  Future<bool> submitComplaint({String? studentProgram}) async {
    // 1. Guard against in-flight concurrent execution
    if (_isSubmitting) return false;

    // 2. Debounce duplicate clicks within 2 seconds
    final now = DateTime.now();
    if (_lastSubmitTimestamp != null &&
        now.difference(_lastSubmitTimestamp!).inSeconds < 2) {
      return false;
    }
    _lastSubmitTimestamp = now;

    // 3. Pre-flight client-side form validation
    if (!isFormValid) {
      _submissionError =
          'Please resolve all required fields and date constraints before submitting.';
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _submissionError = null;
    _submitAttempts++;
    notifyListeners();

    final draft = ComplaintDraftModel(
      title: _title,
      description: _description,
      category: _category,
      subCategory: _subCategory,
      departmentId: _departmentId!,
      academicProgram: studentProgram,
      incidentDate: _incidentDate,
      attachment: _attachment,
    );

    try {
      final result = await _service.submitComplaint(draft);
      _submissionResult = result;
      _isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      final raw = e.toString();
      if (raw.contains('SocketException') ||
          raw.contains('ClientException') ||
          raw.contains('Failed host lookup')) {
        _submissionError =
            'Unable to connect. Please check your internet connection and try again.';
      } else if (raw.contains('violates check constraint') ||
          raw.contains('incident_date') ||
          raw.contains('23514')) {
        _submissionError =
            'Grievances must be submitted within 7 calendar days of the incident.';
      } else if (e is ValidationFailure || e is StorageUploadFailure) {
        _submissionError =
            e.toString().replaceFirst(RegExp(r'^[A-Za-z]+Failure:\s*'), '');
      } else if (e is DatabaseFailure) {
        _submissionError = e.message;
      } else {
        _submissionError =
            'Failed to submit grievance. Please verify details and try again.';
      }
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  void resetForm() {
    _title = '';
    _description = '';
    _category = '';
    _subCategory = null;
    _departmentId = _departments.isNotEmpty ? _departments.first.id : null;
    _incidentDate = DateValidator.getLatestPermittedDate();
    _attachment = null;
    _submissionError = null;
    _submissionResult = null;
    _isSubmitting = false;
    notifyListeners();
  }
}
