import 'package:flutter/material.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';
import '../core/utils/report_metrics.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'kpi_metric.dart';

/// Horizontally scrollable Total/Completadas/Pendientes/Reprogramadas/
/// Cumplimiento % row, shared by `ReportsPage` (Sprint 6.1) and
/// `DashboardPage` (Sprint 6.2) so both render the same [TaskKpis] snapshot
/// identically instead of duplicating the cards.
class KpiSummaryRow extends StatelessWidget {
  const KpiSummaryRow({super.key, required this.kpis});

  final TaskKpis kpis;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Los mismos bloques del Dashboard, dentro de un solo recuadro separados
    // por líneas finas. Antes cada indicador era su propia cajita con el
    // nombre arriba a la izquierda y la cifra de color: la misma información
    // dibujada de dos formas distintas en dos pantallas de la misma app.
    final metricas = <Widget>[
      KpiMetric(
        icon: LucideIcons.clipboardList,
        title: 'Tareas',
        value: '${kpis.total}',
        accentColor: colors.primary,
        dense: true,
      ),
      KpiMetric(
        icon: LucideIcons.checkCircle2,
        title: 'Completadas',
        value: '${kpis.completed}',
        accentColor: colors.success,
        dense: true,
      ),
      KpiMetric(
        icon: LucideIcons.clock,
        title: 'Pendientes',
        value: '${kpis.pending}',
        accentColor: colors.statusPending,
        dense: true,
      ),
      KpiMetric(
        icon: LucideIcons.repeat2,
        title: 'Reprogramadas',
        value: '${kpis.rescheduled}',
        accentColor: colors.statusRescheduled,
        dense: true,
      ),
      KpiMetric(
        icon: LucideIcons.target,
        title: 'Cumplimiento',
        value: '${kpis.compliancePercent}%',
        accentColor: colors.success,
        dense: true,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Cinco bloques con "Reprogramadas" y "Cumplimiento" debajo piden
          // unos 480 px antes de que los nombres empiecen a cortarse. Por
          // debajo de eso se deslizan de lado, como el resto de la app.
          if (c.maxWidth >= 480) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < metricas.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 40,
                      color: colors.divider,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                    ),
                  Expanded(child: metricas[i]),
                ],
              ],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < metricas.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.md),
                  SizedBox(width: 110, child: metricas[i]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
