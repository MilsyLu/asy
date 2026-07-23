import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../models/app_user.dart';
import '../../../models/group_model.dart';
import '../../../models/task_model.dart';
import '../../../models/task_type_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/system_config_provider.dart';
import '../../../services/task_repository.dart';
import '../../../services/task_scheduling_service.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/form_section_card.dart';
import 'hour_grid_selector.dart';
import 'reminder_picker.dart';

/// Inline "crear tarea" form embedded directly on Home (tablet/desktop) —
/// same fields, validators and save logic as [AddEditTaskPage]'s create
/// mode, but always visible instead of behind a separate full-page route.
/// Stays in place after a successful save (fields reset to defaults) so a
/// worker can log several tasks in a row without leaving the agenda.
///
/// Editing an existing task still goes through [AddEditTaskPage] as before
/// (pencil icon on an agenda row, task detail dialog, etc.) — this panel
/// only replaces the "+" FAB flow for *creating* a task from Home.
class TaskCreatePanel extends StatefulWidget {
  const TaskCreatePanel({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<TaskCreatePanel> createState() => _TaskCreatePanelState();
}

class _TaskCreatePanelState extends State<TaskCreatePanel> {
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

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientPhoneController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Reminder helpers — the sheet/custom-picker UI lives in reminder_picker.dart.
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

  /// Active users eligible for "Encargado" — same rule as AddEditTaskPage.
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

  /// Resets every field to its default — used both by the explicit
  /// "Limpiar" button and automatically after a successful save.
  void _clearForm() {
    _clientNameController.clear();
    _clientPhoneController.clear();
    _observationsController.clear();
    _formKey.currentState?.reset();
    setState(() {
      _selectedDate = widget.initialDate ?? DateTime.now();
      _selectedHour = null;
      _assignedUserId = null;
      _taskTypeId = null;
      _statusId = null;
      _groupId = null;
      _visibleToAllGroups = false;
      _reminderDateTime = null;
      _reminderOption = ReminderOption.none;
    });
  }

  Future<void> _save() async {
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
    final dateKey = AppDateUtils.formatDateKey(_selectedDate);

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
        excludeTaskId: null,
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
        createdBy: currentUserId,
      );
      await repo.createTask(newTask);

      if (mounted) {
        SnackbarUtils.showSuccess(context, 'Tarea creada correctamente');
        _clearForm();
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

    if (!isAdmin) {
      _assignedUserId ??= currentUser.id;
    }
    _statusId ??= catalog.pendingStatusId;
    if (_selectedHour == null && !useFreePicker && catalog.availableHours.isNotEmpty) {
      _selectedHour = catalog.availableHours.first.hour;
    }
    _groupId ??= catalog.userById(_assignedUserId)?.groupId ?? currentUser.groupId;

    final availableTaskTypes = catalog.taskTypes
        .where((t) => t.appliesToGroup(_groupId) || t.id == _taskTypeId)
        .toList();
    if (_taskTypeId == null && availableTaskTypes.isNotEmpty) {
      _taskTypeId = availableTaskTypes.first.id;
    }

    final assignableUsers = _assignableUsers(catalog, currentUser);
    final isGroupLocked = !isAdmin && currentUser.groupId != null;
    final groupOptions = isGroupLocked
        ? catalog.groups
            .where((g) => g.id == currentUser.groupId || g.id == _groupId)
            .toList()
        : catalog.groups;

    return Form(
      key: _formKey,
      child: _buildFormCard(
        colors: colors,
        catalog: catalog,
        useFreePicker: useFreePicker,
        assignableUsers: assignableUsers,
        groupOptions: groupOptions,
        isGroupLocked: isGroupLocked,
        availableTaskTypes: availableTaskTypes,
        isAdmin: isAdmin,
      ),
    );
  }

  /// Small caption-style sub-header used to separate "Cliente" from
  /// "Programación" *within* the single merged card below — a full
  /// [FormSectionCard] per group would cost an extra border+padding+gap
  /// just to save space Home doesn't have to spare.
  Widget _sectionLabel(AppColorsExtension colors, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: colors.textSecondary),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  /// One merged card — "Cliente" then "Programación" — instead of two
  /// separate [FormSectionCard]s, to save the vertical space a second
  /// border+padding+gap would otherwise cost in Home's fixed-width right
  /// column.
  Widget _buildFormCard({
    required AppColorsExtension colors,
    required CatalogProvider catalog,
    required bool useFreePicker,
    required List<AppUser> assignableUsers,
    required List<GroupModel> groupOptions,
    required bool isGroupLocked,
    required List<TaskTypeModel> availableTaskTypes,
    required bool isAdmin,
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
              final picked = await showTimePicker(context: context, initialTime: initial);
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
                style: _selectedHour == null ? TextStyle(color: colors.textSecondary) : null,
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
      icon: LucideIcons.calendarPlus,
      title: 'Nueva tarea',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _isSaving ? null : _clearForm,
            child: const Text('Limpiar', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: _isSaving
                ? SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.background,
                    ),
                  )
                : const Text('Crear tarea', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(colors, LucideIcons.userCircle, 'CLIENTE'),
          const SizedBox(height: AppSpacing.sm),
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
          const SizedBox(height: AppSpacing.md),
          Divider(color: colors.divider, height: 1),
          const SizedBox(height: AppSpacing.md),
          _sectionLabel(colors, LucideIcons.calendarClock, 'PROGRAMACIÓN'),
          const SizedBox(height: AppSpacing.sm),
          // Fecha stacked above Hora (not side by side) — this card's
          // ~330px content width is comfortable for a single field, but
          // splitting it with Fecha would leave HourGridSelector too
          // narrow for more than one cramped column of hour cards.
          dateField,
          const SizedBox(height: AppSpacing.md),
          hourField,
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: _pickReminder,
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
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_reminderOption != ReminderOption.none)
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
            'El recordatorio debe ser anterior a la hora de la tarea.',
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: assignedField),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: groupField),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          statusField != null
              ? Row(
                  children: [
                    Expanded(child: taskTypeField),
                    const SizedBox(width: AppSpacing.sm),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Si está desactivado, solo el equipo seleccionado podrá ver esta tarea.',
                      style: TextStyle(color: colors.textSecondary, fontSize: 10),
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
}
