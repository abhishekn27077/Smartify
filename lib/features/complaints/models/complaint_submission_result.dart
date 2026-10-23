import 'package:smartify/core/utils/authority_designation_resolver.dart';

/// Result returned upon verified grievance creation
class ComplaintSubmissionResult {
  final String complaintId;
  final String trackingNumber;
  final String status;
  final DateTime submittedAt;
  final String category;
  final String departmentName;
  final DateTime incidentDate;
  final String currentTierTitle;
  final DateTime tierDeadline;
  final String? attachmentUrl;

  const ComplaintSubmissionResult({
    required this.complaintId,
    required this.trackingNumber,
    required this.status,
    required this.submittedAt,
    required this.category,
    required this.departmentName,
    required this.incidentDate,
    required this.currentTierTitle,
    required this.tierDeadline,
    this.attachmentUrl,
  });

  factory ComplaintSubmissionResult.fromJson(Map<String, dynamic> json,
      {String? deptName, String? tierTitle, String? attachmentUrl}) {
    return ComplaintSubmissionResult(
      complaintId: json['id'] as String,
      trackingNumber: json['tracking_number'] as String,
      status: json['status'] as String? ?? 'PENDING',
      submittedAt: DateTime.parse(json['created_at'] as String),
      category: json['category'] as String,
      departmentName: deptName ?? 'Campus Department',
      incidentDate: DateTime.parse(json['incident_date'] as String),
      currentTierTitle: AuthorityDesignationResolver.resolveDesignation(
        levelNumber: 1,
        departmentName: deptName,
        fallbackTitle: tierTitle,
      ),
      tierDeadline: DateTime.parse(json['current_tier_deadline'] as String),
      attachmentUrl: attachmentUrl ?? json['attachment_url'] as String?,
    );
  }
}
