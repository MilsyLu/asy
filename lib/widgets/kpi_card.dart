import 'package:flutter/material.dart';

import '../core/responsive/app_spacing.dart';
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
    final cards = [
      KpiCard(label: 'Tareas', value: '${kpis.total}', color: colors.primary),
      KpiCard(
        label: 'Completadas',
        value: '${kpis.completed}',
        color: colors.success,
      ),
      KpiCard(
        label: 'Pendientes',
        value: '${kpis.pending}',
        color: colors.statusPending,
      ),
      KpiCard(
        label: 'Reprogramadas',
        value: '${kpis.rescheduled}',
        color: colors.statusRescheduled,
      ),
      KpiCard(
        label: 'Cumplimiento',
        value: '${kpis.compliancePercent}%',
        color: colors.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Five cards need roughly this much before they stop being readable.
        // Above it they share the row evenly instead of huddling on the left
        // with the rest of the width unused; below it the row scrolls, which
        // is what it always did.
        if (constraints.maxWidth >= 620) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                cards[i],
              ],
            ],
          ),
        );
      },
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
