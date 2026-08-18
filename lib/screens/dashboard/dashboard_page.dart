import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/report_metrics.dart';
import '../../core/utils/task_visibility.dart';
import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_sheet.dart';
import '../home/widgets/compact_task_card.dart' show taskStatusColor;

/// Spacing system (Sprint 6.3.1): preserved unchanged for mobile.
const double _kSectionGap = 24;
const double _kCardGap = 12;
const double _kCardPadding = 16;
const double _kCardRadius = AppSpacing.radiusLg;

/// Elements nested *inside* a card sit one step below `_kCardRadius`, so the
/// nesting reads correctly instead of looking like two cards stacked.
const double _kInnerRadius = AppSpacing.radiusMd;

/// Compact row height used inside consolidated mobile cards.
const double _kRowMinHeight = 40;

/// Ranges offered by the header selector.
///
/// These used to be labels and nothing more: picking one changed the text and
/// left every number on screen exactly as it was, because the query was
/// hard-wired to 30 days. That is worse than a disabled control — the screen
/// claimed to show the year while showing the month, and there was no way to
/// tell from looking. They now drive the query (see [_rangeFor]).
const _kRangeLabels = [
  'Últimos 7 días',
  'Últimos 30 días',
  'Este mes',
  'Este año',
  'Personalizado',
];
const _kDefaultRangeIndex = 1; // "Últimos 30 días"
const _kCustomRangeIndex = 4;

/// Computed metrics bundle shared across the three layout builders so each
/// receives a typed snapshot instead of a long parameter list.
class _Snapshot {
  const _Snapshot({
    required this.kpis,
    required this.topUser,
    required this.groupCompliance,
    required this.bestGroup,
    required this.topClient,
    required this.streakUser,
    required this.statusDistribution,
    required this.dailyTrend,
    required this.overdueTasks,
    required this.upcomingTasks,
    required this.inactiveUsers,
    required this.catalog,
  });

  final TaskKpis kpis;
  final AppUser? topUser;
  final List<GroupCompliance> groupCompliance;
  final GroupCompliance? bestGroup;
  final ({String name, String phone, int count})? topClient;
  final AppUser? streakUser;
  final Map<String, int> statusDistribution;
  final List<MapEntry<String, int>> dailyTrend;
  final List<TaskModel> overdueTasks;
  final List<TaskModel> upcomingTasks;
  final List<InactiveUserStat> inactiveUsers;
  final CatalogProvider catalog;
}

/// Admin-only executive dashboard — Sprint 6.2.
///
/// Sprint 14 adds responsive layout branching:
///   Mobile    (<600 px)   — identical ListView, no change.
///   Tablet    (600–1023)  — 2-col KPI grid + 2-col charts.
///   Desktop   (≥1024 px)  — header + 4-row grid, fits 1920×1080.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late DateTime _start;
  late DateTime _end;
  late DateTime _queryEnd;
  late Stream<List<TaskModel>> _tasksStream;
  late Stopwatch _loadStopwatch;
  bool _loadLogged = false;

  int _rangeIndex = _kDefaultRangeIndex;

  @override
  void initState() {
    super.initState();
    _applyRange(_kDefaultRangeIndex);
  }

  /// First and last day covered by [index], both inclusive.
  static ({DateTime start, DateTime end}) _rangeFor(int index, DateTime today) {
    switch (index) {
      case 0:
        return (start: today.subtract(const Duration(days: 7)), end: today);
      case 2:
        return (start: DateTime(today.year, today.month, 1), end: today);
      case 3:
        return (start: DateTime(today.year, 1, 1), end: today);
      default:
        return (start: today.subtract(const Duration(days: 30)), end: today);
    }
  }

  /// Points the screen at a new period and re-opens the query behind it.
  ///
  /// Everything downstream already reads [_start]/[_end] — the KPIs, the
  /// trend, the charts — so re-running the stream is the whole change.
  void _applyRange(int index, {DateTimeRange? custom}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (custom != null) {
      _start = DateTime(custom.start.year, custom.start.month, custom.start.day);
      _end = DateTime(custom.end.year, custom.end.month, custom.end.day);
    } else {
      final range = _rangeFor(index, today);
      _start = range.start;
      _end = range.end;
    }

    _rangeIndex = index;
    // One extra day so "Próximas 24 horas" sees tomorrow without a second
    // stream. On a custom range that ends in the past there is nothing ahead
    // to show, which is the honest answer for a window that already closed.
    _queryEnd = _end.add(const Duration(days: 1));
    _loadLogged = false;
    _loadStopwatch = Stopwatch()..start();
    _tasksStream = context.read<TaskRepository>().watchTasksInRange(_start, _queryEnd);
  }

  Future<void> _onRangeChanged(int index) async {
    if (index == _kCustomRangeIndex) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: DateTimeRange(start: _start, end: _end),
        helpText: 'Elige el periodo',
        saveText: 'Aplicar',
      );
      if (picked == null || !mounted) return;
      setState(() => _applyRange(_kCustomRangeIndex, custom: picked));
      return;
    }
    setState(() => _applyRange(index));
  }

  /// What the header and the empty state call the current period.
  String get _rangeLabel => _rangeIndex == _kCustomRangeIndex
      ? '${AppDateUtils.formatShortDate(_start)} — ${AppDateUtils.formatShortDate(_end)}'
      : _kRangeLabels[_rangeIndex];

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
          if (!_loadLogged && snapshot.connectionState != ConnectionState.waiting) {
            _loadLogged = true;
            debugPrint('[PERF] Dashboard load: ${_loadStopwatch.elapsedMilliseconds}ms');
          }
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
              .where((t) => isTaskVisibleToUser(task: t, user: currentUser))
              .toList();

          if (allTasks.isEmpty) {
            return EmptyState(
              message: 'No hay tareas registradas en el periodo: '
                  '${_rangeLabel.toLowerCase()}.',
              icon: LucideIcons.layoutDashboard,
            );
          }

          final now = DateTime.now();
          // Historical KPIs/charts only see up to _end (today); the extra day
          // fetched above is for "Próximas 24 horas" only.
          final todayKey = AppDateUtils.formatDateKey(_end);
          final historicalTasks =
              allTasks.where((t) => t.date.compareTo(todayKey) <= 0).toList();

          final kpis = computeTaskKpis(historicalTasks, catalog);
          final topUser = topUserByCompleted(historicalTasks, catalog);
          final groupCompliance = computeGroupCompliance(historicalTasks, catalog)
            ..sort((a, b) => b.percent.compareTo(a.percent));
          final bestGroup = bestGroupCompliance(groupCompliance);
          final topClient = mostAttendedClient(historicalTasks, catalog);
          final streakUser = bestActiveStreak(catalog.users);
          final statusDistribution = computeStatusDistribution(historicalTasks, catalog);
          final dailyTrend =
              computeDailyTrend(historicalTasks, _start, _end, AppDateUtils.formatDateKey);

          final overdueTasks = computeOverdueTasks(allTasks, catalog, now);
          final upcomingTasks = computeUpcomingTasks(allTasks, now);
          final inactiveUsers = computeInactiveUsers(allTasks, catalog.users, catalog, now);

          final snap = _Snapshot(
            kpis: kpis,
            topUser: topUser,
            groupCompliance: groupCompliance,
            bestGroup: bestGroup,
            topClient: topClient,
            streakUser: streakUser,
            statusDistribution: statusDistribution,
            dailyTrend: dailyTrend,
            overdueTasks: overdueTasks,
            upcomingTasks: upcomingTasks,
            inactiveUsers: inactiveUsers,
            catalog: catalog,
          );

          if (context.isDesktop) return _buildDesktopBody(context, snap, currentUser);
          if (context.isTablet) return _buildTabletBody(context, snap);
          return _buildMobileBody(context, snap);
        },
      ),
    );
  }

  // ── Mobile (<600 px) ───────────────────────────────────────────────────────
  // Identical to the pre-Sprint-14 ListView; no line changed.
  Widget _buildMobileBody(BuildContext context, _Snapshot s) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeroSummaryCard(rangeLabel: _rangeLabel, kpis: s.kpis),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('⚠️ Atención requerida'),
        const SizedBox(height: _kCardGap),
        _DashboardCard(
          child: _AttentionList(items: [
            _AttentionItem(
              emoji: '🔴',
              color: colors.error,
              count: s.overdueTasks.length,
              singular: 'tarea vencida',
              plural: 'tareas vencidas',
              onTap: () => _showOverdueTasksSheet(context, s.catalog, s.overdueTasks),
            ),
            _AttentionItem(
              emoji: '🟠',
              color: colors.statusPending,
              count: s.upcomingTasks.length,
              singular: 'tarea próxima (24h)',
              plural: 'tareas próximas (24h)',
              onTap: () => _showUpcomingTasksSheet(context, s.catalog, s.upcomingTasks),
            ),
            _AttentionItem(
              emoji: '🔵',
              color: colors.statusRescheduled,
              count: s.inactiveUsers.length,
              singular: 'usuario sin actividad',
              plural: 'usuarios sin actividad',
              onTap: () => _showInactiveUsersSheet(context, s.catalog, s.inactiveUsers),
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
              value: s.topUser?.name ?? 'Sin datos',
            ),
            _ExecutiveItem(
              label: 'Mejor equipo',
              value: s.bestGroup == null
                  ? 'Sin datos'
                  : '${s.catalog.groupName(s.bestGroup!.groupId)} · ${s.bestGroup!.percent}%',
            ),
            _ExecutiveItem(
              label: 'Cliente destacado',
              value: s.topClient == null
                  ? 'Sin datos'
                  : '${s.topClient!.name} · ${s.topClient!.count}',
            ),
            _ExecutiveItem(
              label: 'Mejor racha',
              value: s.streakUser == null
                  ? 'Sin datos'
                  : '${s.streakUser!.name} · ${s.streakUser!.streakDays} días',
            ),
          ]),
        ),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('Distribución de estados'),
        const SizedBox(height: _kCardGap),
        _DashboardCard(child: _StatusDistributionChart(distribution: s.statusDistribution)),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('Cumplimiento por equipo'),
        const SizedBox(height: _kCardGap),
        _DashboardCard(child: _GroupComplianceChart(groups: s.groupCompliance, catalog: s.catalog)),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('Tendencia de tareas'),
        const SizedBox(height: _kCardGap),
        _DashboardCard(child: _TrendChart(entries: s.dailyTrend)),
      ],
    );
  }

  // ── Tablet (600–1023 px) ───────────────────────────────────────────────────
  // Same navigation as mobile (Sprint 13 MainShell); content centered at
  // AppLayout.contentMaxWidthWide by the shell's ConstrainedBox — unchanged.
  // Layout changes: 2-col KPI grid, standalone compliance card, 2-col charts.
  Widget _buildTabletBody(BuildContext context, _Snapshot s) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePaddingTablet,
        AppSpacing.md,
        AppSpacing.pagePaddingTablet,
        AppSpacing.xxl,
      ),
      children: [
        // 2×2 KPI grid (replaces _HeroSummaryCard on tablet)
        _TwoColRow(
          left: _KpiCard(
            icon: LucideIcons.clipboardList,
            title: 'Total tareas',
            count: s.kpis.total,
            linkLabel: 'Ver tareas →',
          ),
          right: _KpiCard(
            icon: LucideIcons.checkCircle2,
            title: 'Completadas',
            count: s.kpis.completed,
            accentColor: colors.success,
            linkLabel: 'Ver completadas →',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _TwoColRow(
          left: _KpiCard(
            icon: LucideIcons.clock,
            title: 'Pendientes',
            count: s.kpis.pending,
            accentColor: colors.statusPending,
            linkLabel: 'Ver pendientes →',
          ),
          right: _KpiCard(
            icon: LucideIcons.calendarDays,
            title: 'Reprogramadas',
            count: s.kpis.rescheduled,
            accentColor: colors.statusRescheduled,
            linkLabel: 'Ver reprogramadas →',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ComplianceCard(kpis: s.kpis),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('⚠️ Atención requerida'),
        const SizedBox(height: _kCardGap),
        _DashboardCard(
          showShadow: true,
          child: _AttentionList(items: [
            _AttentionItem(
              emoji: '🔴',
              color: colors.error,
              count: s.overdueTasks.length,
              singular: 'tarea vencida',
              plural: 'tareas vencidas',
              onTap: () => _showOverdueTasksSheet(context, s.catalog, s.overdueTasks),
            ),
            _AttentionItem(
              emoji: '🟠',
              color: colors.statusPending,
              count: s.upcomingTasks.length,
              singular: 'tarea próxima (24h)',
              plural: 'tareas próximas (24h)',
              onTap: () => _showUpcomingTasksSheet(context, s.catalog, s.upcomingTasks),
            ),
            _AttentionItem(
              emoji: '🔵',
              color: colors.statusRescheduled,
              count: s.inactiveUsers.length,
              singular: 'usuario sin actividad',
              plural: 'usuarios sin actividad',
              onTap: () => _showInactiveUsersSheet(context, s.catalog, s.inactiveUsers),
            ),
          ]),
        ),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('🏆 Resumen ejecutivo'),
        const SizedBox(height: _kCardGap),
        _DashboardCard(
          showShadow: true,
          child: _ExecutiveSummaryList(items: [
            _ExecutiveItem(
              label: 'Mejor colaborador',
              value: s.topUser?.name ?? 'Sin datos',
            ),
            _ExecutiveItem(
              label: 'Mejor equipo',
              value: s.bestGroup == null
                  ? 'Sin datos'
                  : '${s.catalog.groupName(s.bestGroup!.groupId)} · ${s.bestGroup!.percent}%',
            ),
            _ExecutiveItem(
              label: 'Cliente destacado',
              value: s.topClient == null
                  ? 'Sin datos'
                  : '${s.topClient!.name} · ${s.topClient!.count}',
            ),
            _ExecutiveItem(
              label: 'Mejor racha',
              value: s.streakUser == null
                  ? 'Sin datos'
                  : '${s.streakUser!.name} · ${s.streakUser!.streakDays} días',
            ),
          ]),
        ),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('Distribución de estados  ·  Cumplimiento por equipo'),
        const SizedBox(height: _kCardGap),
        // 2 charts side by side
        _TwoColRow(
          left: _DashboardCard(
            showShadow: true,
            child: _StatusDistributionChart(distribution: s.statusDistribution),
          ),
          right: _DashboardCard(
            showShadow: true,
            child: _GroupComplianceChart(groups: s.groupCompliance, catalog: s.catalog),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _SectionTitle('Tendencia de tareas'),
        const SizedBox(height: _kCardGap),
        _DashboardCard(showShadow: true, child: _TrendChart(entries: s.dailyTrend)),
      ],
    );
  }

  // ── Desktop (≥1024 px) ────────────────────────────────────────────────────
  // Full grid redesign: header + 4 content rows visible at 1920×1080.
  Widget _buildDesktopBody(BuildContext context, _Snapshot s, AppUser user) {
    final colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePaddingDesktop,
        AppSpacing.md,
        AppSpacing.pagePaddingDesktop,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: title + greeting + range selector ──────────────────
          _DesktopHeader(
            user: user,
            rangeIndex: _rangeIndex,
            onRangeChanged: _onRangeChanged,
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Row 1: KPI group card (Total/Completadas/Pendientes, ~67%)
          // + Cumplimiento general filling the row's full height (~33%) ──
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _DashboardCard(
                    showShadow: true,
                    child: Row(
                      children: [
                        Expanded(
                          child: _KpiSubBlock(
                            icon: LucideIcons.clipboardList,
                            title: 'Total tareas',
                            count: s.kpis.total,
                            linkLabel: 'Ver tareas →',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 56,
                          color: colors.divider,
                        ),
                        Expanded(
                          child: _KpiSubBlock(
                            icon: LucideIcons.checkCircle2,
                            title: 'Completadas',
                            count: s.kpis.completed,
                            accentColor: colors.success,
                            linkLabel: 'Ver completadas →',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 56,
                          color: colors.divider,
                        ),
                        Expanded(
                          child: _KpiSubBlock(
                            icon: LucideIcons.clock,
                            title: 'Pendientes',
                            count: s.kpis.pending,
                            accentColor: colors.statusPending,
                            linkLabel: 'Ver pendientes →',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 1,
                  child: _ComplianceCard(kpis: s.kpis),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Row 2: Atención requerida (flex 2) + resumen ejecutivo en
          // grilla 2×2 (flex 1) — antes una fila horizontal aparte, ahora
          // compactada acá para ganar una fila entera de alto ──────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _DashboardCard(
                    showShadow: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle('⚠️ Atención requerida', fontSize: 16),
                        const SizedBox(height: AppSpacing.sm),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: _AttentionCompactCard(
                                  item: _AttentionItem(
                                    emoji: '🔴',
                                    color: colors.error,
                                    count: s.overdueTasks.length,
                                    singular: 'Tarea vencida',
                                    plural: 'Tareas vencidas',
                                    onTap: () => _showOverdueTasksSheet(
                                        context, s.catalog, s.overdueTasks),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _AttentionCompactCard(
                                  item: _AttentionItem(
                                    emoji: '🟠',
                                    color: colors.statusPending,
                                    count: s.upcomingTasks.length,
                                    singular: 'Próxima 24h',
                                    plural: 'Próximas 24h',
                                    onTap: () => _showUpcomingTasksSheet(
                                        context, s.catalog, s.upcomingTasks),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _AttentionCompactCard(
                                  item: _AttentionItem(
                                    emoji: '🔵',
                                    color: colors.statusRescheduled,
                                    count: s.inactiveUsers.length,
                                    singular: 'Usuario inactivo',
                                    plural: 'Usuarios inactivos',
                                    onTap: () => _showInactiveUsersSheet(
                                        context, s.catalog, s.inactiveUsers),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _DashboardCard(
                                showShadow: true,
                                padding: AppSpacing.sm,
                                child: _ExecutiveHorizontalItem(
                                  icon: LucideIcons.trophy,
                                  label: 'Mejor colaborador',
                                  value: s.topUser?.name ?? 'Sin datos todavía',
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _DashboardCard(
                                showShadow: true,
                                padding: AppSpacing.sm,
                                child: _ExecutiveHorizontalItem(
                                  icon: LucideIcons.users,
                                  label: 'Mejor equipo',
                                  value: s.bestGroup == null
                                      ? 'Sin datos todavía'
                                      : '${s.catalog.groupName(s.bestGroup!.groupId)} · ${s.bestGroup!.percent}%',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _DashboardCard(
                                showShadow: true,
                                padding: AppSpacing.sm,
                                child: _ExecutiveHorizontalItem(
                                  icon: LucideIcons.star,
                                  label: 'Cliente destacado',
                                  value: s.topClient == null
                                      ? 'Sin datos todavía'
                                      : '${s.topClient!.name} · ${s.topClient!.count}',
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _DashboardCard(
                                showShadow: true,
                                padding: AppSpacing.sm,
                                child: _ExecutiveHorizontalItem(
                                  icon: LucideIcons.flame,
                                  label: 'Mejor racha',
                                  value: s.streakUser == null
                                      ? 'Sin datos todavía'
                                      : '${s.streakUser!.name} · ${s.streakUser!.streakDays} días',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Row 3: distribución + cumplimiento por equipo + tendencia ────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _DashboardCard(
                    showShadow: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle('Distribución de estados', fontSize: 16),
                        const SizedBox(height: AppSpacing.md),
                        _StatusDistributionChart(distribution: s.statusDistribution),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _DashboardCard(
                    showShadow: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle('Cumplimiento por equipo', fontSize: 16),
                        const SizedBox(height: AppSpacing.md),
                        _GroupComplianceChart(
                            groups: s.groupCompliance, catalog: s.catalog),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _DashboardCard(
                    showShadow: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle('Tendencia', fontSize: 16),
                        const SizedBox(height: AppSpacing.md),
                        _TrendChart(entries: s.dailyTrend),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sprint 14: desktop header ──────────────────────────────────────────────────

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.user,
    required this.rangeIndex,
    required this.onRangeChanged,
  });

  final AppUser user;
  final int rangeIndex;
  final ValueChanged<int> onRangeChanged;

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${_greeting()}, ${user.name}',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Aquí tienes un resumen de la actividad del equipo.',
                style: TextStyle(color: colors.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
        // Range selector — drives the query (see _DashboardPageState._applyRange)
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(_kCardRadius),
            border: Border.all(color: colors.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: rangeIndex,
              onChanged: (i) => onRangeChanged(i!),
              isDense: true,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              dropdownColor: colors.surface,
              items: [
                for (var i = 0; i < _kRangeLabels.length; i++)
                  DropdownMenuItem(value: i, child: Text(_kRangeLabels[i])),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Sprint 14: shared layout helpers ──────────────────────────────────────────

/// Two equal-width columns with [AppSpacing.sm] gap, stretched to the same
/// height via [IntrinsicHeight] — used for tablet's 2-col KPI grid and charts.
class _TwoColRow extends StatelessWidget {
  const _TwoColRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// KPI summary card (tablet 2×2 grid and desktop 4-in-a-row).
/// No solid accent background; accent color applied only to icon circle and link.
/// Hover elevates the card and highlights the border on desktop/tablet.
class _KpiCard extends StatefulWidget {
  const _KpiCard({
    required this.icon,
    required this.title,
    required this.count,
    this.accentColor,
    this.linkLabel,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color? accentColor;
  final String? linkLabel;

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = widget.accentColor ?? colors.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(_kCardPadding),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(
            color: _hovered ? accent.withValues(alpha: 0.45) : colors.divider,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.18 : 0.10),
              blurRadius: _hovered ? 14 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: Icon(widget.icon, color: accent, size: 18),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.title,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.count}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 38,
                fontWeight: FontWeight.bold,
                height: 1.05,
              ),
            ),
            if (widget.linkLabel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.linkLabel!,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single metric (icon/title/count/link), without its own card shell —
/// three of these sit side by side inside one shared `_DashboardCard` in
/// desktop Row 1's left column (Total tareas / Completadas / Pendientes),
/// separated by thin dividers, instead of each being its own full card.
class _KpiSubBlock extends StatelessWidget {
  const _KpiSubBlock({
    required this.icon,
    required this.title,
    required this.count,
    this.accentColor,
    this.linkLabel,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color? accentColor;
  final String? linkLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = accentColor ?? colors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppSpacing.xs),
          ),
          child: Icon(icon, color: accent, size: 16),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.bold,
            height: 1.05,
          ),
        ),
        if (linkLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            linkLabel!,
            textAlign: TextAlign.center,
            style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

/// Standalone compliance card: percentage headline + labelled progress bar.
/// Shown on tablet (below KPI grid) and desktop Row 2 right slot.
class _ComplianceCard extends StatelessWidget {
  const _ComplianceCard({required this.kpis});

  final TaskKpis kpis;

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cumplimiento general',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${kpis.compliancePercent}%',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 42,
              fontWeight: FontWeight.bold,
              height: 1.05,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            child: LinearProgressIndicator(
              value: kpis.compliancePercent / 100,
              minHeight: 10,
              backgroundColor: colors.divider,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Objetivo',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
              Text(
                '100%',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact attention card for the desktop 3-card row (replaces the list rows).
/// Tapping still opens the same detail sheet as on mobile.
/// Hover animates the border and background for interactive feedback.
class _AttentionCompactCard extends StatefulWidget {
  const _AttentionCompactCard({required this.item});

  final _AttentionItem item;

  @override
  State<_AttentionCompactCard> createState() => _AttentionCompactCardState();
}

class _AttentionCompactCardState extends State<_AttentionCompactCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: widget.item.color.withValues(alpha: _hovered ? 0.09 : 0.06),
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(
            color: widget.item.color.withValues(alpha: _hovered ? 0.40 : 0.25),
          ),
        ),
        child: InkWell(
          onTap: widget.item.onTap,
          borderRadius: BorderRadius.circular(_kCardRadius),
          child: Padding(
            padding: const EdgeInsets.all(_kCardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(widget.item.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${widget.item.count}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.item.color,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.item.count == 1 ? widget.item.singular : widget.item.plural,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop Row 4 executive summary item — icon badge + label + value.
/// Displays up to 2 lines so the "no data" message always fits.
class _ExecutiveHorizontalItem extends StatelessWidget {
  const _ExecutiveHorizontalItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppSpacing.xs),
          ),
          child: Icon(icon, color: colors.primary, size: 16),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Existing widgets — unchanged from Sprint 6 ─────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.fontSize = 14});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      text,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Standard card shell reused across every chart section.
/// [showShadow] adds a subtle elevation shadow — enabled on desktop/tablet,
/// omitted on mobile to preserve the unchanged mobile experience.
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.child,
    this.showShadow = false,
    this.padding = _kCardPadding,
  });

  final Widget child;
  final bool showShadow;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: colors.divider),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Mobile hero card (Sprint 6.4 Part 1). Desktop/tablet use _KpiCard rows instead.
class _HeroSummaryCard extends StatelessWidget {
  const _HeroSummaryCard({required this.rangeLabel, required this.kpis});

  final String rangeLabel;
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
            'Resumen · $rangeLabel',
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
                style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
          style: TextStyle(
            color: colors.onPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
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
      borderRadius: BorderRadius.circular(_kInnerRadius),
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
                      style: TextStyle(
                        color: item.color,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
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
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Part 6.1: pie chart for "Distribución de estados".
class _StatusDistributionChart extends StatelessWidget {
  const _StatusDistributionChart({required this.distribution});

  final Map<String, int> distribution;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = distribution.entries.toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    if (total == 0) {
      return Text(
        'Sin datos suficientes.',
        style: TextStyle(color: colors.textSecondary, fontSize: 13),
      );
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

/// Part 6.2: horizontal-bar ranking for "Cumplimiento por equipo".
class _GroupComplianceChart extends StatelessWidget {
  const _GroupComplianceChart({required this.groups, required this.catalog});

  final List<GroupCompliance> groups;
  final CatalogProvider catalog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (groups.isEmpty) {
      return Text(
        'Sin datos suficientes.',
        style: TextStyle(color: colors.textSecondary, fontSize: 13),
      );
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
                        style: TextStyle(
                          color: colors.success,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
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

/// Part 6.3: daily task count line chart for "Tendencia de tareas".
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.entries});

  final List<MapEntry<String, int>> entries;

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
      return Text(
        'Sin datos suficientes.',
        style: TextStyle(color: colors.textSecondary, fontSize: 13),
      );
    }

    final spots = [
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].value.toDouble()),
    ];
    final maxCount =
        entries.map((e) => e.value).fold<int>(0, (m, v) => v > m ? v : m);

    final yInterval = _niceYInterval(maxCount);
    final topTick =
        maxCount == 0 ? yInterval : (maxCount / yInterval).ceil() * yInterval;
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
          height: 150,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              lineTouchData: const LineTouchData(enabled: false),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                // Date labels along the bottom — previously off entirely, so
                // the only way to know which day a point/spike belonged to
                // was to count pixels against the "Del X al Y" caption above.
                // ~4-5 evenly-spaced labels regardless of the range length
                // (30 daily labels would overlap on a narrow chart).
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: entries.length > 1 ? (entries.length / 4).ceilToDouble() : 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= entries.length) {
                        return const SizedBox.shrink();
                      }
                      final date = AppDateUtils.parseDateKey(entries[index].key);
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          AppDateUtils.formatDayMonth(date),
                          style: TextStyle(color: colors.textSecondary, fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: yInterval,
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        value.toInt().toString(),
                        style:
                            TextStyle(color: colors.textSecondary, fontSize: 11),
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
                  belowBarData: BarAreaData(
                    show: true,
                    color: colors.primary.withValues(alpha: 0.15),
                  ),
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
// Sprint 6.3: operational alert detail sheets — unchanged.
// -----------------------------------------------------------------------

void _showOverdueTasksSheet(
  BuildContext context,
  CatalogProvider catalog,
  List<TaskModel> overdueTasks,
) {
  showResponsiveSheet(
    context,
    desktopMaxWidth: 480,
    scrollable: false,
    contentBuilder: (sheetContext) => _DetailSheet(
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
            'Equipo: ${catalog.groupName(task.groupId)}',
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
  showResponsiveSheet(
    context,
    desktopMaxWidth: 480,
    scrollable: false,
    contentBuilder: (sheetContext) => _DetailSheet(
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
            'Equipo: ${catalog.groupName(task.groupId)}',
            'Tipo: ${catalog.taskTypeName(task.taskTypeId)}',
          ],
        );
      },
    ),
  );
}

/// Reads the idle time as a phrase instead of a bare number, so the row says
/// something a person can act on at a glance.
String _textoInactividad(int? dias) {
  if (dias == null) return 'nunca completó una tarea';
  if (dias == 0) return 'hoy completó una';
  if (dias == 1) return 'hace 1 día';
  return 'hace $dias días';
}

void _showInactiveUsersSheet(
  BuildContext context,
  CatalogProvider catalog,
  List<InactiveUserStat> inactiveUsers,
) {
  showResponsiveSheet(
    context,
    desktopMaxWidth: 480,
    scrollable: false,
    contentBuilder: (sheetContext) => _DetailSheet(
      title: 'Usuarios sin actividad (${inactiveUsers.length})',
      itemCount: inactiveUsers.length,
      emptyMessage: 'Todos los usuarios completaron tareas en los últimos 7 días.',
      itemBuilder: (context, index) {
        final stat = inactiveUsers[index];
        return _DetailCard(
          title: stat.user.name,
          color: context.colors.statusRescheduled,
          lines: [
            'Equipo: ${catalog.groupNames(stat.user.groupIds)}',
            'Sin completar tareas: ${_textoInactividad(stat.daysSinceLastCompleted)}',
            'Último acceso: ${AppDateUtils.formatDateTimeOrDash(stat.user.lastLogin)}',
          ],
        );
      },
    ),
  );
}

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
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
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
        borderRadius: BorderRadius.circular(_kInnerRadius),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
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
