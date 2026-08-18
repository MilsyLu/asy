import '../../models/app_user.dart';
import '../../models/task_model.dart';

/// The slice of the catalog these calculations actually need.
///
/// `CatalogProvider` satisfies this already — it declares `implements
/// TaskCatalog` and every member below was public on it before this existed,
/// so no screen changed. The point is the other direction: `CatalogProvider`
/// opens Firestore streams in its constructor, which made every metric here
/// impossible to unit-test even though all of them are pure functions over a
/// task list. Depending on five members instead of the whole provider lets a
/// test supply a plain object.
abstract class TaskCatalog {
  /// Status ids, resolved by name — null when the empresa has not created
  /// that status yet, which is why every caller treats them as optional.
  String? get completedStatusId;
  String? get pendingStatusId;
  String? get rescheduledStatusId;
  String? get cancelledStatusId;

  /// Display name for a status id, or '-' when unknown.
  String statusName(String? id);

  /// The user behind an id, or null if they were deleted.
  AppUser? userById(String? id);
}

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
    required this.cancelled,
  });

  final int total;
  final int completed;
  final int pending;
  final int rescheduled;
  final int cancelled;

  /// Tasks that could actually have been fulfilled — everything except the
  /// ones somebody decided not to do.
  int get countable => total - cancelled;

  /// Completed over what was actually there to complete.
  ///
  /// Cancelled tasks used to sit in the denominator, so cancelling one cost a
  /// team exactly as much as letting it lapse. That is backwards on both
  /// counts: a cancellation is a decision, not a failure, and charging for it
  /// rewards the team that quietly leaves a task to go overdue instead.
  int get compliancePercent =>
      countable <= 0 ? 0 : (completed * 100 / countable).round();
}

TaskKpis computeTaskKpis(List<TaskModel> tasks, TaskCatalog catalog) {
  final completedId = catalog.completedStatusId;
  final pendingId = catalog.pendingStatusId;
  final rescheduledId = catalog.rescheduledStatusId;
  final cancelledId = catalog.cancelledStatusId;
  return TaskKpis(
    total: tasks.length,
    completed: tasks.where((t) => t.statusId == completedId).length,
    pending: tasks.where((t) => t.statusId == pendingId).length,
    rescheduled: tasks.where((t) => t.statusId == rescheduledId).length,
    cancelled: tasks.where((t) => t.statusId == cancelledId).length,
  );
}

/// The user with the most completed tasks in [tasks] (Sprint 6.2 Part 5,
/// "🏆 Usuario con más tareas completadas").
AppUser? topUserByCompleted(List<TaskModel> tasks, TaskCatalog catalog) {
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

/// Per-group assigned/completed counts, used both for the "Equipo con mejor
/// cumplimiento" highlight and the "Cumplimiento por equipo" chart (Sprint
/// 6.2 Parts 5 and 6) so the breakdown is computed exactly once.
class GroupCompliance {
  const GroupCompliance({
    required this.groupId,
    required this.assigned,
    required this.completed,
    required this.cancelled,
  });

  final String? groupId;

  /// Everything handed to the team, cancellations included — the honest
  /// workload figure.
  final int assigned;
  final int completed;
  final int cancelled;

  /// Same rule as [TaskKpis.compliancePercent]: cancelled work leaves the
  /// denominator, so a team is never penalised for cancelling.
  int get percent {
    final countable = assigned - cancelled;
    return countable <= 0 ? 0 : (completed * 100 / countable).round();
  }
}

List<GroupCompliance> computeGroupCompliance(List<TaskModel> tasks, TaskCatalog catalog) {
  final completedId = catalog.completedStatusId;
  final cancelledId = catalog.cancelledStatusId;
  final assigned = <String?, int>{};
  final completed = <String?, int>{};
  final cancelled = <String?, int>{};
  for (final t in tasks) {
    assigned[t.groupId] = (assigned[t.groupId] ?? 0) + 1;
    if (t.statusId == completedId) {
      completed[t.groupId] = (completed[t.groupId] ?? 0) + 1;
    }
    if (t.statusId == cancelledId) {
      cancelled[t.groupId] = (cancelled[t.groupId] ?? 0) + 1;
    }
  }
  return assigned.entries
      .map((e) => GroupCompliance(
            groupId: e.key,
            assigned: e.value,
            completed: completed[e.key] ?? 0,
            cancelled: cancelled[e.key] ?? 0,
          ))
      .toList();
}

GroupCompliance? bestGroupCompliance(List<GroupCompliance> groups) {
  if (groups.isEmpty) return null;
  return groups.reduce((a, b) => b.percent > a.percent ? b : a);
}

/// The client (name+phone) with the most tasks in [tasks] (Sprint 6.2 Part
/// 5, "⭐ Cliente más atendido").
({String name, String phone, int count})? mostAttendedClient(
  List<TaskModel> tasks,
  TaskCatalog catalog,
) {
  if (tasks.isEmpty) return null;
  final cancelledId = catalog.cancelledStatusId;
  final counts = <String, ({String name, String phone, int count})>{};
  for (final t in tasks) {
    // A cancelled visit is not attention the client received.
    if (t.statusId == cancelledId) continue;
    // Group by the real client record when the task has one, exactly as
    // `top_clients_report_tab.dart` does. Keying on the typed name and phone
    // alone splits a client in two the moment either is corrected — and left
    // the Dashboard and the Reports screen free to name different "top"
    // clients from the same data.
    final key = t.clientId ?? '${t.clientName}|${t.clientPhone}';
    final existing = counts[key];
    counts[key] = (
      name: t.clientName,
      phone: t.clientPhone,
      count: (existing?.count ?? 0) + 1,
    );
  }
  if (counts.isEmpty) return null;
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
Map<String, int> computeStatusDistribution(List<TaskModel> tasks, TaskCatalog catalog) {
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
  TaskCatalog catalog,
  DateTime now,
) {
  final completedId = catalog.completedStatusId;
  final cancelledId = catalog.cancelledStatusId;
  // A cancelled task cannot be late: nobody is waiting on it. Leaving them in
  // meant the "tareas vencidas" count asked somebody to chase work that had
  // already been called off.
  final overdue = tasks
      .where((t) =>
          t.statusId != completedId &&
          t.statusId != cancelledId &&
          t.scheduledDateTime.isBefore(now))
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
  const InactiveUserStat({required this.user, required this.daysSinceLastCompleted});

  final AppUser user;

  /// Whole days since this user last completed anything, or null when they
  /// never have. Replaces an earlier `completedLast7Days`, which could only
  /// ever be 0 — the list is *defined* as users with zero completions in the
  /// window, so showing that count told the reader nothing. How long someone
  /// has been idle does vary, and it is what separates "was off two days
  /// extra" from "has not worked in two months".
  final int? daysSinceLastCompleted;
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
  TaskCatalog catalog,
  DateTime now,
) {
  final completedId = catalog.completedStatusId;
  final since = now.subtract(const Duration(days: 7));

  // Two passes over the same loop: who worked inside the window (which
  // decides membership), and when each person last finished anything at all
  // (which is what the list actually reports).
  final activos = <String>{};
  final ultimaCompletada = <String, DateTime>{};
  for (final t in tasks) {
    if (t.statusId != completedId) continue;
    final completedAt = t.completedAt ?? t.scheduledDateTime;
    if (!completedAt.isBefore(since)) activos.add(t.assignedUserId);

    final previa = ultimaCompletada[t.assignedUserId];
    if (previa == null || completedAt.isAfter(previa)) {
      ultimaCompletada[t.assignedUserId] = completedAt;
    }
  }

  final inactivos = allUsers.where((u) => !activos.contains(u.id)).map((u) {
    final ultima = ultimaCompletada[u.id];
    return InactiveUserStat(
      user: u,
      daysSinceLastCompleted: ultima == null ? null : now.difference(ultima).inDays,
    );
  }).toList();

  // Peor primero: quien nunca completó nada encabeza, después de mayor a
  // menor inactividad. Una lista para priorizar no debería empezar por el
  // caso más leve.
  inactivos.sort((a, b) {
    final da = a.daysSinceLastCompleted;
    final db = b.daysSinceLastCompleted;
    if (da == null && db == null) return 0;
    if (da == null) return -1;
    if (db == null) return 1;
    return db.compareTo(da);
  });
  return inactivos;
}
