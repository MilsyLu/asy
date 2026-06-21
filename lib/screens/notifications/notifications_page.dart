import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

/// In-app notification history (Sprint 7.4). Read-only list backed by the
/// `notifications` collection that Cloud Functions populate alongside every
/// FCM push, so it survives the user dismissing/missing the system push.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final repo = context.read<NotificationRepository>();
    final userId = context.read<AuthProvider>().appUser!.id;

    // Sprint 7.4.4: a single shared listener for both the AppBar action and
    // the body list — previously each opened its own independent
    // `watchNotifications` subscription for the same data.
    return StreamBuilder<List<NotificationModel>>(
      stream: repo.watchNotifications(userId),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final hasUnread = notifications.any((n) => !n.isRead);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Notificaciones'),
            actions: [
              if (hasUnread)
                TextButton(
                  onPressed: () => repo.markAllAsRead(userId),
                  child: const Text('Marcar todas como leídas'),
                ),
              PopupMenuButton<void>(
                icon: const Icon(LucideIcons.moreVertical),
                itemBuilder: (menuContext) => [
                  PopupMenuItem<void>(
                    onTap: () => _confirmClearHistory(context, repo, userId),
                    child: const Text('Vaciar historial'),
                  ),
                ],
              ),
            ],
          ),
          body: _NotificationsBody(
            snapshot: snapshot,
            notifications: notifications,
            colors: colors,
            onTapNotification: (notification) {
              if (!notification.isRead) {
                repo.markAsRead(notification.id);
              }
            },
            onDeleteNotification: (notification) {
              repo.deleteNotification(notification.id);
              debugPrint(
                '[NOTIFICATIONS]\ndeleted_single\nid=${notification.id}\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
              );
            },
          ),
        );
      },
    );
  }
}

/// Shows the "Vaciar historial" confirmation (Sprint 7.4.7 Objetivo F) and,
/// if confirmed, deletes every notification belonging to [userId].
Future<void> _confirmClearHistory(
  BuildContext context,
  NotificationRepository repo,
  String userId,
) async {
  final confirm = await showConfirmDialog(
    context,
    title: '¿Deseas eliminar todas tus notificaciones?',
    message: 'Esta acción no se puede deshacer.',
    confirmLabel: 'Eliminar todo',
    destructive: true,
    confirmForegroundColor: Colors.white,
  );
  if (!confirm) return;
  await repo.deleteAllNotifications(userId);
  debugPrint(
    '[NOTIFICATIONS]\ndeleted_all\nuserId=$userId\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
  );
}

class _NotificationsBody extends StatelessWidget {
  const _NotificationsBody({
    required this.snapshot,
    required this.notifications,
    required this.colors,
    required this.onTapNotification,
    required this.onDeleteNotification,
  });

  final AsyncSnapshot<List<NotificationModel>> snapshot;
  final List<NotificationModel> notifications;
  final AppColorsExtension colors;
  final ValueChanged<NotificationModel> onTapNotification;
  final ValueChanged<NotificationModel> onDeleteNotification;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const LoadingIndicator();
    }
    if (snapshot.hasError) {
      debugPrint('[Notifications] watchNotifications stream error: ${snapshot.error}');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertCircle, color: colors.error, size: 40),
              const SizedBox(height: 12),
              Text(
                'Error al cargar las notificaciones.\n'
                'Es posible que el índice de Firestore no esté desplegado.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (notifications.isEmpty) {
      return const EmptyState(
        message: 'No tienes notificaciones',
        icon: LucideIcons.bellOff,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: notifications.length,
      itemBuilder: (context, i) {
        final notification = notifications[i];
        return Dismissible(
          key: ValueKey(notification.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: colors.error,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.trash2, color: Colors.white),
          ),
          onDismissed: (_) => onDeleteNotification(notification),
          child: _NotificationCard(
            notification: notification,
            onTap: () => onTapNotification(notification),
            onDelete: () => onDeleteNotification(notification),
          ),
        );
      },
    );
  }
}

IconData _iconForType(String type) {
  switch (type) {
    case AppNotificationTypes.taskCreatedAssigned:
      return LucideIcons.clipboardList;
    case AppNotificationTypes.taskCreatedGroup:
      return LucideIcons.users;
    case AppNotificationTypes.taskCreatedAdmin:
      return LucideIcons.shieldCheck;
    case AppNotificationTypes.taskReminder:
      return LucideIcons.bell;
    default:
      return LucideIcons.bell;
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRead = notification.isRead;
    final createdAt = notification.createdAt;

    return Material(
      color: isRead ? colors.surface : colors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isRead ? colors.divider : colors.primary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForType(notification.type), color: colors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Eliminar',
                            icon: Icon(LucideIcons.trash2,
                                size: 16, color: colors.textSecondary),
                            onPressed: onDelete,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(LucideIcons.calendar, size: 12, color: colors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          createdAt != null
                              ? AppDateUtils.formatShortDate(createdAt)
                              : '-',
                          style: TextStyle(color: colors.textSecondary, fontSize: 11),
                        ),
                        const SizedBox(width: 10),
                        Icon(LucideIcons.clock, size: 12, color: colors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          createdAt != null
                              ? AppDateUtils.formatTime12h(createdAt)
                              : '-',
                          style: TextStyle(color: colors.textSecondary, fontSize: 11),
                        ),
                        const Spacer(),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isRead
                                ? colors.textSecondary.withValues(alpha: 0.4)
                                : colors.error,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isRead ? 'Leída' : 'No leída',
                          style: TextStyle(
                            color: isRead ? colors.textSecondary : colors.error,
                            fontSize: 11,
                            fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                          ),
                        ),
                      ],
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
