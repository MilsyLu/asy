import 'package:flutter/material.dart';

import '../core/theme/theme_colors.dart';
import '../core/utils/report_metrics.dart';

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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          KpiCard(label: 'Tareas', value: '${kpis.total}', color: colors.primary),
          const SizedBox(width: 8),
          KpiCard(label: 'Completadas', value: '${kpis.completed}', color: colors.success),
          const SizedBox(width: 8),
          KpiCard(label: 'Pendientes', value: '${kpis.pending}', color: colors.statusPending),
          const SizedBox(width: 8),
          KpiCard(
            label: 'Reprogramadas',
            value: '${kpis.rescheduled}',
            color: colors.statusRescheduled,
          ),
          const SizedBox(width: 8),
          KpiCard(label: 'Cumplimiento', value: '${kpis.compliancePercent}%', color: colors.success),
        ],
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, required this.color});

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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
