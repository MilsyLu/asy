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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    Widget buildList({required bool shrink}) {
      if (filtered.isEmpty) {
        return EmptyState(
          message: query.isEmpty
              ? 'No hay clientes registrados todavía.'
              : 'Ningún cliente coincide con "$query".',
          icon: LucideIcons.contact,
        );
      }
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

    Widget body;
    if (isMobile) {
      body = Column(children: [searchField, Expanded(child: buildList(shrink: false))]);
    } else if (!canEdit) {
      // No create panel to show if this admin can't create/edit clients.
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidthWide),
          child: Column(
            children: [searchField, Expanded(child: buildList(shrink: false))],
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
                        children: [searchField, Expanded(child: buildList(shrink: false))],
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
                searchField,
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
