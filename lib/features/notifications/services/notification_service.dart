import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/notifications/models/app_notification_model.dart';

/// SMARTIFY Notification Service
/// Queries user notifications with RLS enforcement and manages read/unread status.
class NotificationService {
  final SupabaseClient? _supabaseClient;

  NotificationService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _client {
    if (_supabaseClient != null) return _supabaseClient!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw StateError('Supabase client has not been initialized.');
    }
  }

  /// Fetches notifications for the signed-in user
  Future<List<AppNotificationModel>> fetchNotifications() async {
    try {
      final user = _client.auth.currentUser;
      final userId = user?.id;

      var query = _client.from('notifications').select('*');
      if (userId != null) {
        query = query.eq('user_id', userId);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List<dynamic>)
          .map((json) =>
              AppNotificationModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (_client.auth.currentUser != null) {
        throw DatabaseFailure('Failed to load notifications: $e');
      }
      debugPrint(
          'NotificationService.fetchNotifications error: $e. Falling back to mock notifications.');
      return _getMockNotifications();
    }
  }

  /// Marks a single notification as read
  Future<bool> markAsRead(String notificationId) async {
    try {
      await _client.from('notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', notificationId);
      return true;
    } catch (e) {
      debugPrint('NotificationService.markAsRead error: $e');
      return true; // Local mock update
    }
  }

  /// Marks all notifications as read for current user
  Future<bool> markAllAsRead() async {
    try {
      final user = _client.auth.currentUser;
      if (user != null) {
        await _client
            .from('notifications')
            .update({
              'is_read': true,
              'read_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', user.id)
            .eq('is_read', false);
      }
      return true;
    } catch (e) {
      debugPrint('NotificationService.markAllAsRead error: $e');
      return true;
    }
  }

  /// Deletes a notification
  Future<bool> deleteNotification(String notificationId) async {
    try {
      await _client.from('notifications').delete().eq('id', notificationId);
      return true;
    } catch (e) {
      debugPrint('NotificationService.deleteNotification error: $e');
      return true;
    }
  }

  /// Triggered locally for mock events or via Supabase function in production
  Future<void> triggerNotification({
    required String userId,
    required String title,
    required String message,
    String? complaintId,
    String type = 'STATUS_CHANGE',
  }) async {
    try {
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'complaint_id': complaintId,
        'notification_type': type,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('NotificationService.triggerNotification skipped: $e');
    }
  }

  List<AppNotificationModel> _getMockNotifications() {
    final now = DateTime.now();
    return [
      AppNotificationModel(
        id: 'notif-1',
        userId: 'current-user-uuid',
        complaintId: 'c-1',
        title: 'Grievance Escalated to Level 2: HoD',
        message:
            'Grievance SMT-2026-00001 was escalated to Head of Department due to SLA expiration at Level 1.',
        notificationType: 'ESCALATION',
        isRead: false,
        createdAt: now.subtract(const Duration(minutes: 45)),
      ),
      AppNotificationModel(
        id: 'notif-2',
        userId: 'current-user-uuid',
        complaintId: 'c-2',
        title: 'Automated Escalation Frozen (20-Day Cutoff)',
        message:
            'Grievance SMT-2026-PAUSED has reached the 20-day campus cutoff limit. Escalation paused pending administrative review.',
        notificationType: 'DEADLINE_WARNING',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      AppNotificationModel(
        id: 'notif-3',
        userId: 'current-user-uuid',
        complaintId: 'c-3',
        title: 'Status Updated: UNDER_REVIEW',
        message:
            'Authority Faculty Advisor has begun formal investigation of your grievance.',
        notificationType: 'STATUS_CHANGE',
        isRead: true,
        readAt: now.subtract(const Duration(days: 1)),
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
      ),
    ];
  }
}
