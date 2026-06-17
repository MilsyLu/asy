import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 6: per-group task counts (asignadas / completadas / rendimiento)
/// plus a cumplimiento-ranked list (Sprint 6.1 Part 5).
///
/// Tasks created before this feature (`groupId == null`) are bucketed under
/// "Sin grupo" (see [CatalogProvider.groupName]). [tasks] is the already-
/// loaded, visibility-filtered list shared by every report tab.
class GroupsReportTab extends StatelessWidget {
  const GroupsReportTab({super.key, required this.tasks});

  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;

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

    // Part 5 (Sprint 6.1): ranking de grupos por cumplimiento, reusing the
    // already-computed `entries` — no new query, no logic change to `stats`.
    final ranked = entries.toList()
      ..sort((a, b) {
        final perfA = a.value.assigned == 0 ? 0 : (a.value.completed * 100 ~/ a.value.assigned);
        final perfB = b.value.assigned == 0 ? 0 : (b.value.completed * 100 ~/ b.value.assigned);
        return perfB.compareTo(perfA);
      });

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
        Text(
          'Ranking de grupos · Cumplimiento',
          style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < ranked.length; i++)
          _GroupRankRow(position: i + 1, name: catalog.groupName(ranked[i].key), stats: ranked[i].value),
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
  }
}

class _GroupRankRow extends StatelessWidget {
  const _GroupRankRow({required this.position, required this.name, required this.stats});

  final int position;
  final String name;
  final _GroupStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final performance = stats.assigned == 0 ? 0 : (stats.completed * 100 ~/ stats.assigned);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: colors.background,
            child: Text(
              '$position',
              style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$performance% · ${stats.rescheduled} reprog.',
            style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
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
