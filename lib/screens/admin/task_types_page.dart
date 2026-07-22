import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/task_type_colors.dart';
import '../../models/group_model.dart';
import '../../models/task_type_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/side_panel_shell.dart';

/// Preset swatches offered when picking a task type's color.
const _colorPresets = <String>[
  '#D4AF37', // gold
  '#4CAF50', // success green
  '#CF6679', // error red
  '#4A90D9', // blue
  '#9B59B6', // purple
  '#E67E22', // orange
  '#1ABC9C', // teal
];

/// Human-readable summary of which teams [type] is offered for.
String _groupsLabel(CatalogProvider catalog, TaskTypeModel type) {
  if (type.groupIds.isEmpty) return 'Todos';
  return type.groupIds.map((id) => catalog.groupById(id)?.name ?? '?').join(', ');
}

/// Admin: CRUD for `taskTypes` (name, order/"posición", optional color,
/// optional team restriction).
class TaskTypesPage extends StatefulWidget {
  const TaskTypesPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  State<TaskTypesPage> createState() => _TaskTypesPageState();
}

class _TaskTypesPageState extends State<TaskTypesPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _groupFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;
    final isMobile = context.isMobile;
    final query = _query.trim().toLowerCase();
    final groups = List.of(catalog.groups)..sort((a, b) => a.name.compareTo(b.name));

    final taskTypes = catalog.taskTypes.where((t) {
      if (query.isNotEmpty && !t.name.toLowerCase().contains(query)) return false;
      if (_groupFilter == AppFilterValues.noGroup) {
        if (t.groupIds.isNotEmpty) return false;
      } else if (_groupFilter != null && !t.appliesToGroup(_groupFilter)) {
        return false;
      }
      return true;
    }).toList();

    final searchField = TextField(
      controller: _searchController,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Buscar',
        hintText: 'Nombre del tipo',
        prefixIcon: Icon(LucideIcons.search, color: colors.primary, size: 18),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.xCircle, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
      ),
      onChanged: (v) => setState(() => _query = v),
    );

    final groupFilterField = DropdownButtonFormField<String?>(
      initialValue: _groupFilter,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Equipo',
        prefixIcon: Icon(LucideIcons.users, color: colors.primary, size: 18),
      ),
      dropdownColor: colors.surface,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
        const DropdownMenuItem<String?>(
          value: AppFilterValues.noGroup,
          child: Text('Sin equipo'),
        ),
        for (final g in groups) DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
      ],
      onChanged: (v) => setState(() => _groupFilter = v),
    );

    final filters = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 8),
                groupFilterField,
              ],
            )
          : Row(
              children: [
                Expanded(flex: 2, child: searchField),
                const SizedBox(width: 10),
                Expanded(child: groupFilterField),
              ],
            ),
    );

    Widget buildList({required bool shrink}) {
      if (taskTypes.isEmpty) {
        return EmptyState(
          message: query.isEmpty && _groupFilter == null
              ? 'No hay tipos de tarea creados todavía.'
              : 'Ningún tipo de tarea coincide con estos filtros.',
          icon: LucideIcons.tag,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shrinkWrap: shrink,
        physics: shrink ? const NeverScrollableScrollPhysics() : null,
        itemCount: taskTypes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final type = taskTypes[index];
          // Tablet/desktop: name/position/color/teams editable right on
          // the row. Mobile keeps the "Editar" dialog.
          return isMobile
              ? _TaskTypeCardMobile(type: type, catalog: catalog)
              : _TaskTypeRowEditable(type: type, groups: groups);
        },
      );
    }

    Widget body;
    if (isMobile) {
      body = Column(children: [filters, Expanded(child: buildList(shrink: false))]);
    } else {
      // Same width-aware rule as Equipos/Usuarios/Estados: below ~900px of
      // actual available width, stack the "Nuevo tipo de tarea" panel under
      // the list instead of squeezing both side by side.
      body = LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 900;
          final panel = _CreateTaskTypePanel(
            key: const ValueKey('create-task-type'),
            groups: groups,
          );

          if (sideBySide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: AppLayout.contentMaxWidthWide),
                      child: Column(
                        children: [filters, Expanded(child: buildList(shrink: false))],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 16),
                  child: SizedBox(width: 320, child: panel),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filters,
                buildList(shrink: true),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: panel,
                ),
              ],
            ),
          );
        },
      );
    }

    // Tablet/desktop: the panel replaces the FAB for creating a task type.
    final fab = isMobile
        ? FloatingActionButton(
            onPressed: () => _showTaskTypeFormDialog(context),
            child: const Icon(LucideIcons.plus),
          )
        : null;
    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Tipos de tarea')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

/// Mobile row — unchanged behavior (tap pencil/trash to open a dialog).
class _TaskTypeCardMobile extends StatelessWidget {
  const _TaskTypeCardMobile({required this.type, required this.catalog});

  final TaskTypeModel type;
  final CatalogProvider catalog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        leading: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: type.parsedColor ?? colors.primary,
          ),
        ),
        title: Text(type.name, style: TextStyle(color: colors.textPrimary)),
        subtitle: Text(
          'Posición: ${type.order} • Equipos: ${_groupsLabel(catalog, type)}',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(LucideIcons.pencil, color: colors.primary, size: 18),
              onPressed: () => _showTaskTypeFormDialog(context, existing: type),
            ),
            IconButton(
              icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
              onPressed: () => _deleteTaskType(context, type),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tablet/desktop row: Nombre and Posición are real fields that save on
/// blur; the color swatch opens a `flutter_colorpicker` wheel; the teams
/// summary opens a small chip picker (a compact exception, like Equipos'
/// Miembros checklist — a multi-select doesn't fit inline in a table row).
class _TaskTypeRowEditable extends StatefulWidget {
  const _TaskTypeRowEditable({required this.type, required this.groups});

  final TaskTypeModel type;
  final List<GroupModel> groups;

  @override
  State<_TaskTypeRowEditable> createState() => _TaskTypeRowEditableState();
}

class _TaskTypeRowEditableState extends State<_TaskTypeRowEditable> {
  late final _nameController = TextEditingController(text: widget.type.name);
  late final _orderController = TextEditingController(text: '${widget.type.order}');
  final _nameFocus = FocusNode();
  final _orderFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onNameFocusChange);
    _orderFocus.addListener(_onOrderFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TaskTypeRowEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_nameFocus.hasFocus && _nameController.text != widget.type.name) {
      _nameController.text = widget.type.name;
    }
    if (!_orderFocus.hasFocus && _orderController.text != '${widget.type.order}') {
      _orderController.text = '${widget.type.order}';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    _nameFocus.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  void _onNameFocusChange() {
    if (_nameFocus.hasFocus) return;
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      _nameController.text = widget.type.name; // required — revert
      return;
    }
    if (newName == widget.type.name) return;
    _save(name: newName);
  }

  void _onOrderFocusChange() {
    if (_orderFocus.hasFocus) return;
    final newOrder = int.tryParse(_orderController.text.trim());
    if (newOrder == null) {
      _orderController.text = '${widget.type.order}'; // invalid — revert
      return;
    }
    if (newOrder == widget.type.order) return;
    _save(order: newOrder);
  }

  Future<void> _save({String? name, int? order, String? color, List<String>? groupIds}) async {
    final repo = context.read<CatalogRepository>();
    try {
      await repo.updateTaskType(
        widget.type.id,
        name ?? widget.type.name,
        order ?? widget.type.order,
        color: color ?? widget.type.color,
        groupIds: groupIds ?? widget.type.groupIds,
      );
      if (mounted) SnackbarUtils.showSuccess(context, 'Tipo de tarea actualizado');
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Future<void> _pickColor() async {
    var tempColor = widget.type.parsedColor ?? context.colors.primary;
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Color del tipo de tarea'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: tempColor,
            onColorChanged: (c) => tempColor = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(tempColor),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (picked != null) _save(color: taskTypeColorToHex(picked));
  }

  Future<void> _pickGroups() async {
    final selected = <String>{...widget.type.groupIds};
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Equipos'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ninguno seleccionado = todos los equipos',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final group in widget.groups)
                      FilterChip(
                        label: Text(group.name),
                        selected: selected.contains(group.id),
                        onSelected: (v) => setState(() {
                          if (v) {
                            selected.add(group.id);
                          } else {
                            selected.remove(group.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) _save(groupIds: selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RowField(
            label: 'Color',
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _pickColor,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.type.parsedColor ?? colors.primary,
                    border: Border.all(color: colors.divider, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: _RowField(
              label: 'Nombre',
              child: TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(isDense: true),
                onSubmitted: (_) => _nameFocus.unfocus(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: _RowField(
              label: 'Equipos',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _pickGroups,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _groupsLabel(context.watch<CatalogProvider>(), widget.type),
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 84,
            child: _RowField(
              label: 'Posición',
              child: TextField(
                controller: _orderController,
                focusNode: _orderFocus,
                keyboardType: TextInputType.number,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(isDense: true),
                onSubmitted: (_) => _orderFocus.unfocus(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: IconButton(
              icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
              onPressed: () => _deleteTaskType(context, widget.type),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small column header, matching the Equipos row layout convention.
class _RowField extends StatelessWidget {
  const _RowField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Next "Posición" value offered by default in [_CreateTaskTypePanel] —
/// one past the highest position already in use (1 when there are none),
/// so admins don't have to look up the last position themselves.
int _nextTaskTypeOrder(CatalogProvider catalog) {
  if (catalog.taskTypes.isEmpty) return 1;
  return catalog.taskTypes.map((t) => t.order).reduce((a, b) => a > b ? a : b) + 1;
}

/// Tablet/desktop always-visible right panel for creating a task type —
/// stays in place (fields reset, Posición advances to the next number)
/// after a successful save.
class _CreateTaskTypePanel extends StatefulWidget {
  const _CreateTaskTypePanel({super.key, required this.groups});

  final List<GroupModel> groups;

  @override
  State<_CreateTaskTypePanel> createState() => _CreateTaskTypePanelState();
}

class _CreateTaskTypePanelState extends State<_CreateTaskTypePanel> {
  final _nameController = TextEditingController();
  late final _orderController =
      TextEditingController(text: '${_nextTaskTypeOrder(context.read<CatalogProvider>())}');
  final _formKey = GlobalKey<FormState>();
  String? _selectedColor;
  final _selectedGroupIds = <String>{};
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    var tempColor = (_selectedColor != null ? parseHexColor(_selectedColor!) : null) ??
        context.colors.primary;
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Color del tipo de tarea'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: tempColor,
            onColorChanged: (c) => tempColor = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(tempColor),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (picked != null) setState(() => _selectedColor = taskTypeColorToHex(picked));
  }

  Future<void> _pickGroups() async {
    final selected = <String>{..._selectedGroupIds};
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Equipos'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ninguno seleccionado = todos los equipos',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final group in widget.groups)
                      FilterChip(
                        label: Text(group.name),
                        selected: selected.contains(group.id),
                        onSelected: (v) => setState(() {
                          if (v) {
                            selected.add(group.id);
                          } else {
                            selected.remove(group.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      setState(() {
        _selectedGroupIds
          ..clear()
          ..addAll(selected);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final repo = context.read<CatalogRepository>();
    final order = int.parse(_orderController.text.trim());
    try {
      await repo.addTaskType(
        _nameController.text.trim(),
        order,
        color: _selectedColor,
        groupIds: _selectedGroupIds.toList(),
      );
      if (mounted) {
        _nameController.clear();
        _orderController.text = '${order + 1}';
        setState(() {
          _selectedColor = null;
          _selectedGroupIds.clear();
        });
        SnackbarUtils.showSuccess(context, 'Tipo de tarea creado');
      }
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    return SidePanelShell(
      title: 'Nuevo tipo de tarea',
      icon: LucideIcons.plus,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _orderController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Posición'),
              validator: (v) => int.tryParse(v ?? '') == null ? 'Ingresa un número' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Color', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _pickColor,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _selectedColor != null
                          ? parseHexColor(_selectedColor!)
                          : colors.primary,
                      border: Border.all(color: colors.divider, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _pickGroups,
              child: _RowField(
                label: 'Equipos',
                child: Text(
                  _selectedGroupIds.isEmpty
                      ? 'Todos'
                      : _selectedGroupIds
                          .map((id) => catalog.groupById(id)?.name ?? '?')
                          .join(', '),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showTaskTypeFormDialog(BuildContext context, {TaskTypeModel? existing}) async {
  final colors = context.colors;
  final repo = context.read<CatalogRepository>();
  final catalog = context.read<CatalogProvider>();
  final nameController = TextEditingController(text: existing?.name ?? '');
  final orderController = TextEditingController(
    text: '${existing?.order ?? (catalog.taskTypes.length)}',
  );
  final formKey = GlobalKey<FormState>();
  String? selectedColor = existing?.color;
  final selectedGroupIds = <String>{...?existing?.groupIds};
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text(existing == null ? 'Nuevo tipo de tarea' : 'Editar tipo de tarea'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: orderController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Posición'),
                      validator: (v) =>
                          int.tryParse(v ?? '') == null ? 'Ingresa un número' : null,
                    ),
                    const SizedBox(height: 16),
                    Text('Color', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final hex in _colorPresets)
                          GestureDetector(
                            onTap: () => setState(() => selectedColor = hex),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: parseHexColor(hex),
                                border: Border.all(
                                  color: selectedColor == hex
                                      ? colors.textPrimary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: selectedColor == hex
                                  ? const Icon(LucideIcons.check, size: 16, color: Colors.black)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Equipos (ninguno seleccionado = todos)',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final group in catalog.groups)
                          FilterChip(
                            label: Text(group.name),
                            selected: selectedGroupIds.contains(group.id),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                selectedGroupIds.add(group.id);
                              } else {
                                selectedGroupIds.remove(group.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() => isSaving = true);
                        final order = int.parse(orderController.text);
                        try {
                          if (existing == null) {
                            await repo.addTaskType(
                              nameController.text.trim(),
                              order,
                              color: selectedColor,
                              groupIds: selectedGroupIds.toList(),
                            );
                          } else {
                            await repo.updateTaskType(
                              existing.id,
                              nameController.text.trim(),
                              order,
                              color: selectedColor,
                              groupIds: selectedGroupIds.toList(),
                            );
                          }
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                        } catch (e) {
                          if (dialogContext.mounted) {
                            SnackbarUtils.showError(
                                dialogContext, SnackbarUtils.firebaseErrorMessage(e));
                          }
                          setState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _deleteTaskType(BuildContext context, TaskTypeModel type) async {
  final confirm = await showConfirmDialog(
    context,
    title: 'Eliminar tipo de tarea',
    message: '¿Eliminar el tipo de tarea "${type.name}"?',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
  if (!confirm) return;
  if (!context.mounted) return;

  final repo = context.read<CatalogRepository>();
  try {
    await repo.deleteTaskType(type.id);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Tipo de tarea eliminado');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}
