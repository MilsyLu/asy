import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/task_visibility.dart';
import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/loading_indicator.dart';
import 'add_edit_task_page.dart';
import 'widgets/reschedule_dialog.dart';
import 'widgets/task_card.dart';
import 'widgets/task_detail_dialog.dart';

/// Capitalizes the first letter of [input] (used for locale-formatted dates,
/// which `intl` returns lowercase in Spanish).
String _capitalize(String input) {
  if (input.isEmpty) return input;
  return input[0].toUpperCase() + input.substring(1);
}

/// Home tab: the day's operational agenda — "¿qué debo atender hoy?".
///
/// Shows today's pending + rescheduled tasks (the agenda), today's
/// completed tasks (collapsed by default) and overdue pending tasks from
/// previous days, each filtered through [isTaskVisibleToUser] and the
/// Grupo/Encargado/Cliente/Estado filters. Full history lives in Reportes.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// How far back to look for overdue ("atrasadas") pending tasks. Reuses
  /// the existing `watchTasksInRange` stream/index (date ASC, hour ASC)
  /// instead of issuing a new query, mirroring the range Reports uses.
  static const _lookbackDays = 30;

  final DateTime _today = DateTime.now();
  final _clientController = TextEditingController();

  late final Stream<List<TaskModel>> _tasksStream;

  String? _groupFilter;
  String? _userFilter;
  String? _statusFilter;
  String _clientQuery = '';
  bool _completedExpanded = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<TaskRepository>();
    final rangeStart = _today.subtract(const Duration(days: _lookbackDays));
    _tasksStream = repo.watchTasksInRange(rangeStart, _today);
  }

  @override
  void dispose() {
    _clientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.appUser;

    return Scaffold(
      body: currentUser == null || catalog.statuses.isEmpty
          ? const LoadingIndicator()
          : StreamBuilder<List<TaskModel>>(
              stream: _tasksStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingIndicator();
                }
                if (snapshot.hasError) {
                  return EmptyState(
                    message: 'Ocurrió un error al cargar las tareas.\n${snapshot.error}',
                    icon: LucideIcons.alertCircle,
                  );
                }

                final visibleTasks = (snapshot.data ?? [])
                    .where((t) => isTaskVisibleToUser(
                          task: t,
                          user: currentUser,
                          catalog: catalog,
                        ))
                    .toList();

                final allAgenda = _Agenda.classify(visibleTasks, _today, catalog);
                final agenda = _Agenda.classify(
                  visibleTasks.where(_matchesFilters).toList(),
                  _today,
                  catalog,
                );

                final nextTask =
                    allAgenda.agendaToday.isNotEmpty ? allAgenda.agendaToday.first : null;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    _HomeHeader(user: currentUser, today: _today, agenda: allAgenda),
                    const SizedBox(height: 20),
                    _CountersGrid(agenda: agenda),
                    const SizedBox(height: 20),
                    _NextTaskCard(task: nextTask),
                    const SizedBox(height: 24),
                    _FiltersBar(
                      catalog: catalog,
                      groupFilter: _groupFilter,
                      userFilter: _userFilter,
                      statusFilter: _statusFilter,
                      clientController: _clientController,
                      onGroupChanged: (v) => setState(() => _groupFilter = v),
                      onUserChanged: (v) => setState(() => _userFilter = v),
                      onStatusChanged: (v) => setState(() => _statusFilter = v),
                      onClientChanged: (v) => setState(() => _clientQuery = v),
                    ),
                    const SizedBox(height: 20),
                    if (allAgenda.isEmpty)
                      const EmptyState(
                        message: 'No tienes tareas pendientes para hoy. ¡Buen trabajo!',
                        icon: LucideIcons.checkCircle2,
                      )
                    else if (agenda.isEmpty)
                      const EmptyState(
                        message: 'Ningún resultado coincide con los filtros seleccionados.',
                        icon: LucideIcons.search,
                      )
                    else
                      ..._buildSections(agenda),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddEditTaskPage(initialDate: _today),
            ),
          );
        },
        child: const Icon(LucideIcons.plus),
      ),
    );
  }

  List<Widget> _buildSections(_Agenda agenda) {
    return [
      const _SectionHeader(
        icon: LucideIcons.listTodo,
        title: 'Agenda de hoy',
      ),
      const SizedBox(height: 10),
      if (agenda.agendaToday.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Text(
            'No hay tareas pendientes ni reprogramadas para hoy.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
        )
      else
        for (final t in agenda.agendaToday) _AgendaTaskTile(task: t),
      if (agenda.completedToday.isNotEmpty) ...[
        const SizedBox(height: 16),
        _CompletedTodaySection(
          tasks: agenda.completedToday,
          expanded: _completedExpanded,
          onToggle: () => setState(() => _completedExpanded = !_completedExpanded),
        ),
      ],
      if (agenda.overdue.isNotEmpty) ...[
        const SizedBox(height: 16),
        _OverdueSection(tasks: agenda.overdue),
      ],
    ];
  }

  bool _matchesFilters(TaskModel task) {
    if (_groupFilter != null && task.groupId != _groupFilter) return false;
    if (_userFilter != null && task.assignedUserId != _userFilter) return false;
    if (_statusFilter != null && task.statusId != _statusFilter) return false;
    if (_clientQuery.isNotEmpty &&
        !task.clientName.toLowerCase().contains(_clientQuery.toLowerCase())) {
      return false;
    }
    return true;
  }
}

/// Classifies a (visibility + filter)-already-applied list of tasks into
/// the buckets shown on Home: today's pending/rescheduled/completed tasks,
/// and overdue (date < today, still pending) tasks. Cancelled tasks,
/// tasks completed/rescheduled on other days, and pending tasks from
/// before today that aren't overdue-pending are intentionally dropped —
/// Home is a daily agenda, not a history (that's Reportes).
class _Agenda {
  _Agenda({
    required this.pendingToday,
    required this.rescheduledToday,
    required this.completedToday,
    required this.overdue,
  });

  final List<TaskModel> pendingToday;
  final List<TaskModel> rescheduledToday;
  final List<TaskModel> completedToday;
  final List<TaskModel> overdue;

  List<TaskModel> get agendaToday =>
      [...pendingToday, ...rescheduledToday]..sort((a, b) => a.hour.compareTo(b.hour));

  bool get isEmpty =>
      pendingToday.isEmpty &&
      rescheduledToday.isEmpty &&
      completedToday.isEmpty &&
      overdue.isEmpty;

  static _Agenda classify(List<TaskModel> tasks, DateTime today, CatalogProvider catalog) {
    final todayKey = AppDateUtils.formatDateKey(today);
    final pendingId = catalog.pendingStatusId;
    final completedId = catalog.completedStatusId;
    final rescheduledId = catalog.rescheduledStatusId;

    final pendingToday = <TaskModel>[];
    final rescheduledToday = <TaskModel>[];
    final completedToday = <TaskModel>[];
    final overdue = <TaskModel>[];

    for (final t in tasks) {
      if (t.date == todayKey) {
        if (t.statusId == pendingId) {
          pendingToday.add(t);
        } else if (t.statusId == rescheduledId) {
          rescheduledToday.add(t);
        } else if (t.statusId == completedId) {
          completedToday.add(t);
        }
      } else if (t.date.compareTo(todayKey) < 0 && t.statusId == pendingId) {
        overdue.add(t);
      }
    }

    pendingToday.sort((a, b) => a.hour.compareTo(b.hour));
    rescheduledToday.sort((a, b) => a.hour.compareTo(b.hour));
    completedToday.sort((a, b) => a.hour.compareTo(b.hour));
    overdue.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.hour.compareTo(b.hour);
    });

    return _Agenda(
      pendingToday: pendingToday,
      rescheduledToday: rescheduledToday,
      completedToday: completedToday,
      overdue: overdue,
    );
  }
}

/// Header: personalized greeting, today's date and a one-line summary of
/// the user's day ("Tienes N tareas para hoy" / "N tareas atrasadas
/// requieren atención"). [agenda] is intentionally the *unfiltered* agenda
/// (visibility-filtered only) so this summary always reflects the user's
/// real day regardless of the Grupo/Encargado/Cliente/Estado filters below.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.user, required this.today, required this.agenda});

  final AppUser user;
  final DateTime today;
  final _Agenda agenda;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    final firstName = user.name.trim().isEmpty
        ? user.name
        : user.name.trim().split(RegExp(r'\s+')).first;
    final dateLabel = _capitalize(AppDateUtils.formatHeaderDate(today));
    final todayTasks = agenda.agendaToday;
    final todayCount = todayTasks.length;
    final myCount = todayTasks.where((t) => t.assignedUserId == user.id).length;
    final overdueCount = agenda.overdue.length;
    final groupName = user.groupId != null ? catalog.groupName(user.groupId) : null;
    final showOwnLine = groupName != null || user.isSuperAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting(today.hour)}, $firstName',
          style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          dateLabel,
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.listTodo, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _summaryText(groupName, user.isSuperAdmin, todayCount),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (showOwnLine) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.userCheck, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tus tareas asignadas: $myCount',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (overdueCount > 0) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.alertTriangle, size: 16, color: colors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _overdueText(overdueCount),
                  style: TextStyle(color: colors.error, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _greeting(int hour) {
    if (hour >= 6 && hour < 12) return 'Buenos días';
    if (hour >= 12 && hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  static String _summaryText(String? groupName, bool isSuperAdmin, int count) {
    final noun = count == 1 ? 'tarea' : 'tareas';
    if (groupName != null) {
      return count == 0
          ? '$groupName no tiene tareas para hoy'
          : '$groupName tiene $count $noun para hoy';
    }
    if (isSuperAdmin) {
      return count == 0
          ? 'No hay tareas programadas para hoy'
          : 'Hay $count $noun programadas para hoy';
    }
    return count == 0 ? 'No tienes tareas para hoy' : 'Tienes $count $noun para hoy';
  }

  static String _overdueText(int count) {
    final noun = count == 1 ? 'tarea atrasada' : 'tareas atrasadas';
    final verb = count == 1 ? 'requiere' : 'requieren';
    return '$count $noun $verb atención';
  }
}

/// "Próxima tarea": the most important element of the screen. Highlights
/// the first item of today's agenda (earliest pending/rescheduled task,
/// already sorted by hour) with its hour, client, task type and assignee,
/// plus a "Ver detalles" shortcut that opens the task's full detail dialog
/// directly. Shows an elegant empty state when there's nothing left for
/// today.
class _NextTaskCard extends StatelessWidget {
  const _NextTaskCard({required this.task});

  final TaskModel? task;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final task = this.task;

    if (task == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.success.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.checkCircle2, size: 28, color: colors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Todo en orden!',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No tienes tareas pendientes por el momento.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final catalog = context.watch<CatalogProvider>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.star, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'PRÓXIMA TAREA',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.clock, size: 22, color: colors.primary),
                        const SizedBox(width: 8),
                        Text(
                          task.hour,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      task.clientName,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(LucideIcons.tag, size: 14, color: colors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            catalog.taskTypeName(task.taskTypeId),
                            style: TextStyle(color: colors.textSecondary, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(LucideIcons.userCheck, size: 14, color: colors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            catalog.userName(task.assignedUserId),
                            style: TextStyle(color: colors.textSecondary, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QuickActionButton(
                    icon: LucideIcons.checkCircle2,
                    color: colors.success,
                    tooltip: 'Completar',
                    onPressed: () => completeTaskWithConfirm(context, task),
                  ),
                  const SizedBox(height: 10),
                  _QuickActionButton(
                    icon: LucideIcons.repeat,
                    color: colors.statusRescheduled,
                    tooltip: 'Reprogramar',
                    onPressed: () => showRescheduleDialog(context, task),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => showTaskDetailDialog(context, task),
              icon: const Icon(LucideIcons.eye, size: 16),
              label: const Text('Ver detalles'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small circular icon button used for the "Próxima tarea" quick actions
/// (Completar / Reprogramar). Compact by design so the right-side action
/// column can later accommodate an additional action (e.g. papelera) without
/// reworking the card layout.
class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

/// Compact 2x2 summary grid: Pendientes / Reprogramadas / Completadas /
/// Atrasadas. Reflects [agenda], which is already filtered by visibility and
/// the active Grupo/Encargado/Cliente/Estado filters — the underlying counts
/// are unchanged from the previous design, only the presentation is more
/// compact (big number + small label).
class _CountersGrid extends StatelessWidget {
  const _CountersGrid({required this.agenda});

  final _Agenda agenda;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CounterCard(
                label: 'Pendientes',
                count: agenda.pendingToday.length,
                icon: LucideIcons.circleDot,
                color: colors.statusPending,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CounterCard(
                label: 'Reprogramadas',
                count: agenda.rescheduledToday.length,
                icon: LucideIcons.repeat,
                color: colors.statusRescheduled,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _CounterCard(
                label: 'Completadas',
                count: agenda.completedToday.length,
                icon: LucideIcons.checkCircle2,
                color: colors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CounterCard(
                label: 'Atrasadas',
                count: agenda.overdue.length,
                icon: LucideIcons.alertTriangle,
                color: colors.error,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(icon, color: color, size: 18),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.count,
    this.color,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final int? count;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.colors.primary;
    return Row(
      children: [
        Icon(icon, color: effectiveColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (count != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(color: effectiveColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) const SizedBox(width: 8),
        ],
        ?trailing,
      ],
    );
  }
}

/// Resolves the accent color for a status chip in the "Agenda del día" list,
/// following the FASE 3B palette: Pendiente → ámbar, Completada → verde,
/// Reprogramada → azul, Cancelada → gris. Any other/unknown status name
/// (and the default) falls back to the muted gray used for "Cancelada".
Color _statusChipColor(AppColorsExtension colors, String statusName) {
  if (statusName.toLowerCase() == AppStatusNames.pendiente.toLowerCase()) {
    return colors.statusPending;
  }
  if (statusName.toLowerCase() == AppStatusNames.completada.toLowerCase()) {
    return colors.success;
  }
  if (statusName.toLowerCase() == AppStatusNames.reprogramada.toLowerCase()) {
    return colors.statusRescheduled;
  }
  return colors.textSecondary;
}

/// Redesigned task row for the Home agenda sections (Agenda de hoy,
/// Completadas hoy, Tareas atrasadas). Shows the same information as the
/// shared [TaskCard] — hour, client, status, task type, assignee — with a
/// clearer visual hierarchy (hour badge + big client name + status chip,
/// type/assignee as secondary text). Tapping the tile opens the task's full
/// detail dialog directly. Pending/rescheduled tiles also show an inline
/// "Completar" button for quick access; the action row is right-aligned so
/// a future trash/papelera button can be appended without reworking the
/// layout.
///
/// [overrideChipColor] lets the "Tareas atrasadas" section force the chip to
/// the error/red color regardless of the task's real status name (which
/// stays "Pendiente" — the displayed text is unchanged).
class _AgendaTaskTile extends StatelessWidget {
  const _AgendaTaskTile({required this.task, this.overrideChipColor});

  final TaskModel task;
  final Color? overrideChipColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    final statusName = catalog.statusName(task.statusId);
    final chipColor = overrideChipColor ?? _statusChipColor(colors, statusName);
    final isCompleted = task.statusId == catalog.completedStatusId;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showTaskDetailDialog(context, task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 54),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    task.hour,
                    style: TextStyle(color: colors.primary, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              task.clientName,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: chipColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: chipColor.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              statusName,
                              style: TextStyle(
                                color: chipColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        catalog.taskTypeName(task.taskTypeId),
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(LucideIcons.userCheck, size: 12, color: colors.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              catalog.userName(task.assignedUserId),
                              style: TextStyle(color: colors.textSecondary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronRight, size: 16, color: colors.textSecondary),
              ],
            ),
            if (!isCompleted) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => completeTaskWithConfirm(context, task),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.success,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(LucideIcons.checkCircle2, size: 16),
                    label: const Text('Completar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Completadas hoy" — collapsed by default; expands to show today's
/// completed tasks without mixing them into the pending agenda.
class _CompletedTodaySection extends StatelessWidget {
  const _CompletedTodaySection({
    required this.tasks,
    required this.expanded,
    required this.onToggle,
  });

  final List<TaskModel> tasks;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.success.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _SectionHeader(
                icon: LucideIcons.checkCircle2,
                title: 'Completadas hoy',
                count: tasks.length,
                color: context.colors.success,
                trailing: Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  color: context.colors.textSecondary,
                  size: 18,
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(children: [for (final t in tasks) _AgendaTaskTile(task: t)]),
            ),
        ],
      ),
    );
  }
}

/// "Tareas atrasadas" — pending tasks whose date is before today, kept
/// visually separate (red accent) from today's agenda. Each task shows
/// its original date since it isn't today, and its status chip is forced to
/// the error/red color regardless of the underlying "Pendiente" status name.
class _OverdueSection extends StatelessWidget {
  const _OverdueSection({required this.tasks});

  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            icon: LucideIcons.alertTriangle,
            title: 'Tareas atrasadas',
            count: tasks.length,
            color: colors.error,
          ),
          const SizedBox(height: 10),
          for (final t in tasks) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: Text(
                AppDateUtils.formatShortDate(AppDateUtils.parseDateKey(t.date)),
                style: TextStyle(
                  color: colors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _AgendaTaskTile(task: t, overrideChipColor: colors.error),
          ],
        ],
      ),
    );
  }
}

/// Combinable "Grupo / Encargado / Estado / Cliente" filter row. Every
/// dropdown defaults to "Todos" (a null value, meaning no filter applied).
class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.catalog,
    required this.groupFilter,
    required this.userFilter,
    required this.statusFilter,
    required this.clientController,
    required this.onGroupChanged,
    required this.onUserChanged,
    required this.onStatusChanged,
    required this.onClientChanged,
  });

  final CatalogProvider catalog;
  final String? groupFilter;
  final String? userFilter;
  final String? statusFilter;
  final TextEditingController clientController;
  final ValueChanged<String?> onGroupChanged;
  final ValueChanged<String?> onUserChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String> onClientChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final users = List.of(catalog.users)..sort((a, b) => a.name.compareTo(b.name));
    final groups = List.of(catalog.groups)..sort((a, b) => a.name.compareTo(b.name));
    final statuses = List.of(catalog.statuses)..sort((a, b) => a.name.compareTo(b.name));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(LucideIcons.slidersHorizontal, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'Filtros',
                style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FilterDropdown<String>(
                  label: 'Grupo',
                  icon: LucideIcons.users,
                  value: groupFilter,
                  items: [
                    for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: onGroupChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterDropdown<String>(
                  label: 'Encargado',
                  icon: LucideIcons.userCheck,
                  value: userFilter,
                  items: [
                    for (final u in users) DropdownMenuItem(value: u.id, child: Text(u.name)),
                  ],
                  onChanged: onUserChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FilterDropdown<String>(
                  label: 'Estado',
                  icon: LucideIcons.listChecks,
                  value: statusFilter,
                  items: [
                    for (final s in statuses) DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: clientController,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Cliente',
                    prefixIcon: Icon(LucideIcons.search, color: colors.primary, size: 18),
                    suffixIcon: clientController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(LucideIcons.xCircle, size: 16),
                            onPressed: () {
                              clientController.clear();
                              onClientChanged('');
                            },
                          ),
                  ),
                  onChanged: onClientChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon, color: context.colors.primary, size: 18),
      ),
      dropdownColor: context.colors.surface,
      items: [
        const DropdownMenuItem(value: null, child: Text('Todos')),
        ...items,
      ],
      onChanged: onChanged,
    );
  }
}
