import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/task_visibility.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/loading_indicator.dart';
import '../home/add_edit_task_page.dart';
import '../home/widgets/task_card.dart';

const _dayLabels = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
const _defaultHours = [
  '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00',
  '15:00', '16:00', '17:00', '18:00', '19:00', '20:00',
];

const double _hourColumnWidth = 64;
const double _dayColumnWidth = 140;
const double _rowHeight = 84;
const double _headerHeight = 56;

/// Weekly grid view: hours (rows) x LUN-DOM (columns), each cell shows
/// a compact chip per task scheduled at that date+hour.
class WeekPage extends StatefulWidget {
  const WeekPage({super.key});

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  late DateTime _weekStart;
  final _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    _weekStart = DateTime(monday.year, monday.month, monday.day);
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.appUser;
    final weekEnd = _weekStart.add(const Duration(days: 6));

    if (currentUser == null) {
      return const Scaffold(body: LoadingIndicator());
    }

    final hours = catalog.availableHours.isNotEmpty
        ? (catalog.availableHours.map((h) => h.hour).toList()..sort())
        : _defaultHours;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.chevronLeft, color: AppColors.gold),
                  onPressed: () {
                    setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
                  },
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${AppDateUtils.formatShortDate(_weekStart)} - ${AppDateUtils.formatShortDate(weekEnd)}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.chevronRight, color: AppColors.gold),
                  onPressed: () {
                    setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<TaskModel>>(
              stream: repo.watchTasksInRange(_weekStart, weekEnd),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingIndicator();
                }
                if (snapshot.hasError) {
                  return EmptyState(
                    message:
                        'No se pudieron cargar las tareas.\n${snapshot.error}',
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

                // tasksByDateHour["YYYY-MM-DD"]["HH:MM"] -> [TaskModel]
                final byDateHour = <String, Map<String, List<TaskModel>>>{};
                for (final t in tasks) {
                  final byHour = byDateHour.putIfAbsent(t.date, () => {});
                  byHour.putIfAbsent(t.hour, () => []).add(t);
                }

                final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fixed hour column.
                    SizedBox(
                      width: _hourColumnWidth,
                      child: SingleChildScrollView(
                        controller: _verticalController,
                        child: Column(
                          children: [
                            const SizedBox(height: _headerHeight),
                            for (final hour in hours)
                              Container(
                                height: _rowHeight,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: AppColors.divider),
                                    right: BorderSide(color: AppColors.divider),
                                  ),
                                ),
                                child: Text(
                                  hour,
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Scrollable day grid.
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          child: Column(
                            children: [
                              // Header row with day names + dates.
                              Row(
                                children: [
                                  for (final day in days)
                                    Container(
                                      width: _dayColumnWidth,
                                      height: _headerHeight,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(color: AppColors.gold, width: 1.5),
                                          right: BorderSide(color: AppColors.divider),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _dayLabels[day.weekday - 1],
                                            style: const TextStyle(
                                              color: AppColors.gold,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            AppDateUtils.formatShortDate(day),
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              // Hour rows.
                              for (final hour in hours)
                                Row(
                                  children: [
                                    for (final day in days)
                                      _WeekCell(
                                        tasks: byDateHour[AppDateUtils.formatDateKey(day)]
                                                ?[hour] ??
                                            const [],
                                        catalog: catalog,
                                        day: day,
                                        hour: hour,
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddEditTaskPage(initialDate: _weekStart),
            ),
          );
        },
        child: const Icon(LucideIcons.plus),
      ),
    );
  }
}

class _WeekCell extends StatelessWidget {
  const _WeekCell({
    required this.tasks,
    required this.catalog,
    required this.day,
    required this.hour,
  });

  final List<TaskModel> tasks;
  final CatalogProvider catalog;
  final DateTime day;
  final String hour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _dayColumnWidth,
      height: _rowHeight,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.divider),
          right: BorderSide(color: AppColors.divider),
        ),
      ),
      child: tasks.isEmpty
          ? null
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final task in tasks)
                  GestureDetector(
                    onTap: () => showTaskQuickActionsSheet(context, task),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: const Border(
                          left: BorderSide(color: AppColors.gold, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            task.clientName,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            catalog.taskTypeName(task.taskTypeId),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
