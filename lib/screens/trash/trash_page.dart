import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/task_type_colors.dart';
import '../../models/task_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/task_type_chip.dart';

enum _TrashFilter { all, sevenDays, thirtyDays }

/// Admin-only screen that lists soft-deleted tasks and allows restoring or
/// permanently deleting them.
class TrashPage extends StatefulWidget {
  const TrashPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  _TrashFilter _filter = _TrashFilter.all;
  final _searchController = TextEditingController();
  String _query = '';

  // Sprint 7.4.4: a single stream for the whole page lifetime — the filter
  // chips above only change client-side filtering of already-fetched data,
  // so they must never trigger a new Firestore listener.
  late final Stream<List<TaskModel>> _tasksStream;
  late final Stopwatch _loadStopwatch;
  bool _loadLogged = false;

  @override
  void initState() {
    super.initState();
    _tasksStream = context.read<TaskRepository>().watchDeletedTasks();
    _loadStopwatch = Stopwatch()..start();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TaskModel> _applyFilter(List<TaskModel> tasks) {
    var result = tasks;
    if (_filter != _TrashFilter.all) {
      final days = _filter == _TrashFilter.sevenDays ? 7 : 30;
      final cutoff = DateTime.now().subtract(Duration(days: days));
      result = result.where((t) {
        final deletedAt = t.deletedAt;
        return deletedAt != null && deletedAt.isAfter(cutoff);
      }).toList();
    }
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((t) => t.clientName.toLowerCase().contains(query)).toList();
    }
    return result;
  }

  Future<void> _restore(TaskModel task) async {
    final repo = context.read<TaskRepository>();
    try {
      await repo.restoreTask(task.id);
      if (mounted) SnackbarUtils.showSuccess(context, 'Tarea restaurada');
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Future<void> _deleteAll(List<TaskModel> tasks) async {
    if (tasks.isEmpty) return;
    final repo = context.read<TaskRepository>();
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar todas',
      message: 'Esta acción no puede deshacerse.\n'
          'Se eliminarán definitivamente las ${tasks.length} tareas que estás viendo '
          '(según el filtro actual), no solo las que se ven en pantalla ahora mismo.',
      confirmLabel: 'Eliminar todas',
      destructive: true,
      confirmForegroundColor: Colors.white,
    );
    if (!confirm || !mounted) return;
    try {
      await repo.permanentlyDeleteTasks(tasks.map((t) => t.id).toList());
      if (mounted) {
        SnackbarUtils.showSuccess(context, 'Tareas eliminadas definitivamente');
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Future<void> _permanentlyDelete(TaskModel task) async {
    final repo = context.read<TaskRepository>();
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar permanentemente',
      message:
          'Esta acción no puede deshacerse.\nLa tarea será eliminada definitivamente de Firestore.',
      confirmLabel: 'Eliminar',
      destructive: true,
      confirmForegroundColor: Colors.white,
    );
    if (!confirm || !mounted) return;
    try {
      await repo.permanentlyDeleteTask(task.id);
      if (mounted) {
        SnackbarUtils.showSuccess(context, 'Tarea eliminada definitivamente');
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();

    final body = StreamBuilder<List<TaskModel>>(
      stream: _tasksStream,
      builder: (context, snapshot) {
        if (!_loadLogged && snapshot.connectionState != ConnectionState.waiting) {
          _loadLogged = true;
          debugPrint('[PERF] Papelera load: ${_loadStopwatch.elapsedMilliseconds}ms');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.alertCircle,
                    color: colors.error,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Error al cargar la papelera.\n'
                    'Es posible que el índice de Firestore no esté desplegado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        final tasks = _applyFilter(snapshot.data ?? []);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '${tasks.length} '
                '${tasks.length == 1 ? 'tarea eliminada' : 'tareas eliminadas'}',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
            // Filters, search (fills the remaining width), and the
            // destructive bulk action all on one row — the search bar and
            // "Eliminar todas" sit side by side, not stacked.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Todas',
                    selected: _filter == _TrashFilter.all,
                    onTap: () => setState(() => _filter = _TrashFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Últimos 7 días',
                    selected: _filter == _TrashFilter.sevenDays,
                    onTap: () =>
                        setState(() => _filter = _TrashFilter.sevenDays),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Últimos 30 días',
                    selected: _filter == _TrashFilter.thirtyDays,
                    onTap: () =>
                        setState(() => _filter = _TrashFilter.thirtyDays),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: colors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Buscar',
                        hintText: 'Nombre del cliente',
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
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: tasks.isEmpty ? null : () => _deleteAll(tasks),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: const Text('Eliminar todas'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            color: colors.textSecondary,
                            size: 52,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _query.trim().isEmpty
                                ? 'La papelera está vacía'
                                : 'Ningún cliente coincide con "${_query.trim()}"',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _query.trim().isEmpty
                                ? 'Las tareas eliminadas aparecerán aquí.'
                                : 'Probá con otro nombre o borrá la búsqueda.',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: tasks.length,
                      itemBuilder: (context, i) => context.isMobile
                          ? _TrashCard(
                              task: tasks[i],
                              catalog: catalog,
                              onRestore: () => _restore(tasks[i]),
                              onDelete: () => _permanentlyDelete(tasks[i]),
                            )
                          : _TrashRow(
                              task: tasks[i],
                              catalog: catalog,
                              onRestore: () => _restore(tasks[i]),
                              onDelete: () => _permanentlyDelete(tasks[i]),
                            ),
                    ),
            ),
          ],
        );
      },
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Papelera')),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? colors.primary : colors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.onPrimary : colors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trash task card
// ---------------------------------------------------------------------------

class _TrashCard extends StatelessWidget {
  const _TrashCard({
    required this.task,
    required this.catalog,
    required this.onRestore,
    required this.onDelete,
  });

  final TaskModel task;
  final CatalogProvider catalog;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final taskType = catalog.taskTypeName(task.taskTypeId);
    final typeColor =
        catalog.taskTypeById(task.taskTypeId)?.parsedColor ?? colors.primary;
    final formattedDate = AppDateUtils.formatShortDate(
      AppDateUtils.parseDateKey(task.date),
    );
    final deletedByName = task.deletedByName ?? 'Usuario desconocido';
    final createdByName =
        task.createdBy != null ? catalog.userName(task.createdBy) : 'No disponible';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.55),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.userCircle,
                          size: 15,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.clientName,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.tag,
                          size: 13,
                          color: typeColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: TaskTypeChip(
                            label: taskType,
                            color: typeColor,
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          size: 13,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Fecha original: $formattedDate ${task.hour}',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (task.deletedAt != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: 13,
                            color: colors.error.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Eliminada: ${AppDateUtils.formatDateTimeOrDash(task.deletedAt)}',
                            style: TextStyle(
                              color: colors.error.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.userPlus,
                          size: 13,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Creada por: $createdByName',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.userCircle,
                          size: 13,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Eliminado por: $deletedByName',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: onRestore,
                          icon: const Icon(LucideIcons.rotateCcw, size: 15),
                          label: const Text('Restaurar'),
                        ),
                        const SizedBox(width: 4),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colors.error,
                          ),
                          onPressed: onDelete,
                          icon: const Icon(LucideIcons.trash2, size: 15),
                          label: const Text('Eliminar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trash task row (tablet/desktop) — same info as _TrashCard but condensed
// into a single horizontal line so each entry takes far less vertical
// space. Mobile keeps _TrashCard unchanged.
// ---------------------------------------------------------------------------

class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.task,
    required this.catalog,
    required this.onRestore,
    required this.onDelete,
  });

  final TaskModel task;
  final CatalogProvider catalog;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final taskType = catalog.taskTypeName(task.taskTypeId);
    final typeColor =
        catalog.taskTypeById(task.taskTypeId)?.parsedColor ?? colors.primary;
    final formattedDate = AppDateUtils.formatShortDate(
      AppDateUtils.parseDateKey(task.date),
    );
    final deletedByName = task.deletedByName ?? 'Usuario desconocido';
    final createdByName =
        task.createdBy != null ? catalog.userName(task.createdBy) : 'No disponible';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;

          Widget actionButton(
            IconData icon,
            String label,
            VoidCallback onTap, {
            Color? color,
          }) {
            if (wide) {
              return TextButton.icon(
                onPressed: onTap,
                style: color != null ? TextButton.styleFrom(foregroundColor: color) : null,
                icon: Icon(icon, size: 15),
                label: Text(label),
              );
            }
            return IconButton(
              tooltip: label,
              onPressed: onTap,
              icon: Icon(icon, size: 18, color: color),
            );
          }

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.55),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.userCircle, size: 15, color: colors.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                task.clientName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            TaskTypeChip(label: taskType, color: typeColor, dense: true),
                            const SizedBox(width: 8),
                            actionButton(LucideIcons.rotateCcw, 'Restaurar', onRestore),
                            actionButton(
                              LucideIcons.trash2,
                              'Eliminar',
                              onDelete,
                              color: colors.error,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Secondary metadata as badges that size to their own
                        // content and wrap onto more lines instead of ever
                        // truncating — narrowing the window never hides info.
                        Padding(
                          padding: const EdgeInsets.only(left: 21),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _TrashMetaBadge(
                                icon: LucideIcons.calendar,
                                text: '$formattedDate ${task.hour}',
                              ),
                              if (task.deletedAt != null)
                                _TrashMetaBadge(
                                  icon: LucideIcons.trash2,
                                  text:
                                      'Eliminada: ${AppDateUtils.formatDateTimeOrDash(task.deletedAt)}',
                                  color: colors.error.withValues(alpha: 0.75),
                                ),
                              _TrashMetaBadge(
                                icon: LucideIcons.userPlus,
                                text: 'Creada por: $createdByName',
                              ),
                              _TrashMetaBadge(
                                icon: LucideIcons.userCircle,
                                text: 'Eliminado por: $deletedByName',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Small icon+text badge — sizes to its own content and never truncates.
/// Used for _TrashRow's secondary metadata so narrowing the window makes
/// badges wrap onto more lines instead of ever hiding information.
class _TrashMetaBadge extends StatelessWidget {
  const _TrashMetaBadge({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: c, fontSize: 12)),
      ],
    );
  }
}
