import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../models/app_user.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 3: per-user task counts (assigned / completed / rescheduled)
/// with quick highlight cards, a top-3 productivity ranking and a tap-for-
/// detail bottom sheet. [tasks] is the already-loaded, visibility-filtered
/// list shared by every report tab.
class PerformanceReportTab extends StatelessWidget {
  const PerformanceReportTab({super.key, required this.tasks});

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

    // Part 2 (Sprint 6.1): top 3 most productive — most completed first,
    // ties broken by fewer reprogramaciones, then by higher cumplimiento %.
    final ranked = entries.toList()
      ..sort((a, b) {
        final byCompleted = b.value.completed.compareTo(a.value.completed);
        if (byCompleted != 0) return byCompleted;
        final byRescheduled = a.value.rescheduled.compareTo(b.value.rescheduled);
        if (byRescheduled != 0) return byRescheduled;
        return b.value.compliance.compareTo(a.value.compliance);
      });
    final top3 = ranked.take(3).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (top3.isNotEmpty) ...[
          Text(
            'Top 3 más productivos',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < top3.length; i++)
            _TopProductiveRow(
              medal: const ['🥇', '🥈', '🥉'][i],
              name: catalog.userName(top3[i].key),
              stats: top3[i].value,
            ),
          const SizedBox(height: 20),
        ],
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
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Usuario')),
              DataColumn(label: Text('Asignadas')),
              DataColumn(label: Text('Completadas')),
              DataColumn(label: Text('Reprogramadas')),
            ],
            rows: [
              for (final e in entries)
                DataRow(
                  onSelectChanged: (_) =>
                      _showUserDetailSheet(context, catalog.userById(e.key), e.value),
                  cells: [
                    DataCell(Text(catalog.userName(e.key))),
                    DataCell(Text('${e.value.assigned}')),
                    DataCell(Text('${e.value.completed}')),
                    DataCell(Text('${e.value.rescheduled}')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Part 3 (Sprint 6.1): tap-for-detail bottom sheet with the user's full
/// stats for the selected range, reusing already-loaded data — no new
/// fields, no extra query. Racha actual / mejor racha come straight from
/// [AppUser.streakDays] / [AppUser.maxStreakDays].
void _showUserDetailSheet(BuildContext context, AppUser? user, _UserStats stats) {
  final colors = context.colors;
  final name = user?.name ?? 'Sin asignar';

  showModalBottomSheet(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.userCircle, color: colors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _DetailStat(label: 'Asignadas', value: '${stats.assigned}', color: colors.primary),
                  _DetailStat(label: 'Completadas', value: '${stats.completed}', color: colors.success),
                  _DetailStat(label: 'Reprogramadas', value: '${stats.rescheduled}', color: colors.error),
                  _DetailStat(
                    label: 'Cumplimiento',
                    value: '${stats.compliance}%',
                    color: colors.success,
                  ),
                  _DetailStat(
                    label: 'Racha actual',
                    value: '${user?.streakDays ?? 0}',
                    color: colors.statusPending,
                  ),
                  _DetailStat(
                    label: 'Mejor racha',
                    value: '${user?.maxStreakDays ?? 0}',
                    color: colors.statusPending,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TopProductiveRow extends StatelessWidget {
  const _TopProductiveRow({required this.medal, required this.name, required this.stats});

  final String medal;
  final String name;
  final _UserStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
          Text(medal, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${stats.completed} completadas',
            style: TextStyle(color: colors.success, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _UserStats {
  int assigned = 0;
  int completed = 0;
  int rescheduled = 0;

  int get compliance => assigned == 0 ? 0 : (completed * 100 ~/ assigned);
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
