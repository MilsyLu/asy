import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/gold_button.dart';

enum _ReminderOption {
  none,
  min5,
  min10,
  min15,
  min30,
  hour1,
  custom;

  String get label {
    switch (this) {
      case _ReminderOption.none:
        return 'Sin recordatorio';
      case _ReminderOption.min5:
        return '5 minutos antes';
      case _ReminderOption.min10:
        return '10 minutos antes';
      case _ReminderOption.min15:
        return '15 minutos antes';
      case _ReminderOption.min30:
        return '30 minutos antes';
      case _ReminderOption.hour1:
        return '1 hora antes';
      case _ReminderOption.custom:
        return 'Personalizado';
    }
  }

  Duration? get offsetFromTask {
    switch (this) {
      case _ReminderOption.none:
        return null;
      case _ReminderOption.min5:
        return const Duration(minutes: 5);
      case _ReminderOption.min10:
        return const Duration(minutes: 10);
      case _ReminderOption.min15:
        return const Duration(minutes: 15);
      case _ReminderOption.min30:
        return const Duration(minutes: 30);
      case _ReminderOption.hour1:
        return const Duration(hours: 1);
      case _ReminderOption.custom:
        return null;
    }
  }
}

/// Form used to both create and edit a task.
///
/// Pass [existingTask] to edit, or [initialDate] to pre-fill the date
/// when creating a new task from the Calendar/Week view.
class AddEditTaskPage extends StatefulWidget {
  const AddEditTaskPage({super.key, this.existingTask, this.initialDate});

  final TaskModel? existingTask;
  final DateTime? initialDate;

  @override
  State<AddEditTaskPage> createState() => _AddEditTaskPageState();
}

class _AddEditTaskPageState extends State<AddEditTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _clientNameController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  final _observationsController = TextEditingController();

  late DateTime _selectedDate;
  String? _selectedHour;
  String? _assignedUserId;
  String? _taskTypeId;
  String? _statusId;
  String? _groupId;
  bool _visibleToAllGroups = false;
  DateTime? _reminderDateTime;
  _ReminderOption _reminderOption = _ReminderOption.none;
  bool _isSaving = false;

  bool get _isEditing => widget.existingTask != null;

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    if (task != null) {
      _selectedDate = AppDateUtils.parseDateKey(task.date);
      _selectedHour = task.hour;
      _assignedUserId = task.assignedUserId;
      _taskTypeId = task.taskTypeId;
      _statusId = task.statusId;
      _clientNameController.text = task.clientName;
      _clientPhoneController.text = task.clientPhone;
      _observationsController.text = task.observations;
      _reminderDateTime = task.reminderTime;
      _groupId = task.groupId;
      _visibleToAllGroups = task.visibleToAllGroups;
      _reminderOption = _detectOption(
        _reminderDateTime,
        _taskDateTimeFromHour(_selectedDate, _selectedHour),
      );
    } else {
      _selectedDate = widget.initialDate ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientPhoneController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Reminder helpers
  // ---------------------------------------------------------------------------

  static _ReminderOption _detectOption(
      DateTime? reminderTime, DateTime? taskDt) {
    if (reminderTime == null) return _ReminderOption.none;
    if (taskDt == null) return _ReminderOption.custom;
    final diff = taskDt.difference(reminderTime);
    for (final opt in _ReminderOption.values) {
      final offset = opt.offsetFromTask;
      if (offset != null && diff == offset) return opt;
    }
    return _ReminderOption.custom;
  }

  static DateTime? _taskDateTimeFromHour(DateTime date, String? hourStr) {
    if (hourStr == null) return null;
    final parts = hourStr.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? _taskDateTime() =>
      _taskDateTimeFromHour(_selectedDate, _selectedHour);

  String _reminderLabel() {
    switch (_reminderOption) {
      case _ReminderOption.none:
        return 'Sin recordatorio';
      case _ReminderOption.custom:
        return _reminderDateTime != null
            ? _formatReminderDateTime(_reminderDateTime!)
            : 'Sin recordatorio';
      default:
        return _reminderOption.label;
    }
  }

  /// Shows just the time when the reminder falls on the same day as the
  /// task (the common case, unchanged from before Sprint 7.4.9B); prefixes
  /// the short date when the user picked a different day (e.g. the day
  /// before), so that distinction is always visible rather than implied.
  String _formatReminderDateTime(DateTime dt) {
    final taskDt = _taskDateTime();
    final sameDay = taskDt != null && AppDateUtils.isSameDay(dt, taskDt);
    final time = AppDateUtils.formatTime12h(dt);
    return sameDay ? time : '${AppDateUtils.formatShortDate(dt)} · $time';
  }

  // ---------------------------------------------------------------------------
  // Picker sheets
  // ---------------------------------------------------------------------------

  Future<void> _showReminderSheet() async {
    final current = _reminderOption;
    final reminderDt = _reminderDateTime;

    final result = await showModalBottomSheet<_ReminderOption>(
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
              for (final opt in _ReminderOption.values)
                InkWell(
                  onTap: () => Navigator.pop(sheetCtx, opt),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Icon(
                          current == opt
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: current == opt
                              ? colors.primary
                              : colors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            opt.label,
                            style: TextStyle(
                              color: current == opt
                                  ? colors.primary
                                  : colors.textPrimary,
                              fontSize: 15,
                              fontWeight: current == opt
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (opt == _ReminderOption.custom &&
                            current == _ReminderOption.custom &&
                            reminderDt != null)
                          Text(
                            _formatReminderDateTime(reminderDt),
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 13),
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

    if (!mounted || result == null) return;

    if (result == _ReminderOption.custom) {
      await _showCustomReminderPicker();
      return;
    }

    final taskDt = _taskDateTime();
    setState(() {
      _reminderOption = result;
      if (result == _ReminderOption.none) {
        _reminderDateTime = null;
      } else if (taskDt != null) {
        _reminderDateTime = taskDt.subtract(result.offsetFromTask!);
      }
    });
  }

  /// Custom reminder: lets the user pick a date (defaulting to the task's
  /// own date, but any earlier day is allowed — Sprint 7.4.9B Objetivo A/B)
  /// followed by a time, instead of forcing the reminder onto the task's
  /// own day as the previous time-only picker did.
  Future<void> _showCustomReminderPicker() async {
    final taskDt = _taskDateTime();
    final initial = _reminderDateTime ?? taskDt ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: taskDt ?? DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: 'Fecha del recordatorio',
    );
    if (!mounted || pickedDate == null) return;

    DateTime picked = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      initial.hour,
      initial.minute,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final colors = dialogCtx.colors;
        return Dialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
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
                      child: Icon(LucideIcons.clock,
                          color: colors.primary, size: 22),
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
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
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
                      pickerTextStyle: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 21,
                      ),
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
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          setState(() {
                            _reminderOption = _ReminderOption.custom;
                            _reminderDateTime = picked;
                          });
                          Navigator.pop(dialogCtx);
                        },
                        child: const Text(
                          'Confirmar',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
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
  }

  // ---------------------------------------------------------------------------
  // Other helpers
  // ---------------------------------------------------------------------------

  /// Active users eligible for "Encargado" (Sprint 7.3.1 Part 6: deactivated
  /// users must not appear in this selector for new assignments). The task's
  /// already-assigned user is always included even if inactive, mirroring
  /// the existing groupOptions pattern below — otherwise editing a task
  /// previously assigned to a since-deactivated worker would silently blank
  /// out the field.
  List<AppUser> _assignableUsers(CatalogProvider catalog, AppUser current) {
    final pool = current.groupId != null
        ? (catalog.usersInGroup(current.groupId).isNotEmpty
            ? catalog.usersInGroup(current.groupId)
            : catalog.users)
        : catalog.users;
    final active = pool.where((u) => u.isActive).toList();
    if (_assignedUserId != null && !active.any((u) => u.id == _assignedUserId)) {
      final assignedUser = catalog.userById(_assignedUserId);
      if (assignedUser != null) active.add(assignedUser);
    }
    return active;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    debugPrint(
      '[CREATE_TASK]\nsave_pressed\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!_formKey.currentState!.validate()) return;
    if (_selectedHour == null) {
      SnackbarUtils.showError(context, 'Selecciona una hora');
      return;
    }
    if (_assignedUserId == null) {
      SnackbarUtils.showError(context, 'Selecciona un encargado');
      return;
    }
    if (_taskTypeId == null) {
      SnackbarUtils.showError(context, 'Selecciona un tipo de tarea');
      return;
    }
    if (_groupId == null) {
      SnackbarUtils.showError(context, 'Selecciona un grupo');
      return;
    }

    // Reminder must be strictly before the task's scheduled time.
    if (!Validators.isReminderValid(
      taskDate: _selectedDate,
      taskHour: _selectedHour!,
      reminderDateTime: _reminderDateTime,
    )) {
      SnackbarUtils.showError(
        context,
        'El recordatorio no puede ser posterior a la hora de la tarea '
        '($_selectedHour)',
      );
      return;
    }

    final catalog = context.read<CatalogProvider>();
    final repo = context.read<TaskRepository>();
    final auth = context.read<AuthProvider>();
    final currentUserId = auth.appUser?.id;
    final isAdmin = auth.isSuperAdmin;
    final dateKey = AppDateUtils.formatDateKey(_selectedDate);
    // Sprint 7.4.9B Objetivo D: only the task's encargado or an admin may
    // change the reminder of an EXISTING task; the creator of a brand-new
    // task may always set its initial reminder. Mirrored in firestore.rules
    // (canEditReminder()) as the authoritative check.
    final canEditReminder =
        !_isEditing || isAdmin || _assignedUserId == currentUserId;

    setState(() => _isSaving = true);
    try {
      final ignoreStatusIds = <String>{
        if (catalog.completedStatusId != null) catalog.completedStatusId!,
        if (catalog.cancelledStatusId != null) catalog.cancelledStatusId!,
      }.toList();

      final hasConflict = await repo.hasConflict(
        assignedUserId: _assignedUserId!,
        date: dateKey,
        hour: _selectedHour!,
        excludeTaskId: widget.existingTask?.id,
        ignoreStatusIds: ignoreStatusIds,
      );

      if (hasConflict) {
        if (!mounted) return;
        await showInfoDialog(
          context,
          title: 'Horario duplicado',
          message:
              '${catalog.userName(_assignedUserId)} ya tiene otra tarea activa el '
              '${AppDateUtils.formatShortDate(_selectedDate)} a las $_selectedHour. '
              'Puedes continuar: ambas tareas quedarán programadas.',
        );
        if (!mounted) return;
      }

      final statusId = _statusId ?? catalog.pendingStatusId ?? '';

      if (_isEditing) {
        // Sprint 7.4.9B: a user without canEditReminder must not change
        // reminderTime/reminderSent at all, even incidentally — otherwise
        // firestore.rules' reminderUnchanged() check would reject the
        // whole update, blocking their edit of unrelated fields too.
        final reminderTimeToSave =
            canEditReminder ? _reminderDateTime : widget.existingTask!.reminderTime;
        final reminderSentToSave =
            canEditReminder ? false : widget.existingTask!.reminderSent;
        await repo.updateTask(widget.existingTask!.id, {
          'date': dateKey,
          'hour': _selectedHour,
          'assignedUserId': _assignedUserId,
          'taskTypeId': _taskTypeId,
          'statusId': statusId,
          'clientName': _clientNameController.text.trim(),
          'clientPhone': Validators.cleanPhone(_clientPhoneController.text),
          'observations': _observationsController.text.trim(),
          'reminderTime': reminderTimeToSave,
          'reminderSent': reminderSentToSave,
          'groupId': _groupId,
          'visibleToAllGroups': _visibleToAllGroups,
        }.map((key, value) {
          if (key == 'reminderTime') {
            return MapEntry(key,
                value == null ? null : Timestamp.fromDate(value as DateTime));
          }
          return MapEntry(key, value);
        }));
      } else {
        final newTask = TaskModel(
          id: '',
          hour: _selectedHour!,
          assignedUserId: _assignedUserId!,
          taskTypeId: _taskTypeId!,
          clientName: _clientNameController.text.trim(),
          clientPhone: Validators.cleanPhone(_clientPhoneController.text),
          statusId: statusId,
          observations: _observationsController.text.trim(),
          reminderTime: _reminderDateTime,
          date: dateKey,
          groupId: _groupId,
          visibleToAllGroups: _visibleToAllGroups,
          // Sprint 7.4.1: lets onTaskCreate exclude the creator from their
          // own "task created" push (self-assigned task, or own group).
          createdBy: currentUserId,
        );
        final taskId = await repo.createTask(newTask);
        // Sprint 7.4.3 Parte 2 — latency measurement only, no behavior
        // change. Measured on the device clock, so the delta against the
        // Cloud Functions `trigger_received` log (server clock) carries
        // whatever clock skew exists between this device and GCP — not a
        // pure network/processing latency.
        debugPrint(
          '[FCM_TIMING]\ntask_created_local\ntaskId=$taskId\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
        );
        debugPrint(
          '[CREATE_TASK]\nfirestore_saved\ntaskId=$taskId\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      if (mounted) {
        SnackbarUtils.showSuccess(
          context,
          _isEditing ? 'Tarea actualizada' : 'Tarea creada correctamente',
        );
        debugPrint(
          '[CREATE_TASK]\nsuccess_message_shown\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
        );
        Navigator.of(context).pop();
        debugPrint(
          '[CREATE_TASK]\nnavigation_completed\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.appUser!;
    final isAdmin = auth.isSuperAdmin;
    final colors = context.colors;

    // Sprint 7.4.6 Bug 2: only self-default "Encargado" for regular workers
    // (who usually create tasks for themselves) — defaulting an admin to
    // themselves silently saved tasks "assigned" to the admin instead of
    // the worker they actually meant to pick, which then (correctly, given
    // that wrong data) routed the "task_created_assigned" push to the
    // admin. Leaving it null for admins lets the existing
    // "Selecciona un encargado" validation in `_save()` do its job.
    if (!isAdmin) {
      _assignedUserId ??= currentUser.id;
    }
    // Sprint 7.4.9B Objetivo D/E: same rule as in _save() — only the
    // encargado or an admin may edit an EXISTING task's reminder; the
    // creator of a brand-new task may always set the initial one.
    final canEditReminder =
        !_isEditing || isAdmin || _assignedUserId == currentUser.id;
    if (_statusId == null && !_isEditing) {
      _statusId = catalog.pendingStatusId;
    }
    if (_selectedHour == null && catalog.availableHours.isNotEmpty) {
      _selectedHour = catalog.availableHours.first.hour;
    }
    // Default to the assigned worker's group (covers both brand-new tasks
    // and legacy tasks being edited for the first time after this
    // feature shipped, which have groupId == null).
    _groupId ??=
        catalog.userById(_assignedUserId)?.groupId ?? currentUser.groupId;

    // Sprint 5.4: only task types associated with the selected group are
    // offered (types with no groups assigned are universal, see
    // TaskTypeModel.appliesToGroup). The currently selected type is always
    // kept so it isn't silently dropped if it no longer matches.
    final availableTaskTypes = catalog.taskTypes
        .where((t) => t.appliesToGroup(_groupId) || t.id == _taskTypeId)
        .toList();
    if (_taskTypeId == null && availableTaskTypes.isNotEmpty) {
      _taskTypeId = availableTaskTypes.first.id;
    }

    final assignableUsers = _assignableUsers(catalog, currentUser);
    // Non-admins can only create/edit tasks for their own group, so the
    // selector is fully locked (Sprint 5.4); admins may pick any group
    // (e.g. to share a task across groups). The task's current _groupId is
    // always included in the options so editing a legacy/shared task
    // doesn't show an empty field while locked.
    final isGroupLocked = !isAdmin && currentUser.groupId != null;
    final groupOptions = isGroupLocked
        ? catalog.groups
            .where((g) => g.id == currentUser.groupId || g.id == _groupId)
            .toList()
        : catalog.groups;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar tarea' : 'Nueva tarea')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Fecha',
                  prefixIcon: Icon(LucideIcons.calendar, color: colors.primary),
                ),
                child: Text(AppDateUtils.formatShortDate(_selectedDate)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue:
                  catalog.availableHours.any((h) => h.hour == _selectedHour)
                      ? _selectedHour
                      : null,
              decoration: InputDecoration(
                labelText: 'Hora',
                prefixIcon: Icon(LucideIcons.clock, color: colors.primary),
              ),
              dropdownColor: colors.surface,
              items: catalog.availableHours
                  .map((h) =>
                      DropdownMenuItem(value: h.hour, child: Text(h.hour)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedHour = v),
              validator: (v) => v == null ? 'Selecciona una hora' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue:
                  assignableUsers.any((u) => u.id == _assignedUserId)
                      ? _assignedUserId
                      : null,
              decoration: InputDecoration(
                labelText: 'Encargado',
                prefixIcon:
                    Icon(LucideIcons.userCheck, color: colors.primary),
              ),
              dropdownColor: colors.surface,
              items: assignableUsers
                  .map((u) =>
                      DropdownMenuItem(value: u.id, child: Text(u.name)))
                  .toList(),
              onChanged: (v) => setState(() => _assignedUserId = v),
              validator: (v) => v == null ? 'Selecciona un encargado' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue:
                  groupOptions.any((g) => g.id == _groupId) ? _groupId : null,
              decoration: InputDecoration(
                labelText: 'Grupo',
                prefixIcon: Icon(LucideIcons.users, color: colors.primary),
                suffixIcon: isGroupLocked
                    ? Icon(LucideIcons.lock,
                        color: colors.textSecondary, size: 18)
                    : null,
              ),
              dropdownColor: colors.surface,
              items: groupOptions
                  .map((g) =>
                      DropdownMenuItem(value: g.id, child: Text(g.name)))
                  .toList(),
              onChanged: isGroupLocked
                  ? null
                  : (v) => setState(() {
                        _groupId = v;
                        _taskTypeId = null;
                      }),
              validator: (v) => v == null ? 'Selecciona un grupo' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: colors.primary,
              secondary: Icon(LucideIcons.globe, color: colors.primary),
              title: const Text('Visible para todos los grupos'),
              subtitle: Text(
                'Si está desactivado, solo el grupo seleccionado podrá ver esta tarea.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              value: _visibleToAllGroups,
              onChanged: (v) => setState(() => _visibleToAllGroups = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue:
                  availableTaskTypes.any((t) => t.id == _taskTypeId)
                      ? _taskTypeId
                      : null,
              decoration: InputDecoration(
                labelText: 'Tipo de tarea',
                prefixIcon: Icon(LucideIcons.tag, color: colors.primary),
              ),
              dropdownColor: colors.surface,
              items: availableTaskTypes
                  .map((t) =>
                      DropdownMenuItem(value: t.id, child: Text(t.name)))
                  .toList(),
              onChanged: (v) => setState(() => _taskTypeId = v),
              validator: (v) =>
                  v == null ? 'Selecciona un tipo de tarea' : null,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue:
                    catalog.statuses.any((s) => s.id == _statusId)
                        ? _statusId
                        : null,
                decoration: InputDecoration(
                  labelText: 'Estado',
                  prefixIcon:
                      Icon(LucideIcons.listChecks, color: colors.primary),
                ),
                dropdownColor: colors.surface,
                items: catalog.statuses
                    .map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() => _statusId = v),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _clientNameController,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Nombre del cliente',
                prefixIcon:
                    Icon(LucideIcons.userCircle, color: colors.primary),
              ),
              validator: (v) =>
                  Validators.required(v, fieldName: 'El nombre del cliente'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _clientPhoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Teléfono del cliente',
                prefixIcon: Icon(LucideIcons.phone, color: colors.primary),
                hintText: '300 225 7755 o +57 300 225 7755',
              ),
              validator: Validators.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _observationsController,
              maxLines: 3,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Observaciones',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Icon(LucideIcons.pencil, color: colors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: canEditReminder ? _showReminderSheet : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Recordatorio (opcional)',
                  prefixIcon: Icon(LucideIcons.bell, color: colors.primary),
                  suffixIcon: !canEditReminder
                      ? Icon(LucideIcons.lock,
                          color: colors.textSecondary, size: 18)
                      : (_reminderOption != _ReminderOption.none
                          ? IconButton(
                              icon: Icon(LucideIcons.xCircle,
                                  color: colors.textSecondary),
                              onPressed: () => setState(() {
                                _reminderDateTime = null;
                                _reminderOption = _ReminderOption.none;
                              }),
                            )
                          : null),
                ),
                child: Text(
                  _reminderLabel(),
                  style:
                      !canEditReminder ? TextStyle(color: colors.textSecondary) : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                canEditReminder
                    ? 'El recordatorio debe ser anterior a la hora de la tarea.'
                    : 'Solo el encargado o un administrador pueden modificar el recordatorio.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 28),
            GoldButton(
              label: _isEditing ? 'Guardar cambios' : 'Crear tarea',
              loading: _isSaving,
              onPressed: _save,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
