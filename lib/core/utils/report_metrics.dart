import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/catalog_provider.dart';

/// Aggregate task KPIs (Total/Completadas/Pendientes/Reprogramadas/
/// Cumplimiento %) for an already-loaded, visibility-filtered task list.
///
/// Single source of truth shared by `ReportsPage` (Sprint 6.1) and
/// `DashboardPage` (Sprint 6.2) so both screens always agree — neither
/// computes this by hand.
class TaskKpis {
  const TaskKpis({
    required this.total,
    required this.completed,
    required this.pending,
    required this.rescheduled,
  });

  final int total;
  final int completed;
  final int pending;
  final int rescheduled;

  int get compliancePercent => total == 0 ? 0 : (completed * 100 / total).round();
}

TaskKpis computeTaskKpis(List<TaskModel> tasks, CatalogProvider catalog) {
  final completedId = catalog.completedStatusId;
  final pendingId = catalog.pendingStatusId;
  final rescheduledId = catalog.rescheduledStatusId;
  return TaskKpis(
    total: tasks.length,
    completed: tasks.where((t) => t.statusId == completedId).length,
    pending: tasks.where((t) => t.statusId == pendingId).length,
    rescheduled: tasks.where((t) => t.statusId == rescheduledId).length,
  );
}

/// The user with the most completed tasks in [tasks] (Sprint 6.2 Part 5,
/// "🏆 Usuario con más tareas completadas").
AppUser? topUserByCompleted(List<TaskModel> tasks, CatalogProvider catalog) {
  final completedId = catalog.completedStatusId;
  final counts = <String, int>{};
  for (final t in tasks) {
    if (t.statusId == completedId) {
      counts[t.assignedUserId] = (counts[t.assignedUserId] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return null;
  final topId = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return catalog.userById(topId);
}

/// Per-group assigned/completed counts, used both for the "Grupo con mejor
/// cumplimiento" highlight and the "Cumplimiento por grupo" chart (Sprint
/// 6.2 Parts 5 and 6) so the breakdown is computed exactly once.
class GroupCompliance {
  const GroupCompliance({
    required this.groupId,
    required this.assigned,
    required this.completed,
  });

  final String? groupId;
  final int assigned;
  final int completed;

  int get percent => assigned == 0 ? 0 : (completed * 100 / assigned).round();
}

List<GroupCompliance> computeGroupCompliance(List<TaskModel> tasks, CatalogProvider catalog) {
  final completedId = catalog.completedStatusId;
  final assigned = <String?, int>{};
  final completed = <String?, int>{};
  for (final t in tasks) {
    assigned[t.groupId] = (assigned[t.groupId] ?? 0) + 1;
    if (t.statusId == completedId) {
      completed[t.groupId] = (completed[t.groupId] ?? 0) + 1;
    }
  }
  return assigned.entries
      .map((e) => GroupCompliance(
            groupId: e.key,
            assigned: e.value,
            completed: completed[e.key] ?? 0,
          ))
      .toList();
}

GroupCompliance? bestGroupCompliance(List<GroupCompliance> groups) {
  if (groups.isEmpty) return null;
  return groups.reduce((a, b) => b.percent > a.percent ? b : a);
}

/// The client (name+phone) with the most tasks in [tasks] (Sprint 6.2 Part
/// 5, "⭐ Cliente más atendido").
({String name, String phone, int count})? mostAttendedClient(List<TaskModel> tasks) {
  if (tasks.isEmpty) return null;
  final counts = <String, ({String name, String phone, int count})>{};
  for (final t in tasks) {
    final key = '${t.clientName}|${t.clientPhone}';
    final existing = counts[key];
    counts[key] = (name: t.clientName, phone: t.clientPhone, count: (existing?.count ?? 0) + 1);
  }
  return counts.values.reduce((a, b) => b.count > a.count ? b : a);
}

/// The user with the highest current login streak (Sprint 6.2 Part 5,
/// "🔥 Mejor racha activa"), reusing [AppUser.streakDays] — already loaded
/// on [CatalogProvider.users], no new query.
AppUser? bestActiveStreak(List<AppUser> users) {
  if (users.isEmpty) return null;
  return users.reduce((a, b) => b.streakDays > a.streakDays ? b : a);
}

/// Task counts per status name (Sprint 6.2 Part 6, "Distribución de
/// estados").
Map<String, int> computeStatusDistribution(List<TaskModel> tasks, CatalogProvider catalog) {
  final counts = <String, int>{};
  for (final t in tasks) {
    final name = catalog.statusName(t.statusId);
    counts[name] = (counts[name] ?? 0) + 1;
  }
  return counts;
}

/// Daily task counts for every day in `[start, end]` (inclusive), in
/// chronological order — including days with zero tasks, so the line
/// reflects the whole selected window (Sprint 6.2 Part 6, "Tendencia de
/// tareas").
List<MapEntry<String, int>> computeDailyTrend(
  List<TaskModel> tasks,
  DateTime start,
  DateTime end,
  String Function(DateTime) formatDateKey,
) {
  final counts = <String, int>{};
  for (final t in tasks) {
    counts[t.date] = (counts[t.date] ?? 0) + 1;
  }
  final entries = <MapEntry<String, int>>[];
  var day = start;
  while (!day.isAfter(end)) {
    final key = formatDateKey(day);
    entries.add(MapEntry(key, counts[key] ?? 0));
    day = day.add(const Duration(days: 1));
  }
  return entries;
}

/// Tasks whose scheduled date/time has already passed [now] and that are
/// not yet completed (Sprint 6.3, "⚠️ Tareas vencidas"). Sorted oldest-first
/// so the most urgent items appear at the top of the detail sheet.
List<TaskModel> computeOverdueTasks(
  List<TaskModel> tasks,
  CatalogProvider catalog,
  DateTime now,
) {
  final completedId = catalog.completedStatusId;
  final overdue = tasks
      .where((t) => t.statusId != completedId && t.scheduledDateTime.isBefore(now))
      .toList()
    ..sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime));
  return overdue;
}

/// Tasks scheduled from [now] through the next 24 hours (Sprint 6.3,
/// "📅 Próximas 24 horas"). Sorted chronologically.
List<TaskModel> computeUpcomingTasks(List<TaskModel> tasks, DateTime now) {
  final limit = now.add(const Duration(hours: 24));
  final upcoming = tasks.where((t) {
    final dt = t.scheduledDateTime;
    return !dt.isBefore(now) && !dt.isAfter(limit);
  }).toList()
    ..sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime));
  return upcoming;
}

/// An [AppUser] paired with how many tasks they completed in the trailing
/// 7-day window (Sprint 6.3, "👤 Sin actividad").
class InactiveUserStat {
  const InactiveUserStat({required this.user, required this.completedLast7Days});

  final AppUser user;
  final int completedLast7Days;
}

/// Users with zero completed tasks in the 7 days before [now] (Sprint 6.3,
/// "👤 Usuarios sin actividad"). [allUsers] is the already-loaded
/// [CatalogProvider.users] list — no new query. Completion is judged by
/// [TaskModel.completedAt] (falling back to the scheduled time for legacy
/// rows without it) so it reflects when the work actually happened rather
/// than when it was scheduled.
List<InactiveUserStat> computeInactiveUsers(
  List<TaskModel> tasks,
  List<AppUser> allUsers,
  CatalogProvider catalog,
  DateTime now,
) {
  final completedId = catalog.completedStatusId;
  final since = now.subtract(const Duration(days: 7));
  final completedCounts = <String, int>{};
  for (final t in tasks) {
    if (t.statusId != completedId) continue;
    final completedAt = t.completedAt ?? t.scheduledDateTime;
    if (completedAt.isBefore(since)) continue;
    completedCounts[t.assignedUserId] = (completedCounts[t.assignedUserId] ?? 0) + 1;
  }
  return allUsers
      .where((u) => (completedCounts[u.id] ?? 0) == 0)
      .map((u) => InactiveUserStat(user: u, completedLast7Days: 0))
      .toList();
}
