/// Represents a single recorded tier escalation event from public.complaint_escalations
class EscalationRecordModel {
  final String id;
  final String complaintId;
  final String fromLevelId;
  final int fromLevelNumber;
  final String fromLevelTitle;
  final String toLevelId;
  final int toLevelNumber;
  final String toLevelTitle;
  final String? escalatedBy;
  final String? escalatedByName;
  final bool isAutomated;
  final String reason;
  final int tierDaysSpent;
  final DateTime createdAt;

  const EscalationRecordModel({
    required this.id,
    required this.complaintId,
    required this.fromLevelId,
    required this.fromLevelNumber,
    required this.fromLevelTitle,
    required this.toLevelId,
    required this.toLevelNumber,
    required this.toLevelTitle,
    this.escalatedBy,
    this.escalatedByName,
    this.isAutomated = true,
    required this.reason,
    required this.tierDaysSpent,
    required this.createdAt,
  });

  factory EscalationRecordModel.fromJson(Map<String, dynamic> json) {
    final fromLvl = json['from_level'] as Map<String, dynamic>?;
    final toLvl = json['to_level'] as Map<String, dynamic>?;
    final actor = json['escalated_by_profile'] as Map<String, dynamic>?;

    return EscalationRecordModel(
      id: json['id'] as String,
      complaintId: json['complaint_id'] as String,
      fromLevelId: json['from_level_id'] as String,
      fromLevelNumber:
          fromLvl != null ? (fromLvl['level_number'] as int? ?? 1) : 1,
      fromLevelTitle: fromLvl != null
          ? (fromLvl['title'] as String? ?? 'Level 1')
          : 'Level 1',
      toLevelId: json['to_level_id'] as String,
      toLevelNumber: toLvl != null ? (toLvl['level_number'] as int? ?? 2) : 2,
      toLevelTitle:
          toLvl != null ? (toLvl['title'] as String? ?? 'Level 2') : 'Level 2',
      escalatedBy: json['escalated_by'] as String?,
      escalatedByName: actor != null ? actor['full_name'] as String? : null,
      isAutomated: json['is_automated'] as bool? ?? true,
      reason: json['reason'] as String? ?? 'Automated SLA tier expiration',
      tierDaysSpent: json['tier_days_spent'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
