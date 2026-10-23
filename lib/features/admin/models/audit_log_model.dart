/// SMARTIFY Immutable Audit Log Entity
class AuditLogModel {
  final String id;
  final String? actorId;
  final String? actorName;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const AuditLogModel({
    required this.id,
    this.actorId,
    this.actorName,
    required this.action,
    required this.entityType,
    this.entityId,
    required this.metadata,
    required this.createdAt,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    final actor = json['profiles'] as Map<String, dynamic>?;

    return AuditLogModel(
      id: json['id'] as String,
      actorId: json['actor_id'] as String?,
      actorName: actor != null
          ? actor['full_name'] as String?
          : (json['actor_id'] == null ? 'System Automation' : 'Staff'),
      action: json['action'] as String? ?? 'EVENT',
      entityType: json['entity_type'] as String? ?? 'system',
      entityId: json['entity_id'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isSystemEvent =>
      actorId == null ||
      (actorName != null &&
          (actorName!.contains('System') || actorName!.contains('Engine')));
}
