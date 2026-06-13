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
import 'add_edit_task_page.dart';
import 'widgets/task_card.dart';

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

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.calendar, color: AppColors.gold, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _capitalize(AppDateUtils.formatHumanDate(_today)),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    _CountersGrid(agenda: agenda),
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
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Text(
            'No hay tareas pendientes ni reprogramadas para hoy.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        )
      else
        for (final t in agenda.agendaToday) TaskCard(task: t),
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

  String _capitalize(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
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

/// 2x2 grid of counters: Pendientes hoy / Reprogramadas hoy / Completadas
/// hoy / Atrasadas. Reflects [agenda], which is already filtered by
/// visibility and the active Grupo/Encargado/Cliente/Estado filters.
class _CountersGrid extends StatelessWidget {
  const _CountersGrid({required this.agenda});

  final _Agenda agenda;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CounterCard(
                label: 'Pendientes hoy',
                count: agenda.pendingToday.length,
                icon: LucideIcons.circleDot,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CounterCard(
                label: 'Reprogramadas hoy',
                count: agenda.rescheduledToday.length,
                icon: LucideIcons.repeat,
                color: AppColors.goldLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _CounterCard(
                label: 'Completadas hoy',
                count: agenda.completedToday.length,
                icon: LucideIcons.checkCircle2,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CounterCard(
                label: 'Atrasadas',
                count: agenda.overdue.length,
                icon: LucideIcons.alertTriangle,
                color: AppColors.error,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
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
    this.color = AppColors.gold,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final int? count;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (count != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) const SizedBox(width: 8),
        ],
        ?trailing,
      ],
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
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
                color: AppColors.success,
                trailing: Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(children: [for (final t in tasks) TaskCard(task: t)]),
            ),
        ],
      ),
    );
  }
}

/// "Tareas atrasadas" — pending tasks whose date is before today, kept
/// visually separate (red accent) from today's agenda. Each task shows
/// its original date since it isn't today.
class _OverdueSection extends StatelessWidget {
  const _OverdueSection({required this.tasks});

  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            icon: LucideIcons.alertTriangle,
            title: 'Tareas atrasadas',
            count: tasks.length,
            color: AppColors.error,
          ),
          const SizedBox(height: 10),
          for (final t in tasks) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: Text(
                AppDateUtils.formatShortDate(AppDateUtils.parseDateKey(t.date)),
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TaskCard(task: t),
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
    final users = List.of(catalog.users)..sort((a, b) => a.name.compareTo(b.name));
    final groups = List.of(catalog.groups)..sort((a, b) => a.name.compareTo(b.name));
    final statuses = List.of(catalog.statuses)..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      children: [
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
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Cliente',
                  prefixIcon: const Icon(LucideIcons.search, color: AppColors.gold, size: 18),
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
        prefixIcon: Icon(icon, color: AppColors.gold, size: 18),
      ),
      dropdownColor: AppColors.surface,
      items: [
        const DropdownMenuItem(value: null, child: Text('Todos')),
        ...items,
      ],
      onChanged: onChanged,
    );
  }
}
