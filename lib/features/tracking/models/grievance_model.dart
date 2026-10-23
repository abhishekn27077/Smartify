import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/utils/authority_designation_resolver.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';

/// Full Grievance entity representation for Tracking & Authority workflows
class GrievanceModel {
  final String id;
  final String trackingNumber;
  final String studentId;
  final String? studentName;
  final String departmentId;
  final String departmentName;
  final String departmentCode;
  final String currentAuthorityLevelId;
  final int currentAuthorityLevelNumber;
  final String currentAuthorityLevelTitle;
  final String? assignedAuthorityId;
  final String? assignedAuthorityName;
  final String title;
  final String description;
  final String category;
  final DateTime incidentDate;
  final ComplaintStatus status;
  final String priority;
  final DateTime currentTierDeadline;
  final DateTime cutoffDeadline;
  final bool isCutoffPaused;
  final DateTime? pausedAt;
  final DateTime? resumedAt;
  final String? resolutionNotes;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> attachmentPaths;

  const GrievanceModel({
    required this.id,
    required this.trackingNumber,
    required this.studentId,
    this.studentName,
    required this.departmentId,
    required this.departmentName,
    required this.departmentCode,
    required this.currentAuthorityLevelId,
    required this.currentAuthorityLevelNumber,
    required this.currentAuthorityLevelTitle,
    this.assignedAuthorityId,
    this.assignedAuthorityName,
    required this.title,
    required this.description,
    required this.category,
    required this.incidentDate,
    required this.status,
    required this.priority,
    required this.currentTierDeadline,
    required this.cutoffDeadline,
    this.isCutoffPaused = false,
    this.pausedAt,
    this.resumedAt,
    this.resolutionNotes,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
    this.attachmentPaths = const [],
  });

  factory GrievanceModel.fromJson(Map<String, dynamic> json) {
    final dept = json['departments'] as Map<String, dynamic>?;
    final level = json['authority_levels'] as Map<String, dynamic>?;
    final student = json['student_profile'] as Map<String, dynamic>?;
    final authority = json['authority_profile'] as Map<String, dynamic>?;

    final attachmentsRaw = json['complaint_attachments'] as List<dynamic>?;
    final attachments = attachmentsRaw != null
        ? attachmentsRaw
            .map((a) => a['file_path'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toList()
        : <String>[];

    return GrievanceModel(
      id: json['id'] as String,
      trackingNumber: json['tracking_number'] as String,
      studentId: json['student_id'] as String,
      studentName: student != null ? student['full_name'] as String? : null,
      departmentId: json['department_id'] as String,
      departmentName: dept != null
          ? dept['name'] as String? ?? 'Campus Dept'
          : 'Campus Dept',
      departmentCode: dept != null ? dept['code'] as String? ?? 'DEPT' : 'DEPT',
      currentAuthorityLevelId: json['current_authority_level_id'] as String,
      currentAuthorityLevelNumber:
          level != null ? (level['level_number'] as int? ?? 1) : 1,
      currentAuthorityLevelTitle:
          AuthorityDesignationResolver.resolveDesignation(
        levelNumber: level != null ? (level['level_number'] as int? ?? 1) : 1,
        departmentCode: dept != null ? dept['code'] as String? : null,
        departmentName: dept != null ? dept['name'] as String? : null,
        fallbackTitle: level != null ? level['title'] as String? : null,
      ),
      assignedAuthorityId: json['assigned_authority_id'] as String?,
      assignedAuthorityName:
          authority != null ? authority['full_name'] as String? : null,
      title: _cleanGrievanceTitle(json['title'] as String),
      description: json['description'] as String,
      category: json['category'] as String,
      incidentDate: AppDateTimeUtils.parseIncidentDate(json['incident_date']),
      status: ComplaintStatus.fromCode(json['status'] as String),
      priority: json['priority'] as String? ?? 'MEDIUM',
      currentTierDeadline:
          AppDateTimeUtils.parseBackendTimestamp(json['current_tier_deadline']),
      cutoffDeadline:
          AppDateTimeUtils.parseBackendTimestamp(json['cutoff_deadline']),
      isCutoffPaused: json['is_cutoff_paused'] as bool? ?? false,
      pausedAt: json['paused_at'] != null
          ? AppDateTimeUtils.parseBackendTimestamp(json['paused_at'])
          : null,
      resumedAt: json['resumed_at'] != null
          ? AppDateTimeUtils.parseBackendTimestamp(json['resumed_at'])
          : null,
      resolutionNotes: json['resolution_notes'] as String?,
      resolvedAt: json['resolved_at'] != null
          ? AppDateTimeUtils.parseBackendTimestamp(json['resolved_at'])
          : null,
      createdAt: AppDateTimeUtils.parseBackendTimestamp(json['created_at']),
      updatedAt: AppDateTimeUtils.parseBackendTimestamp(json['updated_at']),
      attachmentPaths: attachments,
    );
  }

  /// Calculates SLA duration remaining
  Duration get timeRemaining =>
      AppDateTimeUtils.calculateRemainingSla(currentTierDeadline);

  /// True if current tier deadline has passed and complaint is still open
  bool get isSlaBreached =>
      timeRemaining.isNegative && !status.isTerminal && !isCutoffPaused;

  /// Alias for isSlaBreached
  bool get isOverdue => isSlaBreached;

  /// Contextual status remarks or resolution notes
  String? get statusRemarks => resolutionNotes;

  /// User-friendly deadline text
  String get formattedTimeRemaining {
    if (status.isTerminal) return 'Closed';
    if (isCutoffPaused) return 'Governance Cutoff (20d)';
    return AppDateTimeUtils.formatSlaRemaining(timeRemaining);
  }

  /// Authority-facing SLA headline: 'Action overdue', 'Due soon', or 'SLA active'
  String get slaStatusHeadline => AppDateTimeUtils.getSlaStatusLabel(
        isCutoffPaused: isCutoffPaused,
        isSlaBreached: isSlaBreached,
        timeRemaining: timeRemaining,
      );

  /// Authority-facing SLA explanation message
  String get slaExplanation => AppDateTimeUtils.getSlaExplanation(
        isCutoffPaused: isCutoffPaused,
        isSlaBreached: isSlaBreached,
        timeRemaining: timeRemaining,
        currentLevelNumber: currentAuthorityLevelNumber,
      );

  /// Whether this grievance belongs to an operational department with single-tier authority (Hostel, IT, Finance, Infrastructure)
  bool get isOperationalDepartment {
    final code = departmentCode.toUpperCase().trim();
    return const {'HOSTEL', 'IT', 'FIN', 'INFRA'}.contains(code);
  }

  static String _cleanGrievanceTitle(String raw) {
    var cleaned = raw;
    if (cleaned.contains('betConflicting') && cleaned.contains('.ween')) {
      cleaned =
          cleaned.replaceAll(RegExp(r'betConflicting.*?\.ween'), 'between');
    }
    return cleaned.trim();
  }
}
