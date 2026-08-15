import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/client_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../services/task_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_sheet.dart';
import '../../widgets/side_panel_shell.dart';

/// Admin: CRUD for `clients`. Not team-scoped — `manageClients` is a flat
/// permission (see AppPermissions), so every admin who has it sees/edits
/// every client, unlike Equipos/Tipos de tarea/Estados/Horarios.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  // Tablet/desktop-only bulk inline-edit mode (Sprint UX: "Editar" toggles
  // every row's Nombre/Teléfono/Notas into text fields, "Guardar cambios"
  // persists all of them at once). Keyed by client id, not tied to the
  // current search filter, so filtering doesn't affect what gets saved.
  bool _editMode = false;
  bool _isSavingBulk = false;
  Map<String, _ClientEditControllers> _editControllers = {};

  @override
  void dispose() {
    _searchController.dispose();
    _disposeEditControllers();
    super.dispose();
  }

  void _disposeEditControllers() {
    for (final c in _editControllers.values) {
      c.dispose();
    }
    _editControllers = {};
  }

  void _enterEditMode(List<ClientModel> clients) {
    _disposeEditControllers();
    for (final c in clients) {
      _editControllers[c.id] = _ClientEditControllers(c);
    }
    setState(() => _editMode = true);
  }

  void _cancelEditMode() {
    _disposeEditControllers();
    setState(() => _editMode = false);
  }

  Future<void> _saveBulkEdits(List<ClientModel> clients) async {
    for (final c in clients) {
      final ctrl = _editControllers[c.id];
      if (ctrl != null && ctrl.name.text.trim().isEmpty) {
        SnackbarUtils.showError(context, 'El nombre de "${c.name}" no puede quedar vacío.');
        return;
      }
    }
    setState(() => _isSavingBulk = true);
    final repo = context.read<CatalogRepository>();
    var updated = 0;
    try {
      for (final c in clients) {
        final ctrl = _editControllers[c.id];
        if (ctrl == null) continue;
        final newName = ctrl.name.text.trim();
        final newPhone = Validators.cleanPhone(ctrl.phone.text);
        final newNotes = ctrl.notes.text.trim();
        if (newName != c.name || newPhone != c.phone || newNotes != c.notes) {
          await repo.updateClient(c.id, newName, newPhone, notes: newNotes);
          updated++;
        }
      }
      if (mounted) {
        SnackbarUtils.showSuccess(
          context,
          updated == 0 ? 'Sin cambios para guardar' : '$updated cliente(s) actualizado(s)',
        );
        _disposeEditControllers();
        setState(() => _editMode = false);
      }
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSavingBulk = false);
    }
  }

  Future<void> _confirmDeleteClient(ClientModel client) async {
    final catalogRepo = context.read<CatalogRepository>();
    final taskRepo = context.read<TaskRepository>();
    final catalog = context.read<CatalogProvider>();
    final history = await taskRepo.getClientTaskHistory(
      client.id,
      completedStatusId: catalog.completedStatusId,
      rescheduledStatusId: catalog.rescheduledStatusId,
    );
    if (!mounted) return;
    if (history.hasHistory) {
      await showInfoDialog(
        context,
        title: 'No es posible eliminar este cliente',
        message: 'Este cliente tiene ${history.total} tarea(s) registradas. '
            'Para conservar el historial, edita sus datos en lugar de eliminarlo.',
      );
      return;
    }
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar cliente',
      message: '¿Eliminar a "${client.name}" de forma permanente?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    try {
      await catalogRepo.deleteClient(client.id);
      _editControllers.remove(client.id);
      if (mounted) SnackbarUtils.showSuccess(context, 'Cliente eliminado');
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  /// Small read-only history popup, replacing the "Historial" section that
  /// used to live inside the old full-detail sheet — now its own per-row
  /// action so the row itself never needs to open a big form just to check
  /// history.
  void _showClientHistory(ClientModel client) {
    final taskRepo = context.read<TaskRepository>();
    final catalog = context.read<CatalogProvider>();
    final historyFuture = taskRepo.getClientTaskHistory(
      client.id,
      completedStatusId: catalog.completedStatusId,
      rescheduledStatusId: catalog.rescheduledStatusId,
    );
    showResponsiveSheet<void>(
      context,
      desktopMaxWidth: 380,
      contentBuilder: (sheetCtx) {
        final colors = sheetCtx.colors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: colors.primary.withValues(alpha: 0.15),
                      child: Icon(LucideIcons.contact, color: colors.primary, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        client.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: colors.divider, height: 1),
                const SizedBox(height: 16),
                FutureBuilder(
                  future: historyFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final history = snapshot.data!;
                    return Row(
                      children: [
                        Expanded(
                          child: _HistoryStatBox(
                            label: 'Tareas',
                            value: '${history.total}',
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HistoryStatBox(
                            label: 'Completadas',
                            value: '${history.completed}',
                            color: colors.success,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HistoryStatBox(
                            label: 'Reprogramadas',
                            value: '${history.rescheduled}',
                            color: colors.error,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final canEdit = auth.hasPermission(AppPermissions.manageClients);
    final isMobile = context.isMobile;
    final query = _query.trim().toLowerCase();
    final clients = List<ClientModel>.from(catalog.clients)
      ..sort((a, b) => a.name.compareTo(b.name));
    final filtered = query.isEmpty
        ? clients
        : clients
            .where((c) =>
                c.name.toLowerCase().contains(query) || c.phone.contains(query))
            .toList();

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Buscar',
          hintText: 'Nombre o teléfono',
          prefixIcon: Icon(LucideIcons.search, color: context.colors.primary, size: 18),
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
      ),
    );

    // Tablet/desktop only: search field + Editar/Guardar cambios/Cancelar
    // toolbar. Mobile keeps just the plain search field, untouched.
    final toolbar = (isMobile || !canEdit)
        ? searchField
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: searchField),
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: _editMode
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _isSavingBulk ? null : _cancelEditMode,
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton.icon(
                            onPressed: _isSavingBulk ? null : () => _saveBulkEdits(clients),
                            icon: _isSavingBulk
                                ? const SizedBox(
                                    height: 14,
                                    width: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.check, size: 16),
                            label: const Text('Guardar cambios'),
                          ),
                        ],
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _enterEditMode(clients),
                        icon: const Icon(LucideIcons.pencil, size: 16),
                        label: const Text('Editar'),
                      ),
              ),
            ],
          );

    Widget buildList({required bool shrink}) {
      if (filtered.isEmpty) {
        return EmptyState(
          message: query.isEmpty
              ? 'No hay clientes registrados todavía.'
              : 'Ningún cliente coincide con "$query".',
          icon: LucideIcons.contact,
        );
      }
      if (isMobile) {
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          shrinkWrap: shrink,
          physics: shrink ? const NeverScrollableScrollPhysics() : null,
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final client = filtered[index];
            return _ClientCard(
              client: client,
              onTap: () => _showClientDetailSheet(context, client, canEdit: canEdit),
            );
          },
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shrinkWrap: shrink,
        physics: shrink ? const NeverScrollableScrollPhysics() : null,
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final client = filtered[index];
          return _ClientTableRow(
            client: client,
            editControllers: _editMode ? _editControllers[client.id] : null,
            canEdit: canEdit,
            onHistory: () => _showClientHistory(client),
            onDelete: () => _confirmDeleteClient(client),
          );
        },
      );
    }

    Widget body;
    if (isMobile) {
      body = Column(children: [toolbar, Expanded(child: buildList(shrink: false))]);
    } else if (!canEdit) {
      // No create panel to show if this admin can't create/edit clients.
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidthWide),
          child: Column(
            children: [toolbar, Expanded(child: buildList(shrink: false))],
          ),
        ),
      );
    } else {
      // Same width-aware rule as Equipos/Usuarios/Estados.
      body = LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 900;
          const panel = _CreateClientPanel(key: ValueKey('create-client'));

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
                        children: [toolbar, Expanded(child: buildList(shrink: false))],
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
                toolbar,
                buildList(shrink: true),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: panel,
                ),
              ],
            ),
          );
        },
      );
    }

    final fab = isMobile && canEdit
        ? FloatingActionButton(
            onPressed: () => _showClientFormDialog(context),
            child: const Icon(LucideIcons.userPlus),
          )
        : null;
    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onTap});

  final ClientModel client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colors.primary.withValues(alpha: 0.15),
              child: Icon(LucideIcons.contact, color: colors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    client.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (client.phone.isNotEmpty)
                    Text(
                      Validators.formatPhone(client.phone),
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                  if (client.notes.isNotEmpty)
                    Text(
                      client.notes,
                      style: TextStyle(color: colors.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: colors.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Per-client text controllers used while [_ClientsPageState._editMode] is
/// active — pre-filled with the client's current values, diffed against
/// them again on save so only actually-changed rows trigger a write.
class _ClientEditControllers {
  _ClientEditControllers(ClientModel client)
      : name = TextEditingController(text: client.name),
        phone = TextEditingController(text: client.phone),
        notes = TextEditingController(text: client.notes);

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController notes;

  void dispose() {
    name.dispose();
    phone.dispose();
    notes.dispose();
  }
}

/// Tablet/desktop horizontal row: Nombre | Teléfono | Notas | Historial |
/// Eliminar. Replaces the old tap-to-open-sheet interaction on these
/// widths — editing happens in place (see [editControllers]) and history/
/// delete are their own small per-row actions instead of being bundled
/// into one big sheet. Mobile keeps [_ClientCard] instead, unchanged.
class _ClientTableRow extends StatelessWidget {
  const _ClientTableRow({
    required this.client,
    required this.editControllers,
    required this.canEdit,
    required this.onHistory,
    required this.onDelete,
  });

  final ClientModel client;

  /// Non-null while bulk edit mode is active — swaps the row's text into
  /// editable fields bound to these controllers.
  final _ClientEditControllers? editControllers;
  final bool canEdit;
  final VoidCallback onHistory;
  final VoidCallback onDelete;

  Widget _cell(BuildContext context, {
    required int flex,
    required String value,
    required TextEditingController? controller,
    required String hint,
  }) {
    final colors = context.colors;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: controller != null
            ? TextFormField(
                controller: controller,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hint,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              )
            : Text(
                value.isEmpty ? '—' : value,
                style: TextStyle(
                  color: value.isEmpty ? colors.textSecondary : colors.textPrimary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final editing = editControllers != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: editing ? 0.45 : 0.15)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showNotes = constraints.maxWidth >= 480;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: colors.primary.withValues(alpha: 0.15),
                child: Icon(LucideIcons.contact, color: colors.primary, size: 13),
              ),
              const SizedBox(width: 8),
              _cell(
                context,
                flex: 3,
                value: client.name,
                controller: editControllers?.name,
                hint: 'Nombre',
              ),
              _cell(
                context,
                flex: 2,
                value: client.phone.isEmpty ? '' : Validators.formatPhone(client.phone),
                controller: editControllers?.phone,
                hint: 'Teléfono',
              ),
              if (showNotes)
                _cell(
                  context,
                  flex: 3,
                  value: client.notes,
                  controller: editControllers?.notes,
                  hint: 'Notas',
                ),
              IconButton(
                tooltip: 'Historial',
                icon: Icon(LucideIcons.clock, size: 17, color: colors.primary),
                onPressed: onHistory,
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'Eliminar',
                  icon: Icon(LucideIcons.trash2, size: 17, color: colors.error),
                  onPressed: onDelete,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tablet/desktop always-visible right panel for creating a client — stays
/// in place (fields just clear) after a successful save.
class _CreateClientPanel extends StatefulWidget {
  const _CreateClientPanel({super.key});

  @override
  State<_CreateClientPanel> createState() => _CreateClientPanelState();
}

class _CreateClientPanelState extends State<_CreateClientPanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final repo = context.read<CatalogRepository>();
    try {
      await repo.addClient(
        _nameController.text.trim(),
        Validators.cleanPhone(_phoneController.text),
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        _formKey.currentState!.reset();
        _nameController.clear();
        _phoneController.clear();
        _notesController.clear();
        SnackbarUtils.showSuccess(context, 'Cliente creado');
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
      title: 'Nuevo cliente',
      icon: LucideIcons.userPlus,
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
              validator: (v) => Validators.required(v, fieldName: 'El nombre'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
              validator: Validators.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
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
                  : const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showClientFormDialog(BuildContext context) async {
  final colors = context.colors;
  final repo = context.read<CatalogRepository>();
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final notesController = TextEditingController();
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('Nuevo cliente'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (v) => Validators.required(v, fieldName: 'El nombre'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
                      validator: Validators.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Notas (opcional)'),
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
                        try {
                          await repo.addClient(
                            nameController.text.trim(),
                            Validators.cleanPhone(phoneController.text),
                            notes: notesController.text.trim(),
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                            SnackbarUtils.showSuccess(context, 'Cliente creado');
                          }
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
                    : const Text('Crear'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showClientDetailSheet(
  BuildContext context,
  ClientModel client, {
  required bool canEdit,
}) async {
  final colors = context.colors;
  final catalogRepo = context.read<CatalogRepository>();
  final taskRepo = context.read<TaskRepository>();
  final catalog = context.read<CatalogProvider>();
  final nameController = TextEditingController(text: client.name);
  final phoneController = TextEditingController(text: client.phone);
  final notesController = TextEditingController(text: client.notes);
  bool isSaving = false;
  final historyFuture = taskRepo.getClientTaskHistory(
    client.id,
    completedStatusId: catalog.completedStatusId,
    rescheduledStatusId: catalog.rescheduledStatusId,
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: colors.primary.withValues(alpha: 0.15),
                        child: Icon(LucideIcons.contact, color: colors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          client.name,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    enabled: canEdit,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    enabled: canEdit,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    enabled: canEdit,
                    maxLines: 2,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Notas'),
                  ),
                  if (canEdit) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setState(() => isSaving = true);
                                try {
                                  await catalogRepo.updateClient(
                                    client.id,
                                    nameController.text.trim(),
                                    Validators.cleanPhone(phoneController.text),
                                    notes: notesController.text.trim(),
                                  );
                                  if (sheetContext.mounted) {
                                    SnackbarUtils.showSuccess(
                                        sheetContext, 'Cliente actualizado');
                                  }
                                } catch (e) {
                                  if (sheetContext.mounted) {
                                    SnackbarUtils.showError(
                                        sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                                  }
                                } finally {
                                  if (sheetContext.mounted) {
                                    setState(() => isSaving = false);
                                  }
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Guardar cambios'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text('Historial', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  FutureBuilder(
                    future: historyFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final history = snapshot.data!;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _HistoryChip(label: '${history.total} tareas'),
                          _HistoryChip(label: '${history.completed} completadas'),
                          _HistoryChip(label: '${history.rescheduled} reprogramadas'),
                        ],
                      );
                    },
                  ),
                  if (canEdit) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.error,
                          side: BorderSide(color: colors.error),
                        ),
                        onPressed: () async {
                          final history = await historyFuture;
                          if (history.hasHistory) {
                            if (!sheetContext.mounted) return;
                            await showInfoDialog(
                              sheetContext,
                              title: 'No es posible eliminar este cliente',
                              message: 'Este cliente tiene ${history.total} tarea(s) '
                                  'registradas. Para conservar el historial, edita sus '
                                  'datos en lugar de eliminarlo.',
                            );
                            return;
                          }
                          if (!sheetContext.mounted) return;
                          final confirm = await showConfirmDialog(
                            sheetContext,
                            title: 'Eliminar cliente',
                            message: '¿Eliminar a "${client.name}" de forma permanente?',
                            confirmLabel: 'Eliminar',
                            destructive: true,
                          );
                          if (!confirm) return;
                          try {
                            await catalogRepo.deleteClient(client.id);
                            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                            if (context.mounted) {
                              SnackbarUtils.showSuccess(context, 'Cliente eliminado');
                            }
                          } catch (e) {
                            if (sheetContext.mounted) {
                              SnackbarUtils.showError(
                                  sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                            }
                          }
                        },
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        label: const Text('Eliminar'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: colors.primary, fontSize: 11)),
    );
  }
}

/// Boxed stat used by the tablet/desktop "Historial" popup — label above a
/// large bold number, matching the visual weight of stat boxes used
/// elsewhere in the app (e.g. Reportes) instead of the plainer pill chips.
class _HistoryStatBox extends StatelessWidget {
  const _HistoryStatBox({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
