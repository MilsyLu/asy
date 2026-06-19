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
import '../../widgets/loading_indicator.dart';
import '../home/widgets/compact_task_card.dart' show taskStatusColor;

/// Spacing system (Sprint 6.3.1): 24px between sections, 12px between
/// cards within a section, 16px card padding/radius — applied to every
/// grid/card on this screen so the whole page reads as one consistent grid
/// instead of ad hoc widget sizes.
const double _kSectionGap = 24;
const double _kCardGap = 12;
const double _kCardPadding = 16;
const double _kCardRadius = 16;

/// Compact row height used inside the consolidated cards introduced in
/// Sprint 6.4 ([_AttentionList]/[_ExecutiveSummaryList]) — a floor, not a
/// fixed height, for the same reason `_kStatTileMinHeight` existed pre-6.4:
/// real long names must be able to grow a row instead of overflowing it.
const double _kRowMinHeight = 40;

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
  late final DateTime _queryEnd;
  late final Stream<List<TaskModel>> _tasksStream;

  @override
  void initState() {
    super.initState();
    final repo = context.read<TaskRepository>();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day);
    _start = _end.subtract(const Duration(days: _rangeDays));
    // Query one extra day past `_end` so "Próximas 24 horas" (Sprint 6.3)
    // can see tasks scheduled for tomorrow without a second stream — the
    // historical KPIs/charts below still filter back down to `_end` so their
    // existing 30-day-window behavior (Sprint 6.2) is unchanged.
    _queryEnd = _end.add(const Duration(days: 1));
    _tasksStream = repo.watchTasksInRange(_start, _queryEnd);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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

          final allTasks = (snapshot.data ?? [])
              .where((t) => isTaskVisibleToUser(task: t, user: currentUser, catalog: catalog))
              .toList();

          if (allTasks.isEmpty) {
            return const EmptyState(
              message: 'No hay tareas registradas en los últimos 30 días.',
              icon: LucideIcons.layoutDashboard,
            );
          }

          final now = DateTime.now();
          // Sprint 6.2's historical KPIs/highlights/charts must keep seeing
          // exactly the same `_start.._end` (today) window as before — the
          // extra day fetched above for "Próximas 24 horas" is excluded here
          // so none of that existing math changes.
          final todayKey = AppDateUtils.formatDateKey(_end);
          final historicalTasks =
              allTasks.where((t) => t.date.compareTo(todayKey) <= 0).toList();

          final kpis = computeTaskKpis(historicalTasks, catalog);
          final topUser = topUserByCompleted(historicalTasks, catalog);
          final groupCompliance = computeGroupCompliance(historicalTasks, catalog)
            ..sort((a, b) => b.percent.compareTo(a.percent));
          final bestGroup = bestGroupCompliance(groupCompliance);
          final topClient = mostAttendedClient(historicalTasks);
          final streakUser = bestActiveStreak(catalog.users);
          final statusDistribution = computeStatusDistribution(historicalTasks, catalog);
          final dailyTrend =
              computeDailyTrend(historicalTasks, _start, _end, AppDateUtils.formatDateKey);

          // Sprint 6.3: operational alerts — derived from the same `allTasks`
          // list (no extra query), so "vencidas"/"próximas" can see tomorrow.
          final overdueTasks = computeOverdueTasks(allTasks, catalog, now);
          final upcomingTasks = computeUpcomingTasks(allTasks, now);
          final inactiveUsers = computeInactiveUsers(allTasks, catalog.users, catalog, now);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _HeroSummaryCard(rangeDays: _rangeDays, kpis: kpis),
              const SizedBox(height: _kSectionGap),
              _SectionTitle('⚠️ Atención requerida'),
              const SizedBox(height: _kCardGap),
              _DashboardCard(
                child: _AttentionList(items: [
                  _AttentionItem(
                    emoji: '🔴',
                    color: colors.error,
                    count: overdueTasks.length,
                    singular: 'tarea vencida',
                    plural: 'tareas vencidas',
                    onTap: () => _showOverdueTasksSheet(context, catalog, overdueTasks),
                  ),
                  _AttentionItem(
                    emoji: '🟠',
                    color: colors.statusPending,
                    count: upcomingTasks.length,
                    singular: 'tarea próxima (24h)',
                    plural: 'tareas próximas (24h)',
                    onTap: () => _showUpcomingTasksSheet(context, catalog, upcomingTasks),
                  ),
                  _AttentionItem(
                    emoji: '🔵',
                    color: colors.statusRescheduled,
                    count: inactiveUsers.length,
                    singular: 'usuario sin actividad',
                    plural: 'usuarios sin actividad',
                    onTap: () => _showInactiveUsersSheet(context, catalog, inactiveUsers),
                  ),
                ]),
              ),
              const SizedBox(height: _kSectionGap),
              _SectionTitle('🏆 Resumen ejecutivo'),
              const SizedBox(height: _kCardGap),
              _DashboardCard(
                child: _ExecutiveSummaryList(items: [
                  _ExecutiveItem(
                    label: 'Mejor colaborador',
                    value: topUser?.name ?? 'Sin datos',
                  ),
                  _ExecutiveItem(
                    label: 'Mejor grupo',
                    value: bestGroup == null
                        ? 'Sin datos'
                        : '${catalog.groupName(bestGroup.groupId)} · ${bestGroup.percent}%',
                  ),
                  _ExecutiveItem(
                    label: 'Cliente destacado',
                    value: topClient == null
                        ? 'Sin datos'
                        : '${topClient.name} · ${topClient.count}',
                  ),
                  _ExecutiveItem(
                    label: 'Mejor racha',
                    value: streakUser == null
                        ? 'Sin datos'
                        : '${streakUser.name} · ${streakUser.streakDays} días',
                  ),
                ]),
              ),
              const SizedBox(height: _kSectionGap),
              _SectionTitle('Distribución de estados'),
              const SizedBox(height: _kCardGap),
              _DashboardCard(child: _StatusDistributionChart(distribution: statusDistribution)),
              const SizedBox(height: _kSectionGap),
              _SectionTitle('Cumplimiento por grupo'),
              const SizedBox(height: _kCardGap),
              _DashboardCard(child: _GroupComplianceChart(groups: groupCompliance, catalog: catalog)),
              const SizedBox(height: _kSectionGap),
              _SectionTitle('Tendencia de tareas'),
              const SizedBox(height: _kCardGap),
              _DashboardCard(child: _TrendChart(entries: dailyTrend)),
            ],
          );
        },
      ),
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
      padding: const EdgeInsets.all(_kCardPadding),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: colors.divider),
      ),
      child: child,
    );
  }
}

/// Part 1 (Sprint 6.4): the dominant "Resumen · últimos N días" hero —
/// replaces the old 4-tile KPI grid + standalone "Cumplimiento general"
/// tile with one `colors.primary`-filled card carrying total/completadas as
/// headline numbers plus a compliance progress bar. Reads the exact same
/// [TaskKpis] already computed in `DashboardPage.build` — no new metric.
class _HeroSummaryCard extends StatelessWidget {
  const _HeroSummaryCard({required this.rangeDays, required this.kpis});

  final int rangeDays;
  final TaskKpis kpis;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(_kCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen · últimos $rangeDays días',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onPrimary.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _HeroMetric(value: '${kpis.total}', label: 'tareas')),
              Expanded(child: _HeroMetric(value: '${kpis.completed}', label: 'completadas')),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cumplimiento',
                style: TextStyle(
                  color: colors.onPrimary.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${kpis.compliancePercent}%',
                style: TextStyle(color: colors.onPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: kpis.compliancePercent / 100,
              minHeight: 10,
              backgroundColor: colors.onPrimary.withValues(alpha: 0.2),
              color: colors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onPrimary, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onPrimary.withValues(alpha: 0.85), fontSize: 12),
        ),
      ],
    );
  }
}

/// Part 2 (Sprint 6.4): one row of the consolidated "Atención requerida"
/// card. [count]/[onTap] still come straight from the same
/// `computeOverdueTasks`/`computeUpcomingTasks`/`computeInactiveUsers` lists
/// `DashboardPage.build` already had — only the 3-tile grid presentation is
/// replaced, the tap-to-detail behavior per metric is unchanged.
class _AttentionItem {
  const _AttentionItem({
    required this.emoji,
    required this.color,
    required this.count,
    required this.singular,
    required this.plural,
    required this.onTap,
  });

  final String emoji;
  final Color color;
  final int count;
  final String singular;
  final String plural;
  final VoidCallback onTap;
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.items});

  final List<_AttentionItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(height: 1, color: colors.divider),
          _AttentionRow(item: items[i]),
        ],
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final _AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: _kRowMinHeight),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(item.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${item.count} ',
                      style: TextStyle(color: item.color, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: item.count == 1 ? item.singular : item.plural,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronRight, size: 16, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Part 3 (Sprint 6.4): one label/value pair inside the consolidated
/// "Resumen ejecutivo" card — replaces the old 4-tile "Resumen visual" grid.
/// Values are unchanged (`topUser`/`bestGroup`/`topClient`/`streakUser`,
/// already computed once in `DashboardPage.build`); only the presentation is
/// now a vertical list instead of 4 separate tiles, so a long name has the
/// full card width before it needs to ellipsize.
class _ExecutiveItem {
  const _ExecutiveItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _ExecutiveSummaryList extends StatelessWidget {
  const _ExecutiveSummaryList({required this.items});

  final List<_ExecutiveItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _ExecutiveRow(item: items[i]),
        ],
      ],
    );
  }
}

class _ExecutiveRow extends StatelessWidget {
  const _ExecutiveRow({required this.item});

  final _ExecutiveItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
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
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final e in entries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: taskStatusColor(colors, e.key),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        '${e.key} (${e.value})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
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
                        catalog.groupName(g.groupId).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${g.percent}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: colors.success, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
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
          // Sprint 6.4 Part 6: trimmed from 160 — the trend chart should
          // read as a quick-glance analysis strip, not a dominant section.
          height: 130,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              // Sprint 6.4.1: this chart is a quick-glance trend strip, not
              // an analytical tool — fl_chart's default touch tooltip used a
              // hardcoded dark blue-grey box (outside the app's theme) and
              // printed raw double values (e.g. "5.0") for what's always an
              // integer task count. Disabling touch entirely removes both
              // problems instead of re-theming a tooltip nothing here needs.
              lineTouchData: const LineTouchData(enabled: false),
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

// -----------------------------------------------------------------------
// Sprint 6.3: operational alert detail sheets ("¿Qué requiere atención
// inmediata hoy?"). Each sheet renders one of the lists already computed in
// `DashboardPage.build` from the single `allTasks`/`catalog.users` source —
// no additional Firestore reads happen when a card is tapped.
// -----------------------------------------------------------------------

void _showOverdueTasksSheet(
  BuildContext context,
  CatalogProvider catalog,
  List<TaskModel> overdueTasks,
) {
  final colors = context.colors;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => _DetailSheet(
      title: 'Tareas vencidas (${overdueTasks.length})',
      itemCount: overdueTasks.length,
      emptyMessage: 'No hay tareas vencidas.',
      itemBuilder: (context, index) {
        final task = overdueTasks[index];
        return _DetailCard(
          title: task.clientName,
          color: context.colors.error,
          lines: [
            '${AppDateUtils.formatShortDate(task.scheduledDateTime)} · ${task.hour}',
            'Usuario: ${catalog.userName(task.assignedUserId)}',
            'Grupo: ${catalog.groupName(task.groupId)}',
            'Estado: ${catalog.statusName(task.statusId)}',
          ],
        );
      },
    ),
  );
}

void _showUpcomingTasksSheet(
  BuildContext context,
  CatalogProvider catalog,
  List<TaskModel> upcomingTasks,
) {
  final colors = context.colors;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => _DetailSheet(
      title: 'Próximas 24 horas (${upcomingTasks.length})',
      itemCount: upcomingTasks.length,
      emptyMessage: 'No hay tareas programadas en las próximas 24 horas.',
      itemBuilder: (context, index) {
        final task = upcomingTasks[index];
        return _DetailCard(
          title: task.clientName,
          color: context.colors.statusPending,
          lines: [
            '${AppDateUtils.formatShortDate(task.scheduledDateTime)} · ${task.hour}',
            'Usuario: ${catalog.userName(task.assignedUserId)}',
            'Grupo: ${catalog.groupName(task.groupId)}',
            'Tipo: ${catalog.taskTypeName(task.taskTypeId)}',
          ],
        );
      },
    ),
  );
}

void _showInactiveUsersSheet(
  BuildContext context,
  CatalogProvider catalog,
  List<InactiveUserStat> inactiveUsers,
) {
  final colors = context.colors;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => _DetailSheet(
      title: 'Usuarios sin actividad (${inactiveUsers.length})',
      itemCount: inactiveUsers.length,
      emptyMessage: 'Todos los usuarios completaron tareas en los últimos 7 días.',
      itemBuilder: (context, index) {
        final stat = inactiveUsers[index];
        return _DetailCard(
          title: stat.user.name,
          color: context.colors.statusRescheduled,
          lines: [
            'Grupo: ${catalog.groupName(stat.user.groupId)}',
            'Completadas (7 días): ${stat.completedLast7Days}',
            'Último acceso: ${AppDateUtils.formatDateTimeOrDash(stat.user.lastLogin)}',
          ],
        );
      },
    ),
  );
}

/// Shared bottom-sheet shell for the 3 operational alert cards above —
/// a title, then either an empty-state message or a scrollable list, so
/// "0 resultados" (Sprint 6.3 validation cases 2/4) renders cleanly instead
/// of an empty void.
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    required this.title,
    required this.itemCount,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  final String title;
  final int itemCount;
  final String emptyMessage;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: itemCount == 0
                    ? Center(
                        child: Text(
                          emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: itemCount,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: itemBuilder,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row inside a [_DetailSheet]: a bold title plus a handful of muted
/// label lines, in the same bordered-container style already used by
/// [_DashboardStatTile]/[_DashboardCard] so the sheets match the Dashboard look.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.color, required this.lines});

  final String title;
  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
