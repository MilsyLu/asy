import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 2: pie chart summarizing rescheduled / installed / installation
/// / pending task counts within the selected range. [tasks] is the
/// already-loaded, visibility-filtered list shared by every report tab.
class StatusReportTab extends StatelessWidget {
  const StatusReportTab({super.key, required this.tasks});

  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;

    if (tasks.isEmpty) {
      return const EmptyState(
        message: 'No hay tareas registradas en el rango seleccionado.',
        icon: LucideIcons.pieChart,
      );
    }

    final installationTypeId = catalog.taskTypeByName(AppTaskTypeNames.instalacion)?.id;
    final pendingId = catalog.pendingStatusId;
    final completedId = catalog.completedStatusId;
    final rescheduledId = catalog.rescheduledStatusId;

    final metrics = <_Metric>[
      _Metric(
        'Reprogramadas',
        tasks.where((t) => t.statusId == rescheduledId).length,
        colors.error,
      ),
      _Metric(
        'Instaladas',
        tasks
            .where((t) => t.statusId == completedId && t.taskTypeId == installationTypeId)
            .length,
        colors.success,
      ),
      _Metric(
        'Tareas de instalación',
        tasks.where((t) => t.taskTypeId == installationTypeId).length,
        colors.primary,
      ),
      _Metric(
        'Pendientes',
        tasks.where((t) => t.statusId == pendingId).length,
        colors.primaryLight,
      ),
    ];

    final total = metrics.fold<int>(0, (sum, m) => sum + m.value);

    if (total == 0) {
      return const EmptyState(
        message: 'No hay datos suficientes para mostrar el gráfico.',
        icon: LucideIcons.pieChart,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              sections: [
                for (final m in metrics)
                  if (m.value > 0)
                    PieChartSectionData(
                      value: m.value.toDouble(),
                      title: '${m.value}',
                      color: m.color,
                      radius: 64,
                      titleStyle: TextStyle(
                        color: colors.background,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final m in metrics) _LegendRow(metric: m, total: total),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, color: colors.primary, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Las categorías pueden superponerse (por ejemplo, una '
                  'instalación completada también cuenta como "tarea de '
                  'instalación"), por lo que el total puede no coincidir '
                  'con el número de tareas.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric {
  _Metric(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.metric, required this.total});

  final _Metric metric;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final percentage = total == 0 ? 0.0 : (metric.value / total * 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: metric.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              metric.label,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
            ),
          ),
          Text(
            '${metric.value} (${percentage.toStringAsFixed(0)}%)',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
