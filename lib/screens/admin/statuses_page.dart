import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/status_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/side_panel_shell.dart';

/// Admin: CRUD for `statuses` (name, order).
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
    final statuses = catalog.statuses;
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
          // Tablet/desktop: name/order editable right on the row.
          // Mobile keeps the "Editar" dialog and the FAB.
          return isMobile
              ? _StatusCardMobile(status: status)
              : _StatusRowEditable(status: status);
        },
      );
    }

    Widget body;
    if (isMobile) {
      body = Column(children: [infoBanner, Expanded(child: buildList(shrink: false))]);
    } else {
      // Same width-aware rule as Equipos/Usuarios: below ~900px of actual
      // available width, stack the "Nuevo estado" panel under the list
      // instead of squeezing both side by side.
      body = LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 900;
          const panel = _CreateStatusPanel(key: ValueKey('create-status'));

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
                infoBanner,
                const SizedBox(height: 12),
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

    // Tablet/desktop: the panel replaces the FAB for creating a status.
    final fab = isMobile
        ? FloatingActionButton(
            onPressed: () => _showStatusFormDialog(context),
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

/// Mobile row — unchanged behavior (tap pencil/trash to open a dialog).
class _StatusCardMobile extends StatelessWidget {
  const _StatusCardMobile({required this.status});

  final StatusModel status;

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
        subtitle: Text(
          'Orden: ${status.order}',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(LucideIcons.pencil, color: colors.primary, size: 18),
              onPressed: () => _showStatusFormDialog(context, existing: status),
            ),
            IconButton(
              icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
              onPressed: () => _deleteStatus(context, status),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tablet/desktop row: Nombre and Orden are real fields that save on blur.
class _StatusRowEditable extends StatefulWidget {
  const _StatusRowEditable({required this.status});

  final StatusModel status;

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
      );
      if (mounted) SnackbarUtils.showSuccess(context, 'Estado actualizado');
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
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
          SizedBox(
            width: 84,
            child: _RowField(
              label: 'Orden',
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
              onPressed: () => _deleteStatus(context, widget.status),
            ),
          ),
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
  const _CreateStatusPanel({super.key});

  @override
  State<_CreateStatusPanel> createState() => _CreateStatusPanelState();
}

class _CreateStatusPanelState extends State<_CreateStatusPanel> {
  final _nameController = TextEditingController();
  final _orderController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final repo = context.read<CatalogRepository>();
    final order = int.parse(_orderController.text.trim());
    try {
      await repo.addStatus(_nameController.text.trim(), order);
      if (mounted) {
        _nameController.clear();
        _orderController.clear();
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

Future<void> _showStatusFormDialog(BuildContext context, {StatusModel? existing}) async {
  final colors = context.colors;
  final repo = context.read<CatalogRepository>();
  final catalog = context.read<CatalogProvider>();
  final nameController = TextEditingController(text: existing?.name ?? '');
  final orderController = TextEditingController(
    text: '${existing?.order ?? (catalog.statuses.length)}',
  );
  final formKey = GlobalKey<FormState>();
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
                        setState(() => isSaving = true);
                        final order = int.parse(orderController.text);
                        try {
                          if (existing == null) {
                            await repo.addStatus(nameController.text.trim(), order);
                          } else {
                            await repo.updateStatus(existing.id, nameController.text.trim(), order);
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
