import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/report_filters.dart';
import '../../core/utils/report_metrics.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/task_visibility.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import 'report_excel.dart';
import 'report_exports.dart';
import 'widgets/groups_report_tab.dart';
import 'widgets/performance_report_tab.dart';
import 'widgets/report_filter_bar.dart';
import 'widgets/status_report_tab.dart';
import 'widgets/streak_report_tab.dart';
import 'widgets/tasks_report_tab.dart';
import 'widgets/top_clients_report_tab.dart';

/// The period button, sized by whoever lays it out.
class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({required this.range, required this.onTap});

  final DateTimeRange range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendarRange, color: colors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${AppDateUtils.formatShortDate(range.start)} - '
                '${AppDateUtils.formatShortDate(range.end)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronDown,
              color: colors.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin-only "Reportes" tab: 6 reports over a configurable date range.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late DateTimeRange _range;

  /// Applies to every tab and to the exports, not just the Tareas table: a
  /// report is almost always about a slice — one team, the cancelled ones —
  /// and having the summary above describe everything while the table below
  /// describes a subset is the kind of mismatch people quote in meetings.
  ReportFilters _filters = const ReportFilters();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 30)),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Runs an export and always says what happened.
  ///
  /// Both buttons used to be bare `() => export(...)` calls: the Future went
  /// unawaited and nothing caught anything, so a failure anywhere in it — and
  /// the Excel path builds a zip and rewrites XML inside it — reached the user
  /// as a button that did nothing at all. No file, no error, nothing to
  /// report. That is how the Windows download bug stayed a mystery instead of
  /// being a one-line answer.
  Future<void> _runExport(String what, Future<void> Function() export) async {
    try {
      await export();
      if (!mounted) return;
      SnackbarUtils.showSuccess(context, '$what descargado');
    } catch (e) {
      if (!mounted) return;
      SnackbarUtils.showError(
        context,
        'No se pudo generar el $what. ${SnackbarUtils.firebaseErrorMessage(e)}',
      );
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final repo = context.read<TaskRepository>();
    final catalog = context.watch<CatalogProvider>();
    final currentUser = context.watch<AuthProvider>().appUser;

    if (currentUser == null) {
      return const Scaffold(body: LoadingIndicator());
    }

    // Single shared listener for the selected range — every tab below reads
    // from this same task list instead of opening its own stream, so
    // switching tabs/date range never issues duplicate Firestore queries.
    //
    // Sprint 7.4.3 Parte 3 — measurement only. Local to this build() call,
    // so it times the load triggered by each `_pickRange()` selection.
    final loadStopwatch = Stopwatch()..start();
    var loadLogged = false;

    return Scaffold(
      body: StreamBuilder<List<TaskModel>>(
        stream: repo.watchTasksInRange(_range.start, _range.end),
        builder: (context, snapshot) {
          if (!loadLogged &&
              snapshot.connectionState != ConnectionState.waiting) {
            loadLogged = true;
            debugPrint(
              '[PERF] Reportes load: ${loadStopwatch.elapsedMilliseconds}ms',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingIndicator();
          }
          if (snapshot.hasError) {
            return EmptyState(
              message: 'No se pudieron cargar las tareas.\n${snapshot.error}',
              icon: LucideIcons.alertCircle,
            );
          }

          // Two lists on purpose: `visible` feeds the filter bar its options
          // and the "de 44" denominator, `tasks` is what everything else uses.
          final visible = (snapshot.data ?? [])
              .where((t) => isTaskVisibleToUser(task: t, user: currentUser))
              .toList();
          final tasks = _filters.apply(visible);

          final ordenadas = sortedForReport(tasks);

          return Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ReportFilterBar(
                  filters: _filters,
                  onChanged: (f) => setState(() => _filters = f),
                  tasks: visible,
                  catalog: catalog,
                  matchCount: tasks.length,
                  dateSelector: _DateRangeButton(
                    range: _range,
                    onTap: _pickRange,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: KpiSummaryRow(
                        kpis: computeTaskKpis(tasks, catalog),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Moved up out of the Tareas tab: it exports the filtered
                    // list the whole screen is showing, which has nothing to do
                    // with which tab happens to be open.
                    FilledButton.icon(
                      onPressed: ordenadas.isEmpty
                          ? null
                          : () => _runExport(
                              'Excel',
                              () => exportReportExcel(
                                tasks: ordenadas,
                                catalog: catalog,
                                start: _range.start,
                                end: _range.end,
                                generatedBy: currentUser.name,
                                activeFilters: _filters.describe(
                                  groupName: catalog.groupName,
                                  userName: catalog.userName,
                                  statusName: catalog.statusName,
                                  taskTypeName: catalog.taskTypeName,
                                ),
                              ),
                            ),
                      icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
                      label: const Text('Excel'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: ordenadas.isEmpty
                          ? null
                          : () => _runExport(
                              'CSV',
                              () => exportTasksCsv(
                                tasks: ordenadas,
                                catalog: catalog,
                                start: _range.start,
                                end: _range.end,
                              ),
                            ),
                      icon: const Icon(LucideIcons.download, size: 16),
                      label: const Text('CSV'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: colors.primary,
                unselectedLabelColor: colors.textSecondary,
                indicatorColor: colors.primary,
                tabs: const [
                  Tab(text: 'Tareas'),
                  Tab(text: 'Estados'),
                  Tab(text: 'Usuarios'),
                  Tab(text: 'Equipos'),
                  Tab(text: 'Racha'),
                  Tab(text: 'Clientes'),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    TasksReportTab(tasks: ordenadas),
                    StatusReportTab(tasks: tasks),
                    PerformanceReportTab(tasks: tasks),
                    GroupsReportTab(tasks: tasks),
                    const StreakReportTab(),
                    TopClientsReportTab(tasks: tasks),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
