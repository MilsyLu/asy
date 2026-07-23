import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/app_user.dart';
import '../../models/group_model.dart';
import '../../models/task_model.dart';
import '../../models/task_type_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/system_config_provider.dart';
import '../../services/task_repository.dart';
import '../../services/task_scheduling_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_section_card.dart';
import '../../widgets/gold_button.dart';
import 'widgets/hour_grid_selector.dart';
import 'widgets/reminder_picker.dart';

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
  ReminderOption _reminderOption = ReminderOption.none;
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
      _reminderOption = detectReminderOption(
        _reminderDateTime,
        taskDateTimeFromHour(_selectedDate, _selectedHour),
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
  // Reminder helpers — the sheet/custom-picker UI itself lives in
  // widgets/reminder_picker.dart, shared with the inline TaskCreatePanel.
  // ---------------------------------------------------------------------------

  DateTime? _taskDateTime() => taskDateTimeFromHour(_selectedDate, _selectedHour);

  String _reminderLabel() => formatReminderLabel(
        option: _reminderOption,
        reminderDateTime: _reminderDateTime,
        taskDateTime: _taskDateTime(),
      );

  Future<void> _pickReminder() async {
    final result = await pickReminder(
      context,
      current: _reminderOption,
      currentReminderDateTime: _reminderDateTime,
      taskDateTime: _taskDateTime(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _reminderOption = result.option;
      _reminderDateTime = result.dateTime;
    });
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
      SnackbarUtils.showError(context, 'Selecciona un equipo');
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
    final sysConfig = context.watch<SystemConfigProvider>();
    final currentUser = auth.appUser!;
    final isAdmin = auth.isSuperAdmin;
    final colors = context.colors;
    final useFreePicker = TaskSchedulingService.useFreePicker(sysConfig);

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
    if (_selectedHour == null && !useFreePicker && catalog.availableHours.isNotEmpty) {
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

    final title = _isEditing ? 'Editar tarea' : 'Nueva tarea';

    // Tablet/desktop gets a restructured two-zone layout (see
    // _buildDesktopScaffold); mobile keeps the exact original single-column
    // Form below, untouched, per the redesign brief.
    if (!context.isMobile) {
      return _buildDesktopScaffold(
        context,
        title: title,
        colors: colors,
        catalog: catalog,
        useFreePicker: useFreePicker,
        assignableUsers: assignableUsers,
        groupOptions: groupOptions,
        isGroupLocked: isGroupLocked,
        availableTaskTypes: availableTaskTypes,
        isAdmin: isAdmin,
        canEditReminder: canEditReminder,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
            if (useFreePicker)
              InkWell(
                onTap: () async {
                  final initial = _selectedHour != null
                      ? TaskSchedulingService.parseHourString(_selectedHour!)
                      : TimeOfDay.now();
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: initial,
                  );
                  if (!mounted || picked == null) return;
                  setState(() {
                    _selectedHour = TaskSchedulingService.formatTimeOfDay(picked);
                  });
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Hora',
                    prefixIcon: Icon(LucideIcons.clock, color: colors.primary),
                  ),
                  child: Text(
                    _selectedHour ?? 'Seleccionar hora',
                    style: _selectedHour == null
                        ? TextStyle(color: colors.textSecondary)
                        : null,
                  ),
                ),
              )
            else
              HourGridSelector(
                hours: TaskSchedulingService.catalogHours(catalog),
                selectedDate: _selectedDate,
                selectedHour: _selectedHour,
                onHourSelected: (h) => setState(() => _selectedHour = h),
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
                labelText: 'Equipo',
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
              validator: (v) => v == null ? 'Selecciona un equipo' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: colors.primary,
              secondary: Icon(LucideIcons.globe, color: colors.primary),
              title: const Text('Visible para todos los equipos'),
              subtitle: Text(
                'Si está desactivado, solo el equipo seleccionado podrá ver esta tarea.',
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
              onTap: canEditReminder ? _pickReminder : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Recordatorio (opcional)',
                  prefixIcon: Icon(LucideIcons.bell, color: colors.primary),
                  suffixIcon: !canEditReminder
                      ? Icon(LucideIcons.lock,
                          color: colors.textSecondary, size: 18)
                      : (_reminderOption != ReminderOption.none
                          ? IconButton(
                              icon: Icon(LucideIcons.xCircle,
                                  color: colors.textSecondary),
                              onPressed: () => setState(() {
                                _reminderDateTime = null;
                                _reminderOption = ReminderOption.none;
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

  // ---------------------------------------------------------------------------
  // Tablet/desktop layout (redesign — see project conversation history for
  // the agreed brief). Reuses every field widget, validator, controller and
  // handler from the mobile form above unchanged — only the arrangement
  // differs: two zones ("Programación" + "Cliente y notas") instead of one
  // long column, and the primary action moves into the AppBar so it's
  // always reachable without scrolling. Mobile is untouched (see build()).
  // ---------------------------------------------------------------------------

  Widget _buildDesktopScaffold(
    BuildContext context, {
    required String title,
    required AppColorsExtension colors,
    required CatalogProvider catalog,
    required bool useFreePicker,
    required List<AppUser> assignableUsers,
    required List<GroupModel> groupOptions,
    required bool isGroupLocked,
    required List<TaskTypeModel> availableTaskTypes,
    required bool isAdmin,
    required bool canEditReminder,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: IntrinsicWidth(
              child: GoldButton(
                label: _isEditing ? 'Guardar cambios' : 'Crear tarea',
                loading: _isSaving,
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidthWide),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scheduleSection = _buildScheduleSection(
                    colors: colors,
                    catalog: catalog,
                    useFreePicker: useFreePicker,
                    assignableUsers: assignableUsers,
                    groupOptions: groupOptions,
                    isGroupLocked: isGroupLocked,
                    availableTaskTypes: availableTaskTypes,
                    isAdmin: isAdmin,
                    canEditReminder: canEditReminder,
                  );
                  final clientSection = _buildClientSection(colors: colors);

                  if (constraints.maxWidth >= 760) {
                    return SingleChildScrollView(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: scheduleSection),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(flex: 2, child: clientSection),
                        ],
                      ),
                    );
                  }

                  // Stacked (narrow) layout: Cliente y notas first, then
                  // Programación — matches the order Michel asked for in the
                  // centered edit dialog (which always lands here, being
                  // narrower than the 760px threshold above).
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        clientSection,
                        const SizedBox(height: AppSpacing.lg),
                        scheduleSection,
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Programación": Fecha+Hora, Encargado+Equipo, Tipo de tarea(+Estado) and
  /// the "visible para todos los equipos" toggle — the highest-frequency
  /// decisions, grouped by proximity instead of one field per row.
  Widget _buildScheduleSection({
    required AppColorsExtension colors,
    required CatalogProvider catalog,
    required bool useFreePicker,
    required List<AppUser> assignableUsers,
    required List<GroupModel> groupOptions,
    required bool isGroupLocked,
    required List<TaskTypeModel> availableTaskTypes,
    required bool isAdmin,
    required bool canEditReminder,
  }) {
    final dateField = InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Fecha',
          prefixIcon: Icon(LucideIcons.calendar, color: colors.primary),
        ),
        child: Text(AppDateUtils.formatShortDate(_selectedDate)),
      ),
    );

    final hourField = useFreePicker
        ? InkWell(
            onTap: () async {
              final initial = _selectedHour != null
                  ? TaskSchedulingService.parseHourString(_selectedHour!)
                  : TimeOfDay.now();
              final picked = await showTimePicker(
                context: context,
                initialTime: initial,
              );
              if (!mounted || picked == null) return;
              setState(() {
                _selectedHour = TaskSchedulingService.formatTimeOfDay(picked);
              });
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Hora',
                prefixIcon: Icon(LucideIcons.clock, color: colors.primary),
              ),
              child: Text(
                _selectedHour ?? 'Seleccionar hora',
                style: _selectedHour == null
                    ? TextStyle(color: colors.textSecondary)
                    : null,
              ),
            ),
          )
        : HourGridSelector(
            hours: TaskSchedulingService.catalogHours(catalog),
            selectedDate: _selectedDate,
            selectedHour: _selectedHour,
            onHourSelected: (h) => setState(() => _selectedHour = h),
          );

    final assignedField = DropdownButtonFormField<String>(
      initialValue: assignableUsers.any((u) => u.id == _assignedUserId)
          ? _assignedUserId
          : null,
      decoration: InputDecoration(
        labelText: 'Encargado',
        prefixIcon: Icon(LucideIcons.userCheck, color: colors.primary),
      ),
      dropdownColor: colors.surface,
      items: assignableUsers
          .map((u) => DropdownMenuItem(value: u.id, child: Text(u.name)))
          .toList(),
      onChanged: (v) => setState(() => _assignedUserId = v),
      validator: (v) => v == null ? 'Selecciona un encargado' : null,
    );

    final groupField = DropdownButtonFormField<String>(
      initialValue: groupOptions.any((g) => g.id == _groupId) ? _groupId : null,
      decoration: InputDecoration(
        labelText: 'Equipo',
        prefixIcon: Icon(LucideIcons.users, color: colors.primary),
        suffixIcon: isGroupLocked
            ? Icon(LucideIcons.lock, color: colors.textSecondary, size: 18)
            : null,
      ),
      dropdownColor: colors.surface,
      items: groupOptions
          .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
          .toList(),
      onChanged: isGroupLocked
          ? null
          : (v) => setState(() {
                _groupId = v;
                _taskTypeId = null;
              }),
      validator: (v) => v == null ? 'Selecciona un equipo' : null,
    );

    final taskTypeField = DropdownButtonFormField<String>(
      initialValue: availableTaskTypes.any((t) => t.id == _taskTypeId)
          ? _taskTypeId
          : null,
      decoration: InputDecoration(
        labelText: 'Tipo de tarea',
        prefixIcon: Icon(LucideIcons.tag, color: colors.primary),
      ),
      dropdownColor: colors.surface,
      items: availableTaskTypes
          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
          .toList(),
      onChanged: (v) => setState(() => _taskTypeId = v),
      validator: (v) => v == null ? 'Selecciona un tipo de tarea' : null,
    );

    final statusField = isAdmin
        ? DropdownButtonFormField<String>(
            initialValue:
                catalog.statuses.any((s) => s.id == _statusId) ? _statusId : null,
            decoration: InputDecoration(
              labelText: 'Estado',
              prefixIcon: Icon(LucideIcons.listChecks, color: colors.primary),
            ),
            dropdownColor: colors.surface,
            items: catalog.statuses
                .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                .toList(),
            onChanged: (v) => setState(() => _statusId = v),
          )
        : null;

    return FormSectionCard(
      icon: LucideIcons.calendarClock,
      title: 'Programación',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 220, child: dateField),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: hourField),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: canEditReminder ? _pickReminder : null,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.bell, color: colors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Recordatorio',
                          style: TextStyle(color: colors.textSecondary, fontSize: 11),
                        ),
                        Text(
                          _reminderLabel(),
                          style: TextStyle(
                            color: !canEditReminder
                                ? colors.textSecondary
                                : colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!canEditReminder)
                    Icon(LucideIcons.lock, color: colors.textSecondary, size: 18)
                  else if (_reminderOption != ReminderOption.none)
                    IconButton(
                      icon: Icon(LucideIcons.xCircle, color: colors.textSecondary),
                      onPressed: () => setState(() {
                        _reminderDateTime = null;
                        _reminderOption = ReminderOption.none;
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            canEditReminder
                ? 'El recordatorio debe ser anterior a la hora de la tarea.'
                : 'Solo el encargado o un administrador pueden modificar el recordatorio.',
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: assignedField),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: groupField),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          statusField != null
              ? Row(
                  children: [
                    Expanded(child: taskTypeField),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: statusField),
                  ],
                )
              : taskTypeField,
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(LucideIcons.globe, color: colors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Visible para todos los equipos',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Si está desactivado, solo el equipo seleccionado podrá ver esta tarea.',
                      style: TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                activeThumbColor: colors.primary,
                value: _visibleToAllGroups,
                onChanged: (v) => setState(() => _visibleToAllGroups = v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
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
        ],
      ),
    );
  }

  /// "Cliente y notas": solo los datos de contacto del cliente — visualmente
  /// más corta que Programación, que concentra el resto de los campos.
  Widget _buildClientSection({required AppColorsExtension colors}) {
    return FormSectionCard(
      icon: LucideIcons.userCircle,
      title: 'Cliente',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _clientNameController,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Nombre del cliente',
              prefixIcon: Icon(LucideIcons.userCircle, color: colors.primary),
            ),
            validator: (v) =>
                Validators.required(v, fieldName: 'El nombre del cliente'),
          ),
          const SizedBox(height: AppSpacing.md),
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
        ],
      ),
    );
  }
}

/// Opens the edit flow for [task]. On tablet/desktop this is a centered
/// floating window instead of taking over the whole screen — the same
/// [AddEditTaskPage] content, just presented as a [Dialog] (closing it via
/// the AppBar's back arrow, the "Guardar cambios" button, or tapping
/// outside all just pop the dialog's route, exactly like before). Mobile is
/// unchanged: still a full-page push.
///
/// The window is deliberately narrower than [AddEditTaskPage]'s ≥760px
/// side-by-side threshold, so "Cliente y notas" and "Programación" stack
/// vertically here (Cliente y notas on top) instead of sitting side by side —
/// the same responsive rule already used inside the page, just landing on
/// its stacked branch because this window is smaller.
Future<void> openEditTaskFlow(BuildContext context, TaskModel task) {
  if (context.isMobile) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddEditTaskPage(existingTask: task)),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 880),
        child: AddEditTaskPage(existingTask: task),
      ),
    ),
  );
}

