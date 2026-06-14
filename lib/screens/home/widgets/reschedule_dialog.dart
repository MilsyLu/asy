import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';
import '../../../services/task_repository.dart';
import '../../../widgets/confirm_dialog.dart';

/// Quick-action dialog used by [TaskCard] to change a task's date/hour.
/// Increments `rescheduledCount` and sets the status to "Reprogramada".
Future<void> showRescheduleDialog(BuildContext context, TaskModel task) async {
  final catalog = context.read<CatalogProvider>();
  final repo = context.read<TaskRepository>();

  DateTime selectedDate = AppDateUtils.parseDateKey(task.date);
  String? selectedHour = catalog.availableHours.any((h) => h.hour == task.hour)
      ? task.hour
      : (catalog.availableHours.isNotEmpty ? catalog.availableHours.first.hour : task.hour);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final colors = context.colors;
          return AlertDialog(
            title: const Text('Reprogramar tarea'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${task.clientName} · ${catalog.taskTypeName(task.taskTypeId)}',
                  style: TextStyle(color: colors.textSecondary),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Nueva fecha',
                      prefixIcon: Icon(LucideIcons.calendar, color: colors.primary),
                    ),
                    child: Text(AppDateUtils.formatShortDate(selectedDate)),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedHour,
                  decoration: InputDecoration(
                    labelText: 'Nueva hora',
                    prefixIcon: Icon(LucideIcons.clock, color: colors.primary),
                  ),
                  dropdownColor: colors.surface,
                  items: catalog.availableHours
                      .map((h) => DropdownMenuItem(value: h.hour, child: Text(h.hour)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedHour = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: selectedHour == null
                    ? null
                    : () async {
                        await _confirmReschedule(
                          context: dialogContext,
                          task: task,
                          newDate: selectedDate,
                          newHour: selectedHour!,
                          repo: repo,
                          catalog: catalog,
                        );
                      },
                child: const Text('Reprogramar'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true && context.mounted) {
    SnackbarUtils.showSuccess(context, 'Tarea reprogramada');
  }
}

Future<void> _confirmReschedule({
  required BuildContext context,
  required TaskModel task,
  required DateTime newDate,
  required String newHour,
  required TaskRepository repo,
  required CatalogProvider catalog,
}) async {
  final newDateKey = AppDateUtils.formatDateKey(newDate);

  final hasConflict = await repo.hasConflict(
    assignedUserId: task.assignedUserId,
    date: newDateKey,
    hour: newHour,
    excludeTaskId: task.id,
  );

  if (hasConflict) {
    if (!context.mounted) return;
    final proceed = await showConfirmDialog(
      context,
      title: 'Conflicto de horario',
      message:
          '${catalog.userName(task.assignedUserId)} ya tiene una tarea asignada el '
          '${AppDateUtils.formatShortDate(newDate)} a las $newHour. ¿Deseas continuar de todas formas?',
      confirmLabel: 'Continuar',
    );
    if (!proceed) return;
  }

  final reminderStillValid = Validators.isReminderValid(
    taskDate: newDate,
    taskHour: newHour,
    reminderDateTime: task.reminderTime,
  );

  final rescheduledStatusId = catalog.rescheduledStatusId;
  if (rescheduledStatusId == null) {
    if (!context.mounted) return;
    SnackbarUtils.showError(
        context, 'No existe un estado "Reprogramada" configurado');
    return;
  }

  if (!context.mounted) return;

  try {
    await repo.rescheduleTask(
      taskId: task.id,
      newDate: newDateKey,
      newHour: newHour,
      rescheduledStatusId: rescheduledStatusId,
      currentRescheduledCount: task.rescheduledCount,
      reminderTime: reminderStillValid ? task.reminderTime : null,
      clearReminder: !reminderStillValid && task.reminderTime != null,
    );
    if (context.mounted) {
      if (!reminderStillValid && task.reminderTime != null) {
        SnackbarUtils.showInfo(
          context,
          'El recordatorio se eliminó porque ya no es anterior a la nueva hora',
        );
      }
      Navigator.of(context).pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}
