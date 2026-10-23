import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/features/tracking/models/complaint_status.dart';

/// Chronological event node in the complaint redressal journey with immutable actor snapshots
class TimelineEventModel {
  final String id;
  final String complaintId;
  final ComplaintStatus? oldStatus;
  final ComplaintStatus newStatus;
  final String? eventType;
  final String? changedByName;
  final String? changedByRole;
  final String? changedByDept;
  final String? changedByLevelTitle;
  final String? actorDesignation;
  final int? actorAuthorityLevel;
  final String? remarks;
  final bool isSystemEvent;
  final String? assignedToTier;
  final String? assignedToName;
  final DateTime createdAt;

  const TimelineEventModel({
    required this.id,
    required this.complaintId,
    this.oldStatus,
    required this.newStatus,
    this.eventType,
    this.changedByName,
    this.changedByRole,
    this.changedByDept,
    this.changedByLevelTitle,
    this.actorDesignation,
    this.actorAuthorityLevel,
    this.remarks,
    this.isSystemEvent = false,
    this.assignedToTier,
    this.assignedToName,
    required this.createdAt,
  });

  factory TimelineEventModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final dept = profile != null
        ? profile['departments'] as Map<String, dynamic>?
        : null;
    final lvl = profile != null
        ? profile['authority_levels'] as Map<String, dynamic>?
        : null;

    final isSystem = json['is_system_event'] as bool? ??
        (json['actor_role'] == 'SYSTEM' ||
            (json['changed_by'] == null &&
                json['actor_user_id'] == null &&
                profile == null));

    final targetLevel = json['target_level'] as Map<String, dynamic>?;
    final targetAuthority = json['target_authority'] as Map<String, dynamic>?;

    final rawName = json['actor_display_name'] as String? ??
        (profile != null ? profile['full_name'] as String? : null) ??
        json['changed_by_name'] as String?;

    // Clean up any residual parenthetical demo badges from full names
    final cleanedName =
        rawName?.replaceAll(RegExp(r'\s*\([^)]*\)$'), '').trim();

    final rawRole = json['actor_role'] as String? ??
        (profile != null ? profile['role'] as String? : null) ??
        json['changed_by_role'] as String?;

    final rawDept = json['actor_department_name'] as String? ??
        (dept != null ? dept['name'] as String? : null);

    final rawDesignation = json['actor_designation'] as String? ??
        (profile != null ? profile['designation'] as String? : null) ??
        (lvl != null ? lvl['title'] as String? : null);

    // Normalize designation formatting with em-dash and remove legacy combined titles
    final cleanedDesignation = rawDesignation
        ?.replaceAll(
            'Faculty Advisor / Hostel Warden', 'Faculty / Department Officer')
        .replaceAll(': ', ' — ')
        .trim();

    final rawLevel = json['actor_authority_level'] as int? ??
        (lvl != null ? lvl['level_number'] as int? : null);

    final eventType = json['event_type'] as String? ??
        (json['new_status'] == 'PENDING'
            ? 'SUBMITTED'
            : json['new_status'] as String?);

    final rawAssignedTier = targetLevel != null
        ? targetLevel['title'] as String?
        : json['assigned_to_tier'] as String?;
    final cleanedAssignedTier = rawAssignedTier
        ?.replaceAll(
            'Faculty Advisor / Hostel Warden', 'Faculty / Department Officer')
        .trim();

    final rawAssignedName = targetAuthority != null
        ? targetAuthority['full_name'] as String?
        : json['assigned_to_name'] as String?;
    final cleanedAssignedName =
        rawAssignedName?.replaceAll(RegExp(r'\s*\([^)]*\)$'), '').trim();

    return TimelineEventModel(
      id: json['id'] as String,
      complaintId: json['complaint_id'] as String,
      oldStatus: json['old_status'] != null
          ? ComplaintStatus.fromCode(json['old_status'] as String)
          : null,
      newStatus: ComplaintStatus.fromCode(json['new_status'] as String),
      eventType: eventType,
      changedByName: isSystem
          ? 'System Redressal Engine (AUTOMATED)'
          : (cleanedName == null ||
                  cleanedName.toLowerCase().contains('unknown') ||
                  cleanedName.toLowerCase() == 'user'
              ? 'Authorized Officer'
              : cleanedName),
      changedByRole: isSystem
          ? 'SYSTEM'
          : (rawRole == null || rawRole.toLowerCase() == 'user'
              ? 'authority'
              : rawRole),
      changedByDept: rawDept,
      changedByLevelTitle: lvl != null ? lvl['title'] as String? : null,
      actorDesignation: cleanedDesignation,
      actorAuthorityLevel: rawLevel,
      remarks: json['remarks'] as String?,
      isSystemEvent: isSystem,
      assignedToTier: cleanedAssignedTier,
      assignedToName: cleanedAssignedName,
      createdAt: AppDateTimeUtils.parseBackendTimestamp(json['created_at']),
    );
  }
}
