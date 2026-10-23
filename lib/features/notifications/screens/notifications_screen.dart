import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/notifications/models/app_notification_model.dart';
import 'package:smartify/features/notifications/providers/notification_provider.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/complaint_detail_screen.dart';
import 'package:smartify/features/tracking/services/tracking_service.dart';

/// SMARTIFY Role-Specific In-App Notifications Screen
/// Groups alerts into Today, Yesterday, and Earlier sections, provides clear
/// type icons, read/unread states, and direct navigation to grievance details.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _filterOnlyUnread = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _handleNotificationTap(AppNotificationModel item) async {
    final prov = context.read<NotificationProvider>();
    if (!item.isRead) {
      await prov.markAsRead(item.id);
    }

    if (item.complaintId != null && mounted) {
      final service = TrackingService();
      final grievance = await service.fetchComplaintById(item.complaintId!);
      if (mounted && grievance != null) {
        await context
            .read<StudentTrackingProvider>()
            .selectComplaint(grievance);
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ComplaintDetailScreen(grievance: grievance),
          ),
        );
      }
    }
  }

  IconData _getIconForNotification(AppNotificationModel item) {
    final t = '${item.title} ${item.notificationType}'.toUpperCase();
    if (t.contains('ASSIGN') || t.contains('INTAKE')) {
      return Icons.assignment_ind_outlined;
    }
    if (t.contains('FORWARD') || t.contains('ESCALAT') || t.contains('TIER')) {
      return Icons.trending_up_rounded;
    }
    if (t.contains('RESOLV')) {
      return Icons.check_circle_outline_rounded;
    }
    if (t.contains('REJECT')) {
      return Icons.cancel_outlined;
    }
    if (t.contains('SLA') || t.contains('DEADLINE') || t.contains('DUE')) {
      return Icons.timer_outlined;
    }
    if (t.contains('CUTOFF') || t.contains('PAUS')) {
      return Icons.pause_circle_outline_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  Color _getColorForNotification(AppNotificationModel item) {
    final t = '${item.title} ${item.notificationType}'.toUpperCase();
    if (t.contains('RESOLV')) {
      return AppColors.statusResolved;
    }
    if (t.contains('REJECT')) {
      return AppColors.error;
    }
    if (t.contains('FORWARD') || t.contains('ESCALAT')) {
      return AppColors.secondary;
    }
    if (t.contains('SLA') || t.contains('DEADLINE')) {
      return AppColors.statusPending;
    }
    if (t.contains('CUTOFF')) {
      return AppColors.statusCutoffPaused;
    }
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<NotificationProvider>();
    final auth = context.watch<AuthProvider>();
    final role = auth.currentRole.toUpperCase();

    final displayList = _filterOnlyUnread
        ? provider.notifications.where((n) => !n.isRead).toList()
        : provider.notifications;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayList = <AppNotificationModel>[];
    final yesterdayList = <AppNotificationModel>[];
    final earlierList = <AppNotificationModel>[];

    for (final item in displayList) {
      final date = item.createdAt.toLocal();
      if (_isSameDay(date, today)) {
        todayList.add(item);
      } else if (_isSameDay(date, yesterday)) {
        yesterdayList.add(item);
      } else {
        earlierList.add(item);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$role Notifications',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          if (provider.unreadCount > 0)
            TextButton(
              onPressed: provider.markAllAsRead,
              child: const Text('Mark all read',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Notifications',
            onPressed: provider.loadNotifications,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
              height: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter chips bar
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('All (${provider.notifications.length})',
                        style: const TextStyle(fontSize: 11)),
                    selected: !_filterOnlyUnread,
                    onSelected: (_) =>
                        setState(() => _filterOnlyUnread = false),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  ChoiceChip(
                    label: Text('Unread (${provider.unreadCount})',
                        style: const TextStyle(fontSize: 11)),
                    selected: _filterOnlyUnread,
                    onSelected: (_) => setState(() => _filterOnlyUnread = true),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: provider.loadNotifications,
                child: provider.isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.space16),
                        child: StateLoadingShimmer(height: 280),
                      )
                    : provider.errorMessage != null
                        ? StateErrorView(
                            message: provider.errorMessage!,
                            onRetry: provider.loadNotifications,
                          )
                        : displayList.isEmpty
                            ? StateEmptyView(
                                title: _filterOnlyUnread
                                    ? 'No unread notifications'
                                    : 'No notifications',
                                subtitle: _filterOnlyUnread
                                    ? 'No unread updates to review.'
                                    : "You're all caught up.",
                                icon: Icons.notifications_none_rounded,
                              )
                            : ListView(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.space16,
                                    vertical: AppSpacing.space8),
                                children: [
                                  if (todayList.isNotEmpty) ...[
                                    _buildSectionHeader('Today', theme),
                                    ...todayList.map((n) =>
                                        _buildNotificationTile(n, theme)),
                                    const SizedBox(height: AppSpacing.space12),
                                  ],
                                  if (yesterdayList.isNotEmpty) ...[
                                    _buildSectionHeader('Yesterday', theme),
                                    ...yesterdayList.map((n) =>
                                        _buildNotificationTile(n, theme)),
                                    const SizedBox(height: AppSpacing.space12),
                                  ],
                                  if (earlierList.isNotEmpty) ...[
                                    _buildSectionHeader('Earlier', theme),
                                    ...earlierList.map((n) =>
                                        _buildNotificationTile(n, theme)),
                                    const SizedBox(height: AppSpacing.space12),
                                  ],
                                ],
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNotificationTile(AppNotificationModel item, ThemeData theme) {
    final icon = _getIconForNotification(item);
    final color = _getColorForNotification(item);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        side: BorderSide(
          color: item.isRead
              ? theme.colorScheme.outline.withValues(alpha: 0.4)
              : color.withValues(alpha: 0.5),
          width: item.isRead ? 1 : 1.5,
        ),
      ),
      color: item.isRead
          ? theme.colorScheme.surface
          : color.withValues(alpha: 0.04),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        onTap: () => _handleNotificationTap(item),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: AppSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: item.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!item.isRead) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          AppDateTimeUtils.formatLocalTime(item.createdAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.75),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
