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
import 'widgets/groups_report_tab.dart';
import 'widgets/performance_report_tab.dart';
import 'widgets/status_report_tab.dart';
import 'widgets/streak_report_tab.dart';
import 'widgets/tasks_report_tab.dart';
import 'widgets/top_clients_report_tab.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 30)),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          if (!loadLogged && snapshot.connectionState != ConnectionState.waiting) {
            loadLogged = true;
            debugPrint('[PERF] Reportes load: ${loadStopwatch.elapsedMilliseconds}ms');
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

          final tasks = (snapshot.data ?? [])
              .where((t) => isTaskVisibleToUser(
                    task: t,
                    user: currentUser,
                    catalog: catalog,
                  ))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: InkWell(
                  onTap: _pickRange,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.calendarRange, color: colors.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${AppDateUtils.formatShortDate(_range.start)} - '
                            '${AppDateUtils.formatShortDate(_range.end)}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(LucideIcons.chevronDown, color: colors.textSecondary, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: KpiSummaryRow(kpis: computeTaskKpis(tasks, catalog)),
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
                  Tab(text: 'Grupos'),
                  Tab(text: 'Racha'),
                  Tab(text: 'Clientes'),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    TasksReportTab(tasks: tasks, range: _range),
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
