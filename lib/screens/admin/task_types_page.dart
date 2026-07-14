import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/task_type_colors.dart';
import '../../models/task_type_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

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

/// Human-readable summary of which groups [type] is offered for.
String _groupsLabel(CatalogProvider catalog, TaskTypeModel type) {
  if (type.groupIds.isEmpty) return 'Todos';
  return type.groupIds.map((id) => catalog.groupById(id)?.name ?? '?').join(', ');
}

/// Admin: CRUD for `taskTypes` (name, order, optional color).
class TaskTypesPage extends StatelessWidget {
  const TaskTypesPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final taskTypes = catalog.taskTypes;
    final colors = context.colors;

    final body = taskTypes.isEmpty
        ? const EmptyState(
            message: 'No hay tipos de tarea creados todavía.',
            icon: LucideIcons.tag,
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: taskTypes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final type = taskTypes[index];
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
                    'Orden: ${type.order} • Grupos: ${_groupsLabel(catalog, type)}',
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
            },
          );
    final fab = FloatingActionButton(
      onPressed: () => _showTaskTypeFormDialog(context),
      child: const Icon(LucideIcons.plus),
    );
    if (!showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Tipos de tarea')),
      body: body,
      floatingActionButton: fab,
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
                      decoration: const InputDecoration(labelText: 'Orden'),
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
                      'Grupos (ninguno seleccionado = todos)',
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
