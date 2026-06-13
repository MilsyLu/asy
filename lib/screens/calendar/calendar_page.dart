import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

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

/// Monthly calendar: each day shows a bubble with the task count.
/// Tapping a day lists its tasks below; long-pressing a task opens
/// quick actions (editar / reprogramar / completar).
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.appUser;

    // Pull a wide-enough window so paging months doesn't require a
    // new query for the visible range immediately.
    final rangeStart = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
    final rangeEnd = DateTime(_focusedDay.year, _focusedDay.month + 2, 0);

    if (currentUser == null) {
      return const Scaffold(body: LoadingIndicator());
    }

    return Scaffold(
      body: StreamBuilder<List<TaskModel>>(
        stream: repo.watchTasksInRange(rangeStart, rangeEnd),
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

          final tasksByDate = <String, List<TaskModel>>{};
          for (final t in tasks) {
            tasksByDate.putIfAbsent(t.date, () => []).add(t);
          }

          final selectedKey = AppDateUtils.formatDateKey(_selectedDay);
          final selectedTasks = (tasksByDate[selectedKey] ?? [])
            ..sort((a, b) => a.hour.compareTo(b.hour));

          return Column(
            children: [
              TableCalendar<TaskModel>(
                locale: 'es_ES',
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) {
                  setState(() => _focusedDay = focused);
                },
                eventLoader: (day) =>
                    tasksByDate[AppDateUtils.formatDateKey(day)] ?? [],
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 17),
                  leftChevronIcon: Icon(LucideIcons.chevronLeft, color: AppColors.gold),
                  rightChevronIcon: Icon(LucideIcons.chevronRight, color: AppColors.gold),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: AppColors.textSecondary),
                  weekendStyle: TextStyle(color: AppColors.textSecondary),
                ),
                calendarStyle: CalendarStyle(
                  defaultTextStyle: const TextStyle(color: AppColors.textPrimary),
                  weekendTextStyle: const TextStyle(color: AppColors.textPrimary),
                  outsideTextStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4)),
                  todayDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 1.5),
                  ),
                  todayTextStyle: const TextStyle(color: AppColors.gold),
                  selectedDecoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold,
                  ),
                  selectedTextStyle: const TextStyle(
                    color: AppColors.background,
                    fontWeight: FontWeight.bold,
                  ),
                  markerDecoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.goldLight,
                  ),
                  markersMaxCount: 1,
                ),
                calendarBuilders: CalendarBuilders<TaskModel>(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    return Positioned(
                      bottom: 2,
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.gold,
                        ),
                        child: Text(
                          '${events.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.background,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(LucideIcons.listChecks, color: AppColors.gold, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      AppDateUtils.formatShortDate(_selectedDay),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${selectedTasks.length} ${selectedTasks.length == 1 ? 'tarea' : 'tareas'}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: selectedTasks.isEmpty
                    ? const EmptyState(
                        message: 'No hay tareas para este día.',
                        icon: LucideIcons.calendarDays,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: selectedTasks.length,
                        itemBuilder: (context, index) {
                          final task = selectedTasks[index];
                          return GestureDetector(
                            onLongPress: () => showTaskQuickActionsSheet(context, task),
                            child: TaskCard(task: task),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddEditTaskPage(initialDate: _selectedDay),
            ),
          );
        },
        child: const Icon(LucideIcons.plus),
      ),
    );
  }
}
