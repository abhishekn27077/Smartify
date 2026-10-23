import 'package:smartify/core/constants/app_constants.dart';
import 'package:smartify/core/utils/date_validator.dart';
import 'package:smartify/features/complaints/models/attachment_file.dart';

/// Form draft state for registering a campus grievance
class ComplaintDraftModel {
  final String title;
  final String description;
  final String category;
  final String? subCategory;
  final String departmentId;
  final String? academicProgram;
  final DateTime incidentDate;
  final AttachmentFile? attachment;

  const ComplaintDraftModel({
    required this.title,
    required this.description,
    required this.category,
    this.subCategory,
    required this.departmentId,
    this.academicProgram,
    required this.incidentDate,
    this.attachment,
  });

  /// Comprehensive client-side validation
  String? validate() {
    if (title.trim().length < AppConstants.kMinTitleLength) {
      return 'Title must be at least ${AppConstants.kMinTitleLength} characters.';
    }
    if (title.trim().length > AppConstants.kMaxTitleLength) {
      return 'Title cannot exceed ${AppConstants.kMaxTitleLength} characters.';
    }
    if (description.trim().length < AppConstants.kMinDescriptionLength) {
      return 'Description must be at least ${AppConstants.kMinDescriptionLength} characters with specific details.';
    }
    if (category.trim().isEmpty) {
      return 'Please select a grievance category.';
    }
    if (departmentId.trim().isEmpty) {
      return 'Please select the relevant campus department.';
    }

    final dateError = DateValidator.validateIncidentDate(incidentDate);
    if (dateError != null) {
      return dateError;
    }

    if (attachment != null) {
      final attachError = attachment!.validate();
      if (attachError != null) return attachError;
    }

    return null;
  }
}
