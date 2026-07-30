import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/snackbar_utils.dart';
import '../core/utils/task_visibility.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../screens/home/widgets/task_detail_dialog.dart';
import 'task_repository.dart';

/// Attached to [MaterialApp] (see `app.dart`) so a notification tap — which
/// has no [BuildContext] of its own, since it can fire from an FCM
/// background/foreground callback, a service-worker-driven URL param read
/// at cold start, etc. — can still reach into the live widget tree and open
/// a dialog on top of whatever screen is currently showing.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The single place every notification-tap entry point routes through: the
/// in-app notification list, an OS push click (foreground or
/// background/terminated), and a mobile local-notification tap. Opens
/// [taskId]'s detail dialog on top of whatever's currently on screen.
///
/// Quietly no-ops instead of erroring if the app isn't ready yet (context
/// still null — e.g. a push tapped before the first frame), or shows a
/// plain message if the task can no longer be reached (deleted, or the
/// signed-in user lost visibility into it, e.g. reassigned to another
/// team) — both are ordinary, reachable states for a notification that
/// might be hours or days old by the time it's tapped.
Future<void> openTaskFromNotification(String? taskId) async {
  if (taskId == null || taskId.isEmpty) return;
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;

  final auth = context.read<AuthProvider>();
  final user = auth.appUser;
  if (user == null) return;

  final catalog = context.read<CatalogProvider>();
  final taskRepo = context.read<TaskRepository>();
  final task = await taskRepo.watchTask(taskId).first;
  if (!context.mounted) return;

  if (task == null ||
      task.isDeleted ||
      !isTaskVisibleToUser(task: task, user: user, catalog: catalog)) {
    SnackbarUtils.showError(context, 'Esta tarea ya no está disponible.');
    return;
  }

  await showTaskDetailDialog(context, task);
}
