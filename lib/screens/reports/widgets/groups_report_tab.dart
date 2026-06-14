import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/task_visibility.dart';
import '../../../models/task_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/catalog_provider.dart';
import '../../../services/task_repository.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 6: per-group task counts (asignadas / completadas / rendimiento).
///
/// Tasks created before this feature (`groupId == null`) are bucketed under
/// "Sin grupo" (see [CatalogProvider.groupName]).
class GroupsReportTab extends StatelessWidget {
  const GroupsReportTab({super.key, required this.range});

  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    final catalog = context.watch<CatalogProvider>();
    final currentUser = context.watch<AuthProvider>().appUser;
    final colors = context.colors;

    if (currentUser == null) return const LoadingIndicator();

    return StreamBuilder<List<TaskModel>>(
      stream: repo.watchTasksInRange(range.start, range.end),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }
        if (snapshot.hasError) {
          return EmptyState(
            message: 'No se pudieron cargar las tareas.\n${snapshot.error}',
            icon: LucideIcons.alertCircle,
          );
        }

        final tasks = (snapshot.data ?? [])
            .where((t) => isTaskVisibleToUser(
                  task: t,
                  user: currentUser,
                  catalog: catalog,
                ))
            .toList();

        if (tasks.isEmpty) {
          return const EmptyState(
            message: 'No hay tareas registradas en el rango seleccionado.',
            icon: LucideIcons.users,
          );
        }

        final completedId = catalog.completedStatusId;
        final stats = <String?, _GroupStats>{};
        for (final t in tasks) {
          final s = stats.putIfAbsent(t.groupId, () => _GroupStats());
          s.assigned++;
          if (t.statusId == completedId) {
            s.completed++;
          } else {
            s.pending++;
          }
          s.rescheduled += t.rescheduledCount;
        }

        final entries = stats.entries.toList()
          ..sort((a, b) => catalog.groupName(a.key).compareTo(catalog.groupName(b.key)));

        _Highlight? mostAssigned;
        _Highlight? mostCompleted;
        _Highlight? bestPerformance;
        _Highlight? worstPerformance;

        for (final e in entries) {
          final name = catalog.groupName(e.key);
          final s = e.value;
          final performance = s.assigned == 0 ? 0 : (s.completed * 100 ~/ s.assigned);

          if (mostAssigned == null || s.assigned > mostAssigned.value) {
            mostAssigned = _Highlight(name, s.assigned);
          }
          if (mostCompleted == null || s.completed > mostCompleted.value) {
            mostCompleted = _Highlight(name, s.completed);
          }
          if (bestPerformance == null || performance > bestPerformance.value) {
            bestPerformance = _Highlight(name, performance);
          }
          if (worstPerformance == null || performance < worstPerformance.value) {
            worstPerformance = _Highlight(name, performance);
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (mostAssigned != null)
                  _HighlightCard(
                    icon: LucideIcons.briefcase,
                    label: 'Más tareas asignadas',
                    highlight: mostAssigned,
                    color: colors.primary,
                  ),
                if (mostCompleted != null)
                  _HighlightCard(
                    icon: LucideIcons.trophy,
                    label: 'Más tareas completadas',
                    highlight: mostCompleted,
                    color: colors.success,
                  ),
                if (bestPerformance != null)
                  _HighlightCard(
                    icon: LucideIcons.trendingUp,
                    label: 'Mejor rendimiento',
                    highlight: bestPerformance,
                    color: colors.success,
                    suffix: '%',
                  ),
                if (worstPerformance != null)
                  _HighlightCard(
                    icon: LucideIcons.trendingDown,
                    label: 'Menor rendimiento',
                    highlight: worstPerformance,
                    color: colors.error,
                    suffix: '%',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Grupo')),
                  DataColumn(label: Text('Asignadas')),
                  DataColumn(label: Text('Completadas')),
                  DataColumn(label: Text('Pendientes')),
                  DataColumn(label: Text('Reprogramadas')),
                  DataColumn(label: Text('Rendimiento')),
                ],
                rows: [
                  for (final e in entries)
                    DataRow(cells: [
                      DataCell(Text(catalog.groupName(e.key))),
                      DataCell(Text('${e.value.assigned}')),
                      DataCell(Text('${e.value.completed}')),
                      DataCell(Text('${e.value.pending}')),
                      DataCell(Text('${e.value.rescheduled}')),
                      DataCell(Text(
                        '${e.value.assigned == 0 ? 0 : e.value.completed * 100 ~/ e.value.assigned}%',
                      )),
                    ]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupStats {
  int assigned = 0;
  int completed = 0;
  int pending = 0;
  int rescheduled = 0;
}

class _Highlight {
  _Highlight(this.name, this.value);

  final String name;
  final int value;
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.icon,
    required this.label,
    required this.highlight,
    required this.color,
    this.suffix = '',
  });

  final IconData icon;
  final String label;
  final _Highlight highlight;
  final Color color;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            highlight.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${highlight.value}$suffix',
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
