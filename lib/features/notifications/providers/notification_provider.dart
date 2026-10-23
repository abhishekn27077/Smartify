import 'package:flutter/material.dart';
import 'package:smartify/features/notifications/models/app_notification_model.dart';
import 'package:smartify/features/notifications/services/notification_service.dart';

/// SMARTIFY Notification Provider
/// Manages notification state, unread counts, and real-time read updates.
class NotificationProvider extends ChangeNotifier {
  final NotificationService _service;

  NotificationProvider({NotificationService? service})
      : _service = service ?? NotificationService();

  List<AppNotificationModel> _notifications = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<AppNotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> loadNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notifications = await _service.fetchNotifications();
    } catch (e) {
      _errorMessage = 'Failed to load notifications: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markAsRead(String notificationId) async {
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx != -1 && !_notifications[idx].isRead) {
      _notifications[idx] =
          _notifications[idx].copyWith(isRead: true, readAt: DateTime.now());
      notifyListeners();
      await _service.markAsRead(notificationId);
    }
  }

  Future<void> markAllAsRead() async {
    for (int i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] =
            _notifications[i].copyWith(isRead: true, readAt: DateTime.now());
      }
    }
    notifyListeners();
    await _service.markAllAsRead();
  }

  Future<void> deleteNotification(String notificationId) async {
    _notifications.removeWhere((n) => n.id == notificationId);
    notifyListeners();
    await _service.deleteNotification(notificationId);
  }
}
