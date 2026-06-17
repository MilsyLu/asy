import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 5: client summary cards (Sprint 6.1 Part 4) + top 10 clients by
/// completed "Instalación" tasks within the selected range. [tasks] is the
/// already-loaded, visibility-filtered list shared by every report tab.
class TopClientsReportTab extends StatelessWidget {
  const TopClientsReportTab({super.key, required this.tasks});

  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;

    if (tasks.isEmpty) {
      return const EmptyState(
        message: 'No hay tareas registradas en el rango seleccionado.',
        icon: LucideIcons.award,
      );
    }

    final completedId = catalog.completedStatusId;
    final installationTypeId = catalog.taskTypeByName(AppTaskTypeNames.instalacion)?.id;

    // Built once from every task in range (not just completed installations)
    // so the Part 4 summary cards can report total/reprogramaciones too.
    final fullStats = <String, _ClientStats>{};
    for (final t in tasks) {
      final key = '${t.clientName}|${t.clientPhone}';
      final s = fullStats.putIfAbsent(key, () => _ClientStats(t.clientName, t.clientPhone));
      s.totalTasks++;
      if (t.statusId == completedId && t.taskTypeId == installationTypeId) s.installations++;
      s.rescheduled += t.rescheduledCount;
    }

    _ClientStats? mostTasks;
    _ClientStats? mostInstallations;
    _ClientStats? mostRescheduled;
    for (final s in fullStats.values) {
      if (mostTasks == null || s.totalTasks > mostTasks.totalTasks) mostTasks = s;
      if (mostInstallations == null || s.installations > mostInstallations.installations) {
        mostInstallations = s;
      }
      if (mostRescheduled == null || s.rescheduled > mostRescheduled.rescheduled) {
        mostRescheduled = s;
      }
    }

    final top = fullStats.values.where((s) => s.installations > 0).toList()
      ..sort((a, b) => b.installations.compareTo(a.installations));
    final top10 = top.take(10).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (mostTasks != null)
              _ClientSummaryCard(
                icon: LucideIcons.clipboardList,
                label: 'Más tareas',
                stats: mostTasks,
                value: mostTasks.totalTasks,
                suffix: ' tareas',
                color: colors.primary,
              ),
            if (mostInstallations != null && mostInstallations.installations > 0)
              _ClientSummaryCard(
                icon: LucideIcons.award,
                label: 'Más instalaciones',
                stats: mostInstallations,
                value: mostInstallations.installations,
                suffix: ' instalaciones',
                color: colors.success,
              ),
            if (mostRescheduled != null && mostRescheduled.rescheduled > 0)
              _ClientSummaryCard(
                icon: LucideIcons.repeat,
                label: 'Más reprogramaciones',
                stats: mostRescheduled,
                value: mostRescheduled.rescheduled,
                suffix: ' reprog.',
                color: colors.error,
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Ranking por instalaciones',
          style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (top10.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No hay instalaciones completadas en el rango seleccionado.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          )
        else
          for (var i = 0; i < top10.length; i++) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.background,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(top10[i].clientName, style: TextStyle(color: colors.textPrimary)),
                subtitle: Text(
                  top10[i].clientPhone,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                trailing: Text(
                  top10[i].installations == 1 ? '1 instalación' : '${top10[i].installations} instalaciones',
                  style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
      ],
    );
  }
}

class _ClientSummaryCard extends StatelessWidget {
  const _ClientSummaryCard({
    required this.icon,
    required this.label,
    required this.stats,
    required this.value,
    required this.suffix,
    required this.color,
  });

  final IconData icon;
  final String label;
  final _ClientStats stats;
  final int value;
  final String suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 170,
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
                child: Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stats.clientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            '$value$suffix',
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ClientStats {
  _ClientStats(this.clientName, this.clientPhone);

  final String clientName;
  final String clientPhone;
  int totalTasks = 0;
  int installations = 0;
  int rescheduled = 0;
}
