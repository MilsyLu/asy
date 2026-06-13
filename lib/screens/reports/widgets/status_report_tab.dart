import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/task_visibility.dart';
import '../../../models/task_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/catalog_provider.dart';
import '../../../services/task_repository.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 2: pie chart summarizing rescheduled / installed / installation
/// / pending task counts within the selected range.
class StatusReportTab extends StatelessWidget {
  const StatusReportTab({super.key, required this.range});

  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    final catalog = context.watch<CatalogProvider>();
    final currentUser = context.watch<AuthProvider>().appUser;

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
            AppColors.error,
          ),
          _Metric(
            'Instaladas',
            tasks
                .where((t) => t.statusId == completedId && t.taskTypeId == installationTypeId)
                .length,
            AppColors.success,
          ),
          _Metric(
            'Tareas de instalación',
            tasks.where((t) => t.taskTypeId == installationTypeId).length,
            AppColors.gold,
          ),
          _Metric(
            'Pendientes',
            tasks.where((t) => t.statusId == pendingId).length,
            AppColors.goldLight,
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
                          titleStyle: const TextStyle(
                            color: AppColors.background,
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
                      'Las categorías pueden superponerse (por ejemplo, una '
                      'instalación completada también cuenta como "tarea de '
                      'instalación"), por lo que el total puede no coincidir '
                      'con el número de tareas.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          Text(
            '${metric.value} (${percentage.toStringAsFixed(0)}%)',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
