import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/available_hour_model.dart';
import '../../models/group_model.dart';
import '../../providers/auth_provider.dart';
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
  const AvailableHoursPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final isSuperAdmin = auth.isSuperAdmin;
    final canEditCatalogs = auth.hasPermission(AppPermissions.manageCatalogs);
    final managedGroupIds = isSuperAdmin ? null : (auth.appUser?.managedGroupIds ?? const <String>[]);
    // Same visibility rule as Estados: universal slots plus anything scoped
    // to one of this admin's own teams.
    final hours = (isSuperAdmin
        ? catalog.availableHours
        : catalog.availableHours
            .where((h) => h.groupIds.isEmpty || h.groupIds.any(auth.managesGroup))
            .toList())
      ..sort((a, b) => a.hour.compareTo(b.hour));
    final colors = context.colors;

    final body = hours.isEmpty
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
              final canEditThis = isSuperAdmin ||
                  (canEditCatalogs && item.groupIds.isNotEmpty && item.groupIds.every(auth.managesGroup));
              return Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
                ),
                child: ListTile(
                  leading: Icon(LucideIcons.clock, color: colors.primary),
                  title: Text(
                    item.hour,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: _GroupScopeSummary(groupIds: item.groupIds, groups: catalog.groups),
                  trailing: canEditThis
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(LucideIcons.pencil, color: colors.primary, size: 18),
                              onPressed: () => _editHour(context, item,
                                  groups: catalog.groups, managedGroupIds: managedGroupIds),
                            ),
                            IconButton(
                              icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
                              onPressed: () => _deleteHour(context, item),
                            ),
                          ],
                        )
                      : null,
                ),
              );
            },
          );
    final fab = (isSuperAdmin || canEditCatalogs)
        ? FloatingActionButton(
            onPressed: () =>
                _addHour(context, groups: catalog.groups, managedGroupIds: managedGroupIds),
            child: const Icon(LucideIcons.plus),
          )
        : null;
    if (!showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Horarios disponibles')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

/// Read-only chip summary of a catalog entry's team scope — empty means
/// universal (applies to every team). Mirrors statuses_page.dart's.
class _GroupScopeSummary extends StatelessWidget {
  const _GroupScopeSummary({required this.groupIds, required this.groups});

  final List<String> groupIds;
  final List<GroupModel> groups;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (groupIds.isEmpty) {
      return Text('Todos los equipos', style: TextStyle(color: colors.textSecondary, fontSize: 12));
    }
    final namesById = {for (final g in groups) g.id: g.name};
    final names = groupIds.map((id) => namesById[id]).whereType<String>().join(', ');
    return Text(names, style: TextStyle(color: colors.textSecondary, fontSize: 12));
  }
}

/// Multi-select dialog for a catalog entry's team scope — mirrors
/// statuses_page.dart's `_pickCatalogGroups`. Empty is valid ("universal")
/// unless [managedGroupIds] is non-null, in which case a scoped admin must
/// pick at least one of their own teams.
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

Future<void> _addHour(
  BuildContext context, {
  required List<GroupModel> groups,
  List<String>? managedGroupIds,
}) async {
  final repo = context.read<CatalogRepository>();
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
  );
  if (picked == null) return;
  if (!context.mounted) return;

  final result = await _pickCatalogGroups(context,
      current: const {}, groups: groups, managedGroupIds: managedGroupIds);
  if (result == null || !context.mounted) return;
  final groupIds = result;

  final hour = _formatTimeOfDay(picked);
  final exists = repo.getAvailableHours().then((list) => list.any((h) => h.hour == hour));
  try {
    if (await exists) {
      if (context.mounted) {
        SnackbarUtils.showError(context, 'Ese horario ya existe');
      }
      return;
    }
    await repo.addAvailableHour(hour, groupIds: groupIds.toList());
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Horario agregado');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}

Future<void> _editHour(
  BuildContext context,
  AvailableHourModel item, {
  required List<GroupModel> groups,
  List<String>? managedGroupIds,
}) async {
  final repo = context.read<CatalogRepository>();
  final picked = await showTimePicker(
    context: context,
    initialTime: _parseHour(item.hour),
  );
  if (picked == null) return;
  if (!context.mounted) return;

  final result = await _pickCatalogGroups(context,
      current: item.groupIds.toSet(), groups: groups, managedGroupIds: managedGroupIds);
  if (result == null) return;
  if (!context.mounted) return;

  final hour = _formatTimeOfDay(picked);
  try {
    await repo.updateAvailableHour(item.id, hour, groupIds: result.toList());
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
