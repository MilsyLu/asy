import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/theme_colors.dart';
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
    final colors = context.colors;

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
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: colors.primary, fontWeight: FontWeight.bold, fontSize: 17),
                  leftChevronIcon: Icon(LucideIcons.chevronLeft, color: colors.primary),
                  rightChevronIcon: Icon(LucideIcons.chevronRight, color: colors.primary),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: colors.textSecondary),
                  weekendStyle: TextStyle(color: colors.textSecondary),
                ),
                calendarStyle: CalendarStyle(
                  defaultTextStyle: TextStyle(color: colors.textPrimary),
                  weekendTextStyle: TextStyle(color: colors.textPrimary),
                  outsideTextStyle: TextStyle(color: colors.textSecondary.withValues(alpha: 0.4)),
                  todayDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.primary, width: 1.5),
                  ),
                  todayTextStyle: TextStyle(color: colors.primary),
                  selectedDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary,
                  ),
                  selectedTextStyle: TextStyle(
                    color: colors.background,
                    fontWeight: FontWeight.bold,
                  ),
                  markerDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primaryLight,
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
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary,
                        ),
                        child: Text(
                          '${events.length}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colors.background,
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
                    Icon(LucideIcons.listChecks, color: colors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      AppDateUtils.formatShortDate(_selectedDay),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${selectedTasks.length} ${selectedTasks.length == 1 ? 'tarea' : 'tareas'}',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
