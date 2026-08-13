import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/group_model.dart';
import '../../models/status_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/side_panel_shell.dart';

/// Admin: CRUD for `statuses` (name, order, groupIds).
class StatusesPage extends StatefulWidget {
  const StatusesPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  State<StatusesPage> createState() => _StatusesPageState();
}

class _StatusesPageState extends State<StatusesPage> {
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final isSuperAdmin = auth.isSuperAdmin;
    final canEditCatalogs = auth.hasPermission(AppPermissions.manageCatalogs);
    // A scoped admin_equipo sees universal statuses (apply everywhere) plus
    // any scoped to one of their own teams — never one scoped only to a
    // team they don't manage.
    final statuses = isSuperAdmin
        ? catalog.statuses
        : catalog.statuses
            .where((s) => s.groupIds.isEmpty || s.groupIds.any(auth.managesGroup))
            .toList();
    final colors = context.colors;
    final isMobile = context.isMobile;

    final infoBanner = Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, color: colors.primary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Las funciones automáticas usan los nombres exactos '
              '"Pendiente", "Completada" y "Reprogramada". Evita '
              'renombrarlos o eliminarlos.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    Widget buildList({required bool shrink}) {
      if (statuses.isEmpty) {
        return const EmptyState(
          message: 'No hay estados creados todavía.',
          icon: LucideIcons.listChecks,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        shrinkWrap: shrink,
        physics: shrink ? const NeverScrollableScrollPhysics() : null,
        itemCount: statuses.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final status = statuses[index];
          // A scoped admin without manageCatalogs, or looking at a
          // universal (unscoped) entry, gets a read-only row either way.
          final canEditThis = isSuperAdmin ||
              (canEditCatalogs && status.groupIds.isNotEmpty && status.groupIds.every(auth.managesGroup));
          // Tablet/desktop: name/order editable right on the row.
          // Mobile keeps the "Editar" dialog and the FAB.
          return isMobile
              ? _StatusCardMobile(status: status, canEdit: canEditThis, groups: catalog.groups)
              : _StatusRowEditable(status: status, canEdit: canEditThis, groups: catalog.groups);
        },
      );
    }

    Widget body;
    if (isMobile) {
      body = Column(children: [infoBanner, Expanded(child: buildList(shrink: false))]);
    } else if (!isSuperAdmin && !canEditCatalogs) {
      // No create panel to show if this admin can't create anything.
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidthWide),
          child: Column(
            children: [infoBanner, Expanded(child: buildList(shrink: false))],
          ),
        ),
      );
    } else {
      // Same width-aware rule as Equipos/Usuarios: below ~900px of actual
      // available width, stack the "Nuevo estado" panel under the list
      // instead of squeezing both side by side.
      body = LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 900;
          final panel = _CreateStatusPanel(
            key: const ValueKey('create-status'),
            groups: catalog.groups,
            managedGroupIds: isSuperAdmin ? null : (auth.appUser?.managedGroupIds ?? const []),
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
                        children: [infoBanner, Expanded(child: buildList(shrink: false))],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 16),
                  // Scrollable: avoids the confirm button being cut off
                  // below the fold when the panel is taller than the
                  // available height (see same fix in users_page.dart).
                  child: SizedBox(width: 320, child: SingleChildScrollView(child: panel)),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoBanner,
                const SizedBox(height: 12),
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

    // Tablet/desktop: the panel replaces the FAB for creating a status.
    final fab = isMobile && (isSuperAdmin || canEditCatalogs)
        ? FloatingActionButton(
            onPressed: () => _showStatusFormDialog(
              context,
              groups: catalog.groups,
              managedGroupIds: isSuperAdmin ? null : (auth.appUser?.managedGroupIds ?? const []),
            ),
            child: const Icon(LucideIcons.plus),
          )
        : null;
    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Estados')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

/// Read-only chip summary of a catalog entry's team scope — empty means
/// universal (applies to every team).
class _GroupScopeSummary extends StatelessWidget {
  const _GroupScopeSummary({required this.groupIds, required this.groups});

  final List<String> groupIds;
  final List<GroupModel> groups;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (groupIds.isEmpty) {
      return Text('Todos los equipos', style: TextStyle(color: colors.textSecondary, fontSize: 11));
    }
    final namesById = {for (final g in groups) g.id: g.name};
    final names = groupIds.map((id) => namesById[id]).whereType<String>().join(', ');
    return Text(names, style: TextStyle(color: colors.textSecondary, fontSize: 11));
  }
}

/// Multi-select dialog for a catalog entry's team scope. Unlike the
/// admin_equipo "Equipos asignados" picker, empty here is valid and means
/// "universal" — but a scoped admin (canOnly != null) may never leave it
/// empty or pick a team outside their own reach, since firestore.rules
/// requires their entries to always be explicitly scoped to teams they
/// manage.
Future<Set<String>?> _pickCatalogGroups(
  BuildContext context, {
  required Set<String> current,
  required List<GroupModel> groups,
  List<String>? managedGroupIds,
}) {
  final selectable =
      managedGroupIds == null ? groups : groups.where((g) => managedGroupIds.contains(g.id)).toList();
  final selected = {...current}..removeWhere((id) => !selectable.any((g) => g.id == id));
  final colors = context.colors;
  return showDialog<Set<String>>(
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
                managedGroupIds == null
                    ? 'Ninguno seleccionado = todos los equipos'
                    : 'Selecciona al menos uno de tus equipos.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in selectable)
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: (managedGroupIds != null && selected.isEmpty)
                ? null
                : () => Navigator.of(dialogContext).pop(selected),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Mobile row — unchanged behavior (tap pencil/trash to open a dialog).
class _StatusCardMobile extends StatelessWidget {
  const _StatusCardMobile({required this.status, required this.canEdit, required this.groups});

  final StatusModel status;
  final bool canEdit;
  final List<GroupModel> groups;

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
        leading: Icon(LucideIcons.listChecks, color: colors.primary),
        title: Text(status.name, style: TextStyle(color: colors.textPrimary)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Orden: ${status.order}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            _GroupScopeSummary(groupIds: status.groupIds, groups: groups),
          ],
        ),
        trailing: canEdit
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(LucideIcons.pencil, color: colors.primary, size: 18),
                    onPressed: () =>
                        _showStatusFormDialog(context, existing: status, groups: groups),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
                    onPressed: () => _deleteStatus(context, status),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

/// Tablet/desktop row: Nombre and Orden are real fields that save on blur.
class _StatusRowEditable extends StatefulWidget {
  const _StatusRowEditable({required this.status, required this.canEdit, required this.groups});

  final StatusModel status;
  final bool canEdit;
  final List<GroupModel> groups;

  @override
  State<_StatusRowEditable> createState() => _StatusRowEditableState();
}

class _StatusRowEditableState extends State<_StatusRowEditable> {
  late final _nameController = TextEditingController(text: widget.status.name);
  late final _orderController = TextEditingController(text: '${widget.status.order}');
  final _nameFocus = FocusNode();
  final _orderFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onNameFocusChange);
    _orderFocus.addListener(_onOrderFocusChange);
  }

  @override
  void didUpdateWidget(covariant _StatusRowEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_nameFocus.hasFocus && _nameController.text != widget.status.name) {
      _nameController.text = widget.status.name;
    }
    if (!_orderFocus.hasFocus && _orderController.text != '${widget.status.order}') {
      _orderController.text = '${widget.status.order}';
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
      _nameController.text = widget.status.name; // required — revert
      return;
    }
    if (newName == widget.status.name) return;
    _save(name: newName);
  }

  void _onOrderFocusChange() {
    if (_orderFocus.hasFocus) return;
    final newOrder = int.tryParse(_orderController.text.trim());
    if (newOrder == null) {
      _orderController.text = '${widget.status.order}'; // invalid — revert
      return;
    }
    if (newOrder == widget.status.order) return;
    _save(order: newOrder);
  }

  Future<void> _save({String? name, int? order}) async {
    final repo = context.read<CatalogRepository>();
    try {
      await repo.updateStatus(
        widget.status.id,
        name ?? widget.status.name,
        order ?? widget.status.order,
        groupIds: widget.status.groupIds,
      );
      if (mounted) SnackbarUtils.showSuccess(context, 'Estado actualizado');
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Future<void> _pickGroups() async {
    final repo = context.read<CatalogRepository>();
    final result = await _pickCatalogGroups(
      context,
      current: widget.status.groupIds.toSet(),
      groups: widget.groups,
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      await repo.updateStatus(widget.status.id, widget.status.name, widget.status.order,
          groupIds: result.toList());
      if (mounted) SnackbarUtils.showSuccess(context, 'Estado actualizado');
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
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
          Icon(LucideIcons.listChecks, color: colors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _RowField(
              label: 'Nombre',
              child: TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                enabled: widget.canEdit,
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
          SizedBox(
            width: 70,
            child: _RowField(
              label: 'Orden',
              child: TextField(
                controller: _orderController,
                focusNode: _orderFocus,
                enabled: widget.canEdit,
                keyboardType: TextInputType.number,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(isDense: true),
                onSubmitted: (_) => _orderFocus.unfocus(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: _RowField(
              label: 'Equipos',
              child: InkWell(
                onTap: widget.canEdit ? _pickGroups : null,
                child: _GroupScopeSummary(groupIds: widget.status.groupIds, groups: widget.groups),
              ),
            ),
          ),
          if (widget.canEdit) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: IconButton(
                icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
                onPressed: () => _deleteStatus(context, widget.status),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small column header, matching the Equipos/Tipos de tarea row convention.
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

/// Tablet/desktop always-visible right panel for creating a status — stays
/// in place (fields just clear) after a successful save.
class _CreateStatusPanel extends StatefulWidget {
  const _CreateStatusPanel({super.key, required this.groups, required this.managedGroupIds});

  final List<GroupModel> groups;

  /// Null for super_admin (unrestricted); a scoped admin_equipo's own
  /// managed teams otherwise — new entries are forced into a non-empty
  /// subset of these.
  final List<String>? managedGroupIds;

  @override
  State<_CreateStatusPanel> createState() => _CreateStatusPanelState();
}

/// Next "Orden" value offered by default in [_CreateStatusPanel] — one past
/// the highest order already in use (1 when there are none), so admins
/// don't have to look up the last order themselves.
int _nextStatusOrder(CatalogProvider catalog) {
  if (catalog.statuses.isEmpty) return 1;
  return catalog.statuses.map((s) => s.order).reduce((a, b) => a > b ? a : b) + 1;
}

class _CreateStatusPanelState extends State<_CreateStatusPanel> {
  final _nameController = TextEditingController();
  late final _orderController =
      TextEditingController(text: '${_nextStatusOrder(context.read<CatalogProvider>())}');
  final _formKey = GlobalKey<FormState>();
  Set<String> _groupIds = {};
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.managedGroupIds != null && _groupIds.isEmpty) {
      SnackbarUtils.showError(context, 'Selecciona al menos uno de tus equipos');
      return;
    }
    setState(() => _isSaving = true);
    final repo = context.read<CatalogRepository>();
    final order = int.parse(_orderController.text.trim());
    try {
      await repo.addStatus(_nameController.text.trim(), order, groupIds: _groupIds.toList());
      if (mounted) {
        _nameController.clear();
        _orderController.text = '${order + 1}';
        setState(() => _groupIds = {});
        SnackbarUtils.showSuccess(context, 'Estado creado');
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
    return SidePanelShell(
      title: 'Nuevo estado',
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
              decoration: const InputDecoration(labelText: 'Orden'),
              validator: (v) => int.tryParse(v ?? '') == null ? 'Ingresa un número' : null,
            ),
            const SizedBox(height: 12),
            _RowField(
              label: 'Equipos',
              child: OutlinedButton.icon(
                onPressed: () async {
                  final result = await _pickCatalogGroups(
                    context,
                    current: _groupIds,
                    groups: widget.groups,
                    managedGroupIds: widget.managedGroupIds,
                  );
                  if (result != null) setState(() => _groupIds = result);
                },
                icon: const Icon(LucideIcons.users, size: 16),
                label: Text(_groupIds.isEmpty ? 'Todos los equipos' : '${_groupIds.length} elegidos'),
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

Future<void> _showStatusFormDialog(
  BuildContext context, {
  StatusModel? existing,
  required List<GroupModel> groups,
  List<String>? managedGroupIds,
}) async {
  final colors = context.colors;
  final repo = context.read<CatalogRepository>();
  final catalog = context.read<CatalogProvider>();
  final nameController = TextEditingController(text: existing?.name ?? '');
  final orderController = TextEditingController(
    text: '${existing?.order ?? (catalog.statuses.length)}',
  );
  final formKey = GlobalKey<FormState>();
  Set<String> groupIds = {...(existing?.groupIds ?? const [])};
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text(existing == null ? 'Nuevo estado' : 'Editar estado'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    decoration: const InputDecoration(labelText: 'Orden'),
                    validator: (v) =>
                        int.tryParse(v ?? '') == null ? 'Ingresa un número' : null,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await _pickCatalogGroups(
                          dialogContext,
                          current: groupIds,
                          groups: groups,
                          managedGroupIds: managedGroupIds,
                        );
                        if (result != null) setState(() => groupIds = result);
                      },
                      icon: const Icon(LucideIcons.users, size: 16),
                      label: Text(groupIds.isEmpty ? 'Todos los equipos' : '${groupIds.length} equipos'),
                    ),
                  ),
                ],
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
                        if (managedGroupIds != null && groupIds.isEmpty) {
                          SnackbarUtils.showError(
                              dialogContext, 'Selecciona al menos uno de tus equipos');
                          return;
                        }
                        setState(() => isSaving = true);
                        final order = int.parse(orderController.text);
                        try {
                          if (existing == null) {
                            await repo.addStatus(nameController.text.trim(), order,
                                groupIds: groupIds.toList());
                          } else {
                            await repo.updateStatus(
                                existing.id, nameController.text.trim(), order,
                                groupIds: groupIds.toList());
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

Future<void> _deleteStatus(BuildContext context, StatusModel status) async {
  final confirm = await showConfirmDialog(
    context,
    title: 'Eliminar estado',
    message: '¿Eliminar el estado "${status.name}"?',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
  if (!confirm) return;
  if (!context.mounted) return;

  final repo = context.read<CatalogRepository>();
  try {
    await repo.deleteStatus(status.id);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Estado eliminado');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}
