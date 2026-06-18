import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/report_metrics.dart';
import '../../core/utils/task_visibility.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../home/widgets/compact_task_card.dart' show taskStatusColor;

/// Admin-only executive dashboard ("¿Cómo va la operación?") — Sprint 6.2.
///
/// Reuses the same `TaskRepository.watchTasksInRange()` call already used by
/// Home/Reports plus the already-loaded [CatalogProvider] catalogs/users;
/// every KPI, highlight and chart below is derived locally from that single
/// stream — no new Firestore queries, streams or repositories.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const _rangeDays = 30;

  late final DateTime _start;
  late final DateTime _end;
  late final Stream<List<TaskModel>> _tasksStream;

  @override
  void initState() {
    super.initState();
    final repo = context.read<TaskRepository>();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day);
    _start = _end.subtract(const Duration(days: _rangeDays));
    _tasksStream = repo.watchTasksInRange(_start, _end);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final currentUser = context.watch<AuthProvider>().appUser;

    if (currentUser == null) {
      return const Scaffold(body: LoadingIndicator());
    }

    return Scaffold(
      body: StreamBuilder<List<TaskModel>>(
        stream: _tasksStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingIndicator();
          }
          if (snapshot.hasError) {
            return EmptyState(
              message: 'No se pudo cargar el dashboard.\n${snapshot.error}',
              icon: LucideIcons.alertCircle,
            );
          }

          final tasks = (snapshot.data ?? [])
              .where((t) => isTaskVisibleToUser(task: t, user: currentUser, catalog: catalog))
              .toList();

          if (tasks.isEmpty) {
            return const EmptyState(
              message: 'No hay tareas registradas en los últimos 30 días.',
              icon: LucideIcons.layoutDashboard,
            );
          }

          final kpis = computeTaskKpis(tasks, catalog);
          final topUser = topUserByCompleted(tasks, catalog);
          final groupCompliance = computeGroupCompliance(tasks, catalog)
            ..sort((a, b) => b.percent.compareTo(a.percent));
          final bestGroup = bestGroupCompliance(groupCompliance);
          final topClient = mostAttendedClient(tasks);
          final streakUser = bestActiveStreak(catalog.users);
          final statusDistribution = computeStatusDistribution(tasks, catalog);
          final dailyTrend =
              computeDailyTrend(tasks, _start, _end, AppDateUtils.formatDateKey);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _SectionLabel('Resumen · últimos $_rangeDays días'),
              const SizedBox(height: 10),
              KpiSummaryRow(kpis: kpis),
              const SizedBox(height: 24),
              _SectionTitle('Resumen visual'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _HighlightTile(
                    emoji: '🏆',
                    label: 'Más tareas completadas',
                    value: topUser?.name ?? 'Sin datos',
                  ),
                  _HighlightTile(
                    emoji: '👥',
                    label: 'Mejor cumplimiento',
                    value: bestGroup == null
                        ? 'Sin datos'
                        : '${catalog.groupName(bestGroup.groupId)} · ${bestGroup.percent}%',
                  ),
                  _HighlightTile(
                    emoji: '⭐',
                    label: 'Cliente más atendido',
                    value: topClient == null
                        ? 'Sin datos'
                        : '${topClient.name} · ${topClient.count}',
                  ),
                  _HighlightTile(
                    emoji: '🔥',
                    label: 'Mejor racha activa',
                    value: streakUser == null
                        ? 'Sin datos'
                        : '${streakUser.name} · ${streakUser.streakDays}d',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionTitle('Distribución de estados'),
              const SizedBox(height: 10),
              _DashboardCard(child: _StatusDistributionChart(distribution: statusDistribution)),
              const SizedBox(height: 24),
              _SectionTitle('Cumplimiento por grupo'),
              const SizedBox(height: 10),
              _DashboardCard(child: _GroupComplianceChart(groups: groupCompliance, catalog: catalog)),
              const SizedBox(height: 24),
              _SectionTitle('Tendencia de tareas'),
              const SizedBox(height: 10),
              _DashboardCard(child: _TrendChart(entries: dailyTrend)),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      text,
      style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      text,
      style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
    );
  }
}

/// Standard Material 3 card shell reused across every chart section so the
/// dashboard matches the existing card style instead of introducing a new
/// visual language.
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: child,
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({required this.emoji, required this.label, required this.value});

  final String emoji;
  final String label;
  final String value;

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
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.primary, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Part 6.1: "Distribución de estados" — reuses the same `fl_chart`
/// [PieChart] pattern already established in `StatusReportTab`, and
/// [taskStatusColor] (already shared by Calendar/Week) for per-status color.
class _StatusDistributionChart extends StatelessWidget {
  const _StatusDistributionChart({required this.distribution});

  final Map<String, int> distribution;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = distribution.entries.toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    if (total == 0) {
      return Text('Sin datos suficientes.', style: TextStyle(color: colors.textSecondary, fontSize: 13));
    }

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (final e in entries)
                  if (e.value > 0)
                    PieChartSectionData(
                      value: e.value.toDouble(),
                      title: '${e.value}',
                      color: taskStatusColor(colors, e.key),
                      radius: 56,
                      titleStyle: TextStyle(
                        color: colors.background,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final e in entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: taskStatusColor(colors, e.key),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${e.key} (${e.value})',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Part 6.2: "Cumplimiento por grupo" — a horizontal-bar ranking built from
/// the [GroupCompliance] breakdown already computed once in
/// `DashboardPage.build` (shared with the Part 5 "mejor cumplimiento" tile).
class _GroupComplianceChart extends StatelessWidget {
  const _GroupComplianceChart({required this.groups, required this.catalog});

  final List<GroupCompliance> groups;
  final CatalogProvider catalog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (groups.isEmpty) {
      return Text('Sin datos suficientes.', style: TextStyle(color: colors.textSecondary, fontSize: 13));
    }

    return Column(
      children: [
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        catalog.groupName(g.groupId),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${g.percent}%',
                      style: TextStyle(color: colors.success, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: g.percent / 100,
                    minHeight: 8,
                    backgroundColor: colors.divider,
                    color: colors.success,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Part 6.3: "Tendencia de tareas" — daily task count across the selected
/// range, via `fl_chart`'s [LineChart] (same package already used by
/// `StatusReportTab`'s [PieChart], no new dependency).
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.entries});

  final List<MapEntry<String, int>> entries;

  /// Picks a "nice" Y-axis step (1/2/5/10/20/50/...) so the left-axis labels
  /// land on round numbers instead of whatever fl_chart's automatic interval
  /// would compute for an arbitrary `maxCount * 1.2` ceiling.
  static double _niceYInterval(int maxValue) {
    if (maxValue <= 4) return 1;
    if (maxValue <= 10) return 2;
    if (maxValue <= 20) return 5;
    if (maxValue <= 50) return 10;
    if (maxValue <= 100) return 20;
    if (maxValue <= 200) return 50;
    return (maxValue / 5).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (entries.isEmpty) {
      return Text('Sin datos suficientes.', style: TextStyle(color: colors.textSecondary, fontSize: 13));
    }

    final spots = [
      for (var i = 0; i < entries.length; i++) FlSpot(i.toDouble(), entries[i].value.toDouble()),
    ];
    final maxCount = entries.map((e) => e.value).fold<int>(0, (m, v) => v > m ? v : m);

    // Align the axis ceiling to a clean multiple of the interval (plus one
    // step of headroom) instead of an arbitrary `* 1.2` value — otherwise
    // fl_chart's `maxIncluded` forces an extra label at maxY that lands right
    // next to the nearest interval tick and renders as an overlapping/
    // duplicated top value.
    final yInterval = _niceYInterval(maxCount);
    final topTick = maxCount == 0 ? yInterval : (maxCount / yInterval).ceil() * yInterval;
    final maxY = topTick + yInterval;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Del ${AppDateUtils.formatShortDate(AppDateUtils.parseDateKey(entries.first.key))} '
          'al ${AppDateUtils.formatShortDate(AppDateUtils.parseDateKey(entries.last.key))}',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: yInterval,
                    // Without this, fl_chart always draws an extra label
                    // exactly at maxY regardless of interval, which is what
                    // caused the duplicated/overlapping top value.
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        value.toInt().toString(),
                        style: TextStyle(color: colors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: colors.primary,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: colors.primary.withValues(alpha: 0.15)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
