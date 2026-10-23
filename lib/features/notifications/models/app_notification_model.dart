/// SMARTIFY In-App Notification Entity
class AppNotificationModel {
  final String id;
  final String userId;
  final String? complaintId;
  final String title;
  final String message;
  final String notificationType;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotificationModel({
    required this.id,
    required this.userId,
    this.complaintId,
    required this.title,
    required this.message,
    required this.notificationType,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  factory AppNotificationModel.fromJson(Map<String, dynamic> json) {
    return AppNotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      complaintId: json['complaint_id'] as String?,
      title: json['title'] as String? ?? 'Notification',
      message: json['message'] as String? ?? '',
      notificationType: json['notification_type'] as String? ?? 'GENERAL',
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AppNotificationModel copyWith({bool? isRead, DateTime? readAt}) {
    return AppNotificationModel(
      id: id,
      userId: userId,
      complaintId: complaintId,
      title: title,
      message: message,
      notificationType: notificationType,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }
}
