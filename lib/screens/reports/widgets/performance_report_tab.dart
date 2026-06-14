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

/// Report 3: per-user task counts (assigned / completed / rescheduled)
/// with quick highlight cards.
class PerformanceReportTab extends StatelessWidget {
  const PerformanceReportTab({super.key, required this.range});

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
        final stats = <String, _UserStats>{};
        for (final t in tasks) {
          final s = stats.putIfAbsent(t.assignedUserId, () => _UserStats());
          s.assigned++;
          if (t.statusId == completedId) s.completed++;
          s.rescheduled += t.rescheduledCount;
        }

        final entries = stats.entries.toList()
          ..sort((a, b) => catalog.userName(a.key).compareTo(catalog.userName(b.key)));

        _Highlight? mostCompleted;
        _Highlight? leastCompleted;
        _Highlight? mostAssigned;
        _Highlight? leastAssigned;
        _Highlight? mostRescheduled;

        for (final e in entries) {
          final name = catalog.userName(e.key);
          final s = e.value;
          if (mostCompleted == null || s.completed > mostCompleted.value) {
            mostCompleted = _Highlight(name, s.completed);
          }
          if (leastCompleted == null || s.completed < leastCompleted.value) {
            leastCompleted = _Highlight(name, s.completed);
          }
          if (mostAssigned == null || s.assigned > mostAssigned.value) {
            mostAssigned = _Highlight(name, s.assigned);
          }
          if (leastAssigned == null || s.assigned < leastAssigned.value) {
            leastAssigned = _Highlight(name, s.assigned);
          }
          if (mostRescheduled == null || s.rescheduled > mostRescheduled.value) {
            mostRescheduled = _Highlight(name, s.rescheduled);
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (mostCompleted != null)
                  _HighlightCard(
                    icon: LucideIcons.trophy,
                    label: 'Más completadas',
                    highlight: mostCompleted,
                    color: colors.success,
                  ),
                if (leastCompleted != null)
                  _HighlightCard(
                    icon: LucideIcons.trendingDown,
                    label: 'Menos completadas',
                    highlight: leastCompleted,
                    color: colors.error,
                  ),
                if (mostAssigned != null)
                  _HighlightCard(
                    icon: LucideIcons.briefcase,
                    label: 'Más asignadas',
                    highlight: mostAssigned,
                    color: colors.primary,
                  ),
                if (leastAssigned != null)
                  _HighlightCard(
                    icon: LucideIcons.briefcase,
                    label: 'Menos asignadas',
                    highlight: leastAssigned,
                    color: colors.textSecondary,
                  ),
                if (mostRescheduled != null)
                  _HighlightCard(
                    icon: LucideIcons.repeat,
                    label: 'Más reprogramaciones',
                    highlight: mostRescheduled,
                    color: colors.error,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Usuario')),
                  DataColumn(label: Text('Asignadas')),
                  DataColumn(label: Text('Completadas')),
                  DataColumn(label: Text('Reprogramadas')),
                ],
                rows: [
                  for (final e in entries)
                    DataRow(cells: [
                      DataCell(Text(catalog.userName(e.key))),
                      DataCell(Text('${e.value.assigned}')),
                      DataCell(Text('${e.value.completed}')),
                      DataCell(Text('${e.value.rescheduled}')),
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

class _UserStats {
  int assigned = 0;
  int completed = 0;
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
  });

  final IconData icon;
  final String label;
  final _Highlight highlight;
  final Color color;

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
            '${highlight.value}',
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
