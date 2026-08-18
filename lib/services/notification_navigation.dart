import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/snackbar_utils.dart';
import '../core/utils/task_visibility.dart';
import '../providers/auth_provider.dart';
import '../screens/home/widgets/task_detail_dialog.dart';
import '../screens/support_cases/support_case_detail_view.dart';
import 'support_case_repository.dart';
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

  final taskRepo = context.read<TaskRepository>();
  final task = await taskRepo.watchTask(taskId).first;
  if (!context.mounted) return;

  if (task == null ||
      task.isDeleted ||
      !isTaskVisibleToUser(task: task, user: user)) {
    SnackbarUtils.showError(context, 'Esta tarea ya no está disponible.');
    return;
  }

  await showTaskDetailDialog(context, task);
}

/// The Casos de Soporte equivalent of [openTaskFromNotification] — pushes
/// [caseId]'s detail as a full page on top of whatever's currently on
/// screen (mirrors how the mobile in-app flow already opens a case, see
/// `support_cases_page.dart._openDetail`), rather than trying to select it
/// inside the desktop split-view's local state, which this global entry
/// point has no access to.
Future<void> openSupportCaseFromNotification(String? caseId) async {
  if (caseId == null || caseId.isEmpty) return;
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;

  final auth = context.read<AuthProvider>();
  if (auth.appUser == null) return;

  final repo = context.read<SupportCaseRepository>();
  final caseModel = await repo.watchCase(caseId).first.catchError((_) => null);
  if (!context.mounted) return;

  if (caseModel == null) {
    SnackbarUtils.showError(context, 'Este caso ya no está disponible.');
    return;
  }

  await rootNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => SupportCaseDetailView(caseId: caseId, showAppBar: true)),
  );
}

/// Dispatches based on whichever id is present in a raw FCM `data` map —
/// used by entry points that already have the full payload (foreground
/// click, background/terminated relaunch). A task takes priority if a
/// message somehow carried both (never happens today — every push carries
/// exactly one).
Future<void> openNotificationFromData(Map<String, dynamic> data) async {
  final taskId = data['taskId'] as String?;
  final caseId = data['caseId'] as String?;
  if (taskId != null && taskId.isNotEmpty) {
    await openTaskFromNotification(taskId);
  } else if (caseId != null && caseId.isNotEmpty) {
    await openSupportCaseFromNotification(caseId);
  }
}

/// A mobile local-notification's `payload` is a single plain string
/// (`flutter_local_notifications` carries no structured data), so it's
/// encoded as `"task:<id>"`/`"case:<id>"` when the notification is shown
/// (see `notification_service.dart`'s `.show()` call) and decoded back
/// here. An unprefixed payload (no `:`) is treated as a bare taskId, for
/// backward compatibility with any notification already in the OS tray
/// from before this format existed.
Future<void> openNotificationFromPayload(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  final colonIndex = payload.indexOf(':');
  if (colonIndex == -1) {
    await openTaskFromNotification(payload);
    return;
  }
  final kind = payload.substring(0, colonIndex);
  final id = payload.substring(colonIndex + 1);
  if (kind == 'case') {
    await openSupportCaseFromNotification(id);
  } else {
    await openTaskFromNotification(id);
  }
}
