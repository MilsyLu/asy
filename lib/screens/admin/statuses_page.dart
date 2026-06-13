import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/status_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

/// Admin: CRUD for `statuses` (name, order).
class StatusesPage extends StatelessWidget {
  const StatusesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final statuses = catalog.statuses;

    return Scaffold(
      appBar: AppBar(title: const Text('Estados')),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.info, color: AppColors.gold, size: 16),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Las funciones automáticas usan los nombres exactos '
                    '"Pendiente", "Completada" y "Reprogramada". Evita '
                    'renombrarlos o eliminarlos.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: statuses.isEmpty
                ? const EmptyState(
                    message: 'No hay estados creados todavía.',
                    icon: LucideIcons.listChecks,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: statuses.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final status = statuses[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
                        ),
                        child: ListTile(
                          leading: const Icon(LucideIcons.listChecks, color: AppColors.gold),
                          title: Text(status.name, style: const TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(
                            'Orden: ${status.order}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(LucideIcons.pencil, color: AppColors.gold, size: 18),
                                onPressed: () => _showStatusFormDialog(context, existing: status),
                              ),
                              IconButton(
                                icon: const Icon(LucideIcons.trash2, color: AppColors.error, size: 18),
                                onPressed: () => _deleteStatus(context, status),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showStatusFormDialog(context),
        child: const Icon(LucideIcons.plus),
      ),
    );
  }
}

Future<void> _showStatusFormDialog(BuildContext context, {StatusModel? existing}) async {
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
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: orderController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary),
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
