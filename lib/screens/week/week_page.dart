import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/task_visibility.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/loading_indicator.dart';
import '../home/add_edit_task_page.dart';
import '../home/widgets/compact_task_card.dart';
import '../home/widgets/task_card.dart';
import '../home/widgets/task_detail_dialog.dart';

const _dayLabels = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
const _monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

String _monthYear(DateTime date) =>
    '${_monthNames[date.month - 1]} ${date.year}';

String _dayOfMonth(DateTime date) =>
    '${date.day} de ${_monthNames[date.month - 1]}';

/// Professional weekly agenda: horizontal day-chip selector at the top,
/// a compact status summary below, and a scrollable task list for the
/// selected day. Replaces the old hour×day grid format.
class WeekPage extends StatefulWidget {
  const WeekPage({super.key});

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  late DateTime _weekStart;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    _weekStart = DateTime(monday.year, monday.month, monday.day);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _prevWeek() {
    final dayOffset = _selectedDay.difference(_weekStart).inDays.clamp(0, 6);
    final newStart = _weekStart.subtract(const Duration(days: 7));
    setState(() {
      _weekStart = newStart;
      _selectedDay = newStart.add(Duration(days: dayOffset));
    });
  }

  void _nextWeek() {
    final dayOffset = _selectedDay.difference(_weekStart).inDays.clamp(0, 6);
    final newStart = _weekStart.add(const Duration(days: 7));
    setState(() {
      _weekStart = newStart;
      _selectedDay = newStart.add(Duration(days: dayOffset));
    });
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

    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));

    return Scaffold(
      body: StreamBuilder<List<TaskModel>>(
        stream: repo.watchTasksInRange(_weekStart, weekEnd),
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

          final allTasks = (snapshot.data ?? [])
              .where((t) => isTaskVisibleToUser(
                    task: t,
                    user: currentUser,
                    catalog: catalog,
                  ))
              .toList();

          final tasksByDate = <String, List<TaskModel>>{};
          for (final t in allTasks) {
            tasksByDate.putIfAbsent(t.date, () => []).add(t);
          }

          final selectedKey = AppDateUtils.formatDateKey(_selectedDay);
          final selectedTasks = List<TaskModel>.from(tasksByDate[selectedKey] ?? [])
            ..sort((a, b) => a.hour.compareTo(b.hour));

          return Column(
            children: [
              _WeekHeader(
                weekStart: _weekStart,
                onPrevious: _prevWeek,
                onNext: _nextWeek,
              ),
              _DaySelector(
                days: days,
                selectedDay: _selectedDay,
                tasksByDate: tasksByDate,
                onDaySelected: (day) => setState(() => _selectedDay = day),
              ),
              const Divider(height: 1),
              _DaySummary(
                selectedDay: _selectedDay,
                tasks: selectedTasks,
                catalog: catalog,
              ),
              const Divider(height: 1),
              Expanded(child: _DayAgenda(tasks: selectedTasks)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddEditTaskPage(initialDate: _selectedDay),
          ),
        ),
        child: const Icon(LucideIcons.plus),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header: month+year title + week navigation arrows
// ---------------------------------------------------------------------------

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.weekStart,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(LucideIcons.chevronLeft, color: colors.primary),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _monthYear(weekStart),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Agenda semanal',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.chevronRight, color: colors.primary),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day selector: horizontal scrollable row of day chips
// ---------------------------------------------------------------------------

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selectedDay,
    required this.tasksByDate,
    required this.onDaySelected,
  });

  final List<DateTime> days;
  final DateTime selectedDay;
  final Map<String, List<TaskModel>> tasksByDate;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: days.length,
        itemBuilder: (context, i) {
          final day = days[i];
          final dayKey = AppDateUtils.formatDateKey(day);
          final hasTask = (tasksByDate[dayKey]?.isNotEmpty) ?? false;
          return _DayChip(
            day: day,
            label: _dayLabels[day.weekday - 1],
            isSelected: AppDateUtils.isSameDay(day, selectedDay),
            isToday: AppDateUtils.isSameDay(day, DateTime.now()),
            hasTask: hasTask,
            onTap: () => onDaySelected(day),
          );
        },
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.label,
    required this.isSelected,
    required this.isToday,
    required this.hasTask,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool isSelected;
  final bool isToday;
  final bool hasTask;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final bgColor = isSelected ? colors.primary : Colors.transparent;
    final numberColor = isSelected
        ? colors.onPrimary
        : (isToday ? colors.primary : colors.textPrimary);
    final labelColor =
        isSelected ? colors.onPrimary : colors.textSecondary;
    final dotColor = isSelected
        ? colors.onPrimary.withValues(alpha: 0.7)
        : colors.primary;

    BoxBorder? border;
    if (!isSelected) {
      border = isToday
          ? Border.all(color: colors.primary, width: 1.5)
          : Border.all(color: colors.divider);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: border,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                color: numberColor,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              height: 9,
              child: hasTask
                  ? Center(
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotColor,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day summary: date label + total count + per-status badges
// ---------------------------------------------------------------------------

class _DaySummary extends StatelessWidget {
  const _DaySummary({
    required this.selectedDay,
    required this.tasks,
    required this.catalog,
  });

  final DateTime selectedDay;
  final List<TaskModel> tasks;
  final CatalogProvider catalog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    var pendingCount = 0;
    var completedCount = 0;
    var rescheduledCount = 0;

    for (final t in tasks) {
      final lower = catalog.statusName(t.statusId).toLowerCase();
      if (lower == AppStatusNames.pendiente.toLowerCase()) {
        pendingCount++;
      } else if (lower == AppStatusNames.completada.toLowerCase()) {
        completedCount++;
      } else if (lower == AppStatusNames.reprogramada.toLowerCase()) {
        rescheduledCount++;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dayOfMonth(selectedDay),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${tasks.length} ${tasks.length == 1 ? 'tarea' : 'tareas'} programadas',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          if (tasks.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                if (pendingCount > 0)
                  _StatusBadge(count: pendingCount, color: colors.statusPending),
                if (completedCount > 0)
                  _StatusBadge(count: completedCount, color: colors.success),
                if (rescheduledCount > 0)
                  _StatusBadge(
                      count: rescheduledCount,
                      color: colors.statusRescheduled),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day agenda: sorted task list or empty state
// ---------------------------------------------------------------------------

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({required this.tasks});

  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const EmptyState(
        message: 'No hay tareas programadas para este día.',
        icon: LucideIcons.calendarDays,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: tasks.length,
      itemBuilder: (context, i) {
        final task = tasks[i];
        return GestureDetector(
          onTap: () => showTaskDetailDialog(context, task),
          onLongPress: () => showTaskQuickActionsSheet(context, task),
          child: CompactTaskCard(task: task),
        );
      },
    );
  }
}
