import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../models/task_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/catalog_provider.dart';
import '../../../services/task_repository.dart';
import '../../../widgets/confirm_dialog.dart';
import '../add_edit_task_page.dart';
import 'reschedule_dialog.dart';
import 'task_detail_dialog.dart';

/// Card representation of a single task, used on Home / Calendar / Week.
/// Shows a thin gold left border, client info, status chip and the
/// Editar / Completar / Reprogramar action row.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task});

  final TaskModel task;

  Future<void> _callClient(BuildContext context) async {
    final phone = Validators.cleanPhone(task.clientPhone);
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      SnackbarUtils.showError(context, 'No se pudo iniciar la llamada');
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();

    final isPending = task.statusId == catalog.pendingStatusId;
    final isCompleted = task.statusId == catalog.completedStatusId;
    final canEdit = auth.isSuperAdmin || isPending;
    final canComplete = !isCompleted;
    final canReschedule = !isCompleted;

    final taskType = catalog.taskTypeName(task.taskTypeId);
    final statusName = catalog.statusName(task.statusId);
    final assignedName = catalog.userName(task.assignedUserId);
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
        boxShadow: const [],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.clock, size: 16, color: colors.primary),
                        const SizedBox(width: 6),
                        Text(
                          task.hour,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            taskType,
                            style: TextStyle(
                              color: colors.primaryLight,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _StatusChip(statusName: statusName, isCompleted: isCompleted),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(LucideIcons.userCircle, size: 15, color: colors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.clientName,
                            style: TextStyle(color: colors.textPrimary, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (task.clientPhone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _callClient(context),
                        child: Row(
                          children: [
                            Icon(LucideIcons.phone, size: 15, color: colors.primary),
                            const SizedBox(width: 6),
                            Text(
                              Validators.formatPhone(task.clientPhone),
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (task.observations.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        task.observations,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(LucideIcons.userCheck, size: 13, color: colors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Encargado: $assignedName',
                            style: TextStyle(color: colors.textSecondary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (task.rescheduledCount > 0)
                          Text(
                            'Reprogramada x${task.rescheduledCount}',
                            style: TextStyle(color: colors.error, fontSize: 11),
                          ),
                      ],
                    ),
                    if (canEdit || canComplete || canReschedule) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 4,
                        children: [
                          if (canEdit)
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AddEditTaskPage(existingTask: task),
                                  ),
                                );
                              },
                              icon: const Icon(LucideIcons.pencil, size: 16),
                              label: const Text('Editar'),
                            ),
                          if (canReschedule)
                            TextButton.icon(
                              onPressed: () => showRescheduleDialog(context, task),
                              icon: const Icon(LucideIcons.repeat, size: 16),
                              label: const Text('Reprogramar'),
                            ),
                          if (canComplete)
                            TextButton.icon(
                              onPressed: () => completeTaskWithConfirm(context, task),
                              style: TextButton.styleFrom(foregroundColor: colors.success),
                              icon: const Icon(LucideIcons.checkCircle, size: 16),
                              label: const Text('Completar'),
                            ),
                        ],
                      ),
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.statusName, required this.isCompleted});

  final String statusName;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isReprogramada = statusName == AppStatusNames.reprogramada;
    final color = isCompleted
        ? colors.success
        : isReprogramada
            ? colors.error
            : colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        statusName,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Marks [task] as completed after confirmation, showing a success/error
/// snackbar. Shared by [TaskCard]'s action row and the Home agenda widgets
/// (quick "Completar" buttons on the next-task card and agenda tiles).
Future<void> completeTaskWithConfirm(BuildContext context, TaskModel task) async {
  final catalog = context.read<CatalogProvider>();
  final repo = context.read<TaskRepository>();
  final completedId = catalog.completedStatusId;
  if (completedId == null) {
    SnackbarUtils.showError(context, 'No existe un estado "Completada" configurado');
    return;
  }
  final confirm = await showConfirmDialog(
    context,
    title: 'Completar tarea',
    message: '¿Marcar la tarea de ${task.clientName} a las ${task.hour} como completada?',
    confirmLabel: 'Completar',
  );
  if (!confirm) return;
  try {
    await repo.completeTask(task.id, completedId);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Tarea completada');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}

/// Bottom sheet with quick actions (Editar / Reprogramar / Completar) for
/// a task, used by long-press gestures on the Calendar and Week views.
Future<void> showTaskQuickActionsSheet(BuildContext context, TaskModel task) {
  final colors = context.colors;
  final catalog = context.read<CatalogProvider>();
  final auth = context.read<AuthProvider>();

  final isPending = task.statusId == catalog.pendingStatusId;
  final isCompleted = task.statusId == catalog.completedStatusId;
  final canEdit = auth.isSuperAdmin || isPending;
  final canComplete = !isCompleted;
  final canReschedule = !isCompleted;

  return showModalBottomSheet(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(LucideIcons.clock, color: colors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${task.hour} · ${task.clientName}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(LucideIcons.fileText, color: colors.primary),
              title: const Text('Ver detalle completo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showTaskDetailDialog(context, task);
              },
            ),
            if (canEdit)
              ListTile(
                leading: Icon(LucideIcons.pencil, color: colors.primary),
                title: const Text('Editar'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AddEditTaskPage(existingTask: task)),
                  );
                },
              ),
            if (canReschedule)
              ListTile(
                leading: Icon(LucideIcons.repeat, color: colors.primary),
                title: const Text('Reprogramar'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showRescheduleDialog(context, task);
                },
              ),
            if (canComplete)
              ListTile(
                leading: Icon(LucideIcons.checkCircle, color: colors.success),
                title: const Text('Completar'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final repo = context.read<TaskRepository>();
                  final completedId = catalog.completedStatusId;
                  if (completedId == null) {
                    if (context.mounted) {
                      SnackbarUtils.showError(
                          context, 'No existe un estado "Completada" configurado');
                    }
                    return;
                  }
                  try {
                    await repo.completeTask(task.id, completedId);
                    if (context.mounted) {
                      SnackbarUtils.showSuccess(context, 'Tarea completada');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      SnackbarUtils.showError(
                          context, SnackbarUtils.firebaseErrorMessage(e));
                    }
                  }
                },
              ),
            if (!canEdit && !canComplete && !canReschedule)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Esta tarea ya fue completada.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
