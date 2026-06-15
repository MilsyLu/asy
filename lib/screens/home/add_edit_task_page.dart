import 'package:cloud_firestore/cloud_firestore.dart';
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

  List<AppUser> _assignableUsers(CatalogProvider catalog, AppUser current) {
    if (current.groupId != null) {
      final inGroup = catalog.usersInGroup(current.groupId);
      return inGroup.isNotEmpty ? inGroup : catalog.users;
    }
    return catalog.users;
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

  Future<void> _pickReminder() async {
    final initialDate = _reminderDateTime ?? _selectedDate;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (pickedDate == null || !mounted) return;

    final initialTime = _reminderDateTime != null
        ? TimeOfDay.fromDateTime(_reminderDateTime!)
        : TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return;

    setState(() {
      _reminderDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
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
        await repo.updateTask(widget.existingTask!.id, {
          'date': dateKey,
          'hour': _selectedHour,
          'assignedUserId': _assignedUserId,
          'taskTypeId': _taskTypeId,
          'statusId': statusId,
          'clientName': _clientNameController.text.trim(),
          'clientPhone': Validators.cleanPhone(_clientPhoneController.text),
          'observations': _observationsController.text.trim(),
          'reminderTime': _reminderDateTime,
          'reminderSent': false,
          'groupId': _groupId,
          'visibleToAllGroups': _visibleToAllGroups,
        }.map((key, value) {
          if (key == 'reminderTime') {
            return MapEntry(key, value == null
                ? null
                : Timestamp.fromDate(value as DateTime));
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
        );
        await repo.createTask(newTask);
      }

      if (mounted) {
        SnackbarUtils.showSuccess(
          context,
          _isEditing ? 'Tarea actualizada' : 'Tarea creada correctamente',
        );
        Navigator.of(context).pop();
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

    _assignedUserId ??= currentUser.id;
    if (_taskTypeId == null && catalog.taskTypes.isNotEmpty) {
      _taskTypeId = catalog.taskTypes.first.id;
    }
    if (_statusId == null && !_isEditing) {
      _statusId = catalog.pendingStatusId;
    }
    if (_selectedHour == null && catalog.availableHours.isNotEmpty) {
      _selectedHour = catalog.availableHours.first.hour;
    }
    // Default to the assigned worker's group (covers both brand-new tasks
    // and legacy tasks being edited for the first time after this
    // feature shipped, which have groupId == null).
    _groupId ??= catalog.userById(_assignedUserId)?.groupId ?? currentUser.groupId;

    final assignableUsers = _assignableUsers(catalog, currentUser);
    // Non-admins can only assign tasks to their own group; admins may
    // pick any group (e.g. to share a task across groups).
    final groupOptions = (!isAdmin && currentUser.groupId != null)
        ? catalog.groups.where((g) => g.id == currentUser.groupId).toList()
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
              initialValue: catalog.availableHours.any((h) => h.hour == _selectedHour)
                  ? _selectedHour
                  : null,
              decoration: InputDecoration(
                labelText: 'Hora',
                prefixIcon: Icon(LucideIcons.clock, color: colors.primary),
              ),
              dropdownColor: colors.surface,
              items: catalog.availableHours
                  .map((h) => DropdownMenuItem(value: h.hour, child: Text(h.hour)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedHour = v),
              validator: (v) => v == null ? 'Selecciona una hora' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
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
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: groupOptions.any((g) => g.id == _groupId) ? _groupId : null,
              decoration: InputDecoration(
                labelText: 'Grupo',
                prefixIcon: Icon(LucideIcons.users, color: colors.primary),
              ),
              dropdownColor: colors.surface,
              items: groupOptions
                  .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                  .toList(),
              onChanged: (v) => setState(() => _groupId = v),
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
              initialValue: catalog.taskTypes.any((t) => t.id == _taskTypeId)
                  ? _taskTypeId
                  : null,
              decoration: InputDecoration(
                labelText: 'Tipo de tarea',
                prefixIcon: Icon(LucideIcons.tag, color: colors.primary),
              ),
              dropdownColor: colors.surface,
              items: catalog.taskTypes
                  .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                  .toList(),
              onChanged: (v) => setState(() => _taskTypeId = v),
              validator: (v) => v == null ? 'Selecciona un tipo de tarea' : null,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: catalog.statuses.any((s) => s.id == _statusId)
                    ? _statusId
                    : null,
                decoration: InputDecoration(
                  labelText: 'Estado',
                  prefixIcon: Icon(LucideIcons.listChecks, color: colors.primary),
                ),
                dropdownColor: colors.surface,
                items: catalog.statuses
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
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
                prefixIcon: Icon(LucideIcons.userCircle, color: colors.primary),
              ),
              validator: (v) => Validators.required(v, fieldName: 'El nombre del cliente'),
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
              onTap: _pickReminder,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Recordatorio (opcional)',
                  prefixIcon: Icon(LucideIcons.barChart3, color: colors.primary),
                  suffixIcon: _reminderDateTime != null
                      ? IconButton(
                          icon: Icon(LucideIcons.xCircle, color: colors.textSecondary),
                          onPressed: () => setState(() => _reminderDateTime = null),
                        )
                      : null,
                ),
                child: Text(
                  _reminderDateTime != null
                      ? AppDateUtils.formatDateTimeOrDash(_reminderDateTime)
                      : 'Sin recordatorio',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'El recordatorio debe ser anterior a la hora de la tarea.',
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
