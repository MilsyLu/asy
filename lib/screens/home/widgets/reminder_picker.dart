import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_utils.dart';

/// The "Recordatorio" picker: a fixed set of relative offsets before the
/// task's scheduled time, plus a free "Personalizado" date+time.
///
/// Shared between [AddEditTaskPage] (create/edit, full page) and
/// [TaskCreatePanel] (inline creation on Home) so both use the exact same
/// bottom sheet, custom date+time flow and formatting — no duplicated logic
/// to drift apart.
enum ReminderOption {
  none,
  min5,
  min10,
  min15,
  min30,
  hour1,
  custom;

  String get label {
    switch (this) {
      case ReminderOption.none:
        return 'Sin recordatorio';
      case ReminderOption.min5:
        return '5 minutos antes';
      case ReminderOption.min10:
        return '10 minutos antes';
      case ReminderOption.min15:
        return '15 minutos antes';
      case ReminderOption.min30:
        return '30 minutos antes';
      case ReminderOption.hour1:
        return '1 hora antes';
      case ReminderOption.custom:
        return 'Personalizado';
    }
  }

  Duration? get offsetFromTask {
    switch (this) {
      case ReminderOption.none:
        return null;
      case ReminderOption.min5:
        return const Duration(minutes: 5);
      case ReminderOption.min10:
        return const Duration(minutes: 10);
      case ReminderOption.min15:
        return const Duration(minutes: 15);
      case ReminderOption.min30:
        return const Duration(minutes: 30);
      case ReminderOption.hour1:
        return const Duration(hours: 1);
      case ReminderOption.custom:
        return null;
    }
  }
}

/// Combines a task's [date] + "HH:MM" [hourStr] into a [DateTime], or null
/// if [hourStr] hasn't been picked yet / is malformed.
DateTime? taskDateTimeFromHour(DateTime date, String? hourStr) {
  if (hourStr == null) return null;
  final parts = hourStr.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

/// Infers which [ReminderOption] a stored `reminderTime` corresponds to,
/// relative to the task's own [taskDt] — used when editing an existing task
/// so the sheet preselects the matching option instead of always falling
/// back to "Personalizado".
ReminderOption detectReminderOption(DateTime? reminderTime, DateTime? taskDt) {
  if (reminderTime == null) return ReminderOption.none;
  if (taskDt == null) return ReminderOption.custom;
  final diff = taskDt.difference(reminderTime);
  for (final opt in ReminderOption.values) {
    final offset = opt.offsetFromTask;
    if (offset != null && diff == offset) return opt;
  }
  return ReminderOption.custom;
}

/// Human-readable label for the current reminder selection. Shows just the
/// time when the reminder falls on the same day as the task (the common
/// case); prefixes the short date when the user picked a different day.
String formatReminderLabel({
  required ReminderOption option,
  required DateTime? reminderDateTime,
  required DateTime? taskDateTime,
}) {
  switch (option) {
    case ReminderOption.none:
      return 'Sin recordatorio';
    case ReminderOption.custom:
      if (reminderDateTime == null) return 'Sin recordatorio';
      final sameDay =
          taskDateTime != null && AppDateUtils.isSameDay(reminderDateTime, taskDateTime);
      final time = AppDateUtils.formatTime12h(reminderDateTime);
      return sameDay ? time : '${AppDateUtils.formatShortDate(reminderDateTime)} · $time';
    default:
      return option.label;
  }
}

/// Result of a [pickReminder] interaction.
class ReminderPickResult {
  const ReminderPickResult({required this.option, required this.dateTime});
  final ReminderOption option;
  final DateTime? dateTime;
}

/// Shows the reminder bottom sheet (6 fixed offsets + "Personalizado"),
/// chaining into the custom date+time flow if the user picks that. Returns
/// null if the user cancels at any point (sheet dismissed, custom flow
/// cancelled) — callers should leave existing state untouched in that case.
Future<ReminderPickResult?> pickReminder(
  BuildContext context, {
  required ReminderOption current,
  required DateTime? currentReminderDateTime,
  required DateTime? taskDateTime,
}) async {
  final result = await showModalBottomSheet<ReminderOption>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      final colors = sheetCtx.colors;
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Icon(LucideIcons.bell, color: colors.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Recordatorio',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: colors.divider, height: 16),
            for (final opt in ReminderOption.values)
              InkWell(
                onTap: () => Navigator.pop(sheetCtx, opt),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        current == opt
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: current == opt ? colors.primary : colors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          opt.label,
                          style: TextStyle(
                            color: current == opt ? colors.primary : colors.textPrimary,
                            fontSize: 15,
                            fontWeight: current == opt ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (opt == ReminderOption.custom &&
                          current == ReminderOption.custom &&
                          currentReminderDateTime != null)
                        Text(
                          formatReminderLabel(
                            option: ReminderOption.custom,
                            reminderDateTime: currentReminderDateTime,
                            taskDateTime: taskDateTime,
                          ),
                          style: TextStyle(color: colors.textSecondary, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (!context.mounted || result == null) return null;

  if (result == ReminderOption.custom) {
    return _pickCustomReminder(
      context,
      taskDateTime: taskDateTime,
      initialReminderDateTime: currentReminderDateTime,
    );
  }

  if (result == ReminderOption.none) {
    return const ReminderPickResult(option: ReminderOption.none, dateTime: null);
  }

  if (taskDateTime != null) {
    return ReminderPickResult(option: result, dateTime: taskDateTime.subtract(result.offsetFromTask!));
  }
  return ReminderPickResult(option: result, dateTime: null);
}

/// Custom reminder: lets the user pick a date (defaulting to the task's own
/// date, but any earlier day is allowed) followed by a time, instead of
/// forcing the reminder onto the task's own day.
Future<ReminderPickResult?> _pickCustomReminder(
  BuildContext context, {
  required DateTime? taskDateTime,
  required DateTime? initialReminderDateTime,
}) async {
  final initial = initialReminderDateTime ?? taskDateTime ?? DateTime.now();

  final pickedDate = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: taskDateTime ?? DateTime.now().add(const Duration(days: 365 * 2)),
    helpText: 'Fecha del recordatorio',
  );
  if (!context.mounted || pickedDate == null) return null;

  DateTime picked = DateTime(
    pickedDate.year,
    pickedDate.month,
    pickedDate.day,
    initial.hour,
    initial.minute,
  );

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      final colors = dialogCtx.colors;
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(LucideIcons.clock, color: colors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hora del recordatorio',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Para el ${AppDateUtils.formatShortDate(pickedDate)}',
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Divider(color: colors.divider, height: 1),
            ),
            SizedBox(
              height: 200,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Theme.of(dialogCtx).brightness,
                  textTheme: CupertinoTextThemeData(
                    pickerTextStyle: TextStyle(color: colors.textPrimary, fontSize: 21),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: picked,
                  use24hFormat: false,
                  onDateTimeChanged: (dt) => picked = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    dt.hour,
                    dt.minute,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('Cancelar', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(dialogCtx, true),
                      child: const Text(
                        'Confirmar',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  if (confirmed != true) return null;
  return ReminderPickResult(option: ReminderOption.custom, dateTime: picked);
}
