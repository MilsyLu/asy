import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/available_hour_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

TimeOfDay _parseHour(String hour) {
  final parts = hour.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
  );
}

/// Admin: CRUD for `availableHours` (the hours selectable when scheduling
/// a task), each picked via a native time picker.
class AvailableHoursPage extends StatelessWidget {
  const AvailableHoursPage({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final hours = List<AvailableHourModel>.from(catalog.availableHours)
      ..sort((a, b) => a.hour.compareTo(b.hour));

    return Scaffold(
      appBar: AppBar(title: const Text('Horarios disponibles')),
      body: hours.isEmpty
          ? const EmptyState(
              message: 'No hay horarios configurados todavía.',
              icon: LucideIcons.clock,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: hours.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = hours[index];
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
                  ),
                  child: ListTile(
                    leading: const Icon(LucideIcons.clock, color: AppColors.gold),
                    title: Text(
                      item.hour,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.pencil, color: AppColors.gold, size: 18),
                          onPressed: () => _editHour(context, item),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, color: AppColors.error, size: 18),
                          onPressed: () => _deleteHour(context, item),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addHour(context),
        child: const Icon(LucideIcons.plus),
      ),
    );
  }
}

Future<void> _addHour(BuildContext context) async {
  final repo = context.read<CatalogRepository>();
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
  );
  if (picked == null) return;
  if (!context.mounted) return;

  final hour = _formatTimeOfDay(picked);
  final exists = repo.getAvailableHours().then((list) => list.any((h) => h.hour == hour));
  try {
    if (await exists) {
      if (context.mounted) {
        SnackbarUtils.showError(context, 'Ese horario ya existe');
      }
      return;
    }
    await repo.addAvailableHour(hour);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Horario agregado');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}

Future<void> _editHour(BuildContext context, AvailableHourModel item) async {
  final repo = context.read<CatalogRepository>();
  final picked = await showTimePicker(
    context: context,
    initialTime: _parseHour(item.hour),
  );
  if (picked == null) return;
  if (!context.mounted) return;

  final hour = _formatTimeOfDay(picked);
  try {
    await repo.updateAvailableHour(item.id, hour);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Horario actualizado');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}

Future<void> _deleteHour(BuildContext context, AvailableHourModel item) async {
  final confirm = await showConfirmDialog(
    context,
    title: 'Eliminar horario',
    message: '¿Eliminar el horario "${item.hour}"?',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
  if (!confirm) return;
  if (!context.mounted) return;

  final repo = context.read<CatalogRepository>();
  try {
    await repo.deleteAvailableHour(item.id);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Horario eliminado');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}
