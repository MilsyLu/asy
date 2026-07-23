import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/task_type_colors.dart';
import '../../core/utils/task_visibility.dart';
import '../../core/utils/validators.dart';
import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/task_type_chip.dart';
import 'add_edit_task_page.dart';
import 'widgets/reschedule_dialog.dart';
import 'widgets/task_card.dart';
import 'widgets/task_create_panel.dart';
import 'widgets/task_detail_dialog.dart';

/// Capitalizes the first letter of [input] (used for locale-formatted dates,
/// which `intl` returns lowercase in Spanish).
String _capitalize(String input) {
  if (input.isEmpty) return input;
  return input[0].toUpperCase() + input.substring(1);
}

// ── Desktop agenda table column widths (Home redesign) ──────────────────────
// Shared between _DesktopAgendaColumnHeader and _DesktopAgendaRow so labels
// and values line up like spreadsheet columns.
const double _kDesktopColHour = 56;
const double _kDesktopColContacto = 140;
const double _kDesktopColEstado = 116;
const double _kDesktopColActions = 148;

/// Home tab: the day's operational agenda — "¿qué debo atender hoy?".
///
/// Shows today's pending + rescheduled tasks (the agenda), today's
/// completed tasks (collapsed by default) and overdue pending tasks from
/// previous days, each filtered through [isTaskVisibleToUser] and the
/// Equipo/Encargado/Cliente/Estado filters. Full history lives in Reportes.
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
  late final Stopwatch _loadStopwatch;
  bool _loadLogged = false;

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
    _loadStopwatch = Stopwatch()..start();
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
                if (!_loadLogged && snapshot.connectionState != ConnectionState.waiting) {
                  _loadLogged = true;
                  debugPrint('[PERF] Home/Agenda load: ${_loadStopwatch.elapsedMilliseconds}ms');
                }
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

                if (context.isDesktop) {
                  return _buildDesktopBody(
                    context,
                    currentUser: currentUser,
                    allAgenda: allAgenda,
                    agenda: agenda,
                    nextTask: nextTask,
                  );
                }

                if (context.isTablet) {
                  return _buildTabletBody(
                    context,
                    currentUser: currentUser,
                    allAgenda: allAgenda,
                    agenda: agenda,
                    nextTask: nextTask,
                  );
                }

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
      // Desktop no longer needs the FAB: creating a task happens inline via
      // the always-visible "Programación"/"Cliente y notas" panel in the
      // right column (see _buildDesktopBody). Tablet/mobile keep it — they
      // still navigate to the full AddEditTaskPage.
      floatingActionButton: context.isDesktop
          ? null
          : FloatingActionButton(
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

  /// Desktop (≥1024 px) layout: two columns instead of the mobile
  /// single-column stack, so the screen uses the available width instead of
  /// stretching mobile cards edge-to-edge and forcing a page-level scroll.
  ///
  /// Left column (flexible): a combined header card — greeting/summary next
  /// to a compact "Próxima tarea" strip (see [_DesktopHeaderCard]) — then
  /// filters, then the agenda table. The 4 counters (Pendientes/
  /// Reprogramadas/Completadas/Atrasadas) sit in a single compact row right
  /// under the header — they describe *this* column's agenda, and living
  /// here means they're always visible without depending on how tall the
  /// create-task card in the right column happens to be. Only the agenda
  /// table scrolls internally (via `Expanded` + `ListView`).
  ///
  /// Right column (fixed width): the inline task-creation form
  /// ([TaskCreatePanel] — one merged card, Cliente then Programación)
  /// replacing the old FAB → full-page flow. Scrolls internally if it's
  /// taller than the viewport.
  Widget _buildDesktopBody(
    BuildContext context, {
    required AppUser currentUser,
    required _Agenda allAgenda,
    required _Agenda agenda,
    required TaskModel? nextTask,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DesktopHeaderCard(
                  user: currentUser,
                  today: _today,
                  agenda: allAgenda,
                  showNextTaskStrip: true,
                  nextTask: nextTask,
                ),
                const SizedBox(height: AppSpacing.md),
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
                    const SizedBox(width: 10),
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
                const SizedBox(height: AppSpacing.md),
                _FiltersBar(
                  catalog: context.watch<CatalogProvider>(),
                  groupFilter: _groupFilter,
                  userFilter: _userFilter,
                  statusFilter: _statusFilter,
                  clientController: _clientController,
                  singleRow: true,
                  onGroupChanged: (v) => setState(() => _groupFilter = v),
                  onUserChanged: (v) => setState(() => _userFilter = v),
                  onStatusChanged: (v) => setState(() => _statusFilter = v),
                  onClientChanged: (v) => setState(() => _clientQuery = v),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: _DesktopAgendaPanel(
                    allAgenda: allAgenda,
                    agenda: agenda,
                    completedExpanded: _completedExpanded,
                    onToggleCompleted: () =>
                        setState(() => _completedExpanded = !_completedExpanded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: TaskCreatePanel(initialDate: _today),
            ),
          ),
        ],
      ),
    );
  }

  /// Tablet (600–1023 px) layout: still a single scrolling column (there
  /// isn't enough width for the desktop two-column layout), but reorganized
  /// per the same redundancy-elimination logic — the header and the next-task
  /// summary sit side by side in one row instead of stacked as two separate
  /// blocks, the 4 counters (Pendientes/Reprogramadas/Completadas/Atrasadas)
  /// sit narrow, side by side in a single row instead of a taller 2×2 grid,
  /// and Filtros moves up to occupy the row that grid used to need instead of
  /// requiring a scroll to reach it. The former standalone "Próxima tarea"
  /// card is folded into one "Listado de órdenes para hoy" panel together
  /// with the rest of the day's tasks, instead of duplicating that task's
  /// data in two cards.
  Widget _buildTabletBody(
    BuildContext context, {
    required AppUser currentUser,
    required _Agenda allAgenda,
    required _Agenda agenda,
    required TaskModel? nextTask,
  }) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePaddingTablet,
        AppSpacing.md,
        AppSpacing.pagePaddingTablet,
        AppSpacing.xxl,
      ),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _DesktopHeaderCard(user: currentUser, today: _today, agenda: allAgenda),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 2, child: _NextTaskCard(task: nextTask)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
            const SizedBox(width: 10),
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
        const SizedBox(height: AppSpacing.md),
        _FiltersBar(
          catalog: context.watch<CatalogProvider>(),
          groupFilter: _groupFilter,
          userFilter: _userFilter,
          statusFilter: _statusFilter,
          clientController: _clientController,
          onGroupChanged: (v) => setState(() => _groupFilter = v),
          onUserChanged: (v) => setState(() => _userFilter = v),
          onStatusChanged: (v) => setState(() => _statusFilter = v),
          onClientChanged: (v) => setState(() => _clientQuery = v),
        ),
        const SizedBox(height: AppSpacing.lg),
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
        else ...[
          _SectionHeader(
            icon: LucideIcons.listTodo,
            title: 'Listado de órdenes para hoy',
            count: agenda.agendaToday.length,
          ),
          const SizedBox(height: 10),
          ..._buildAgendaRows(agenda),
        ],
      ],
    );
  }

  List<Widget> _buildSections(_Agenda agenda) {
    return [
      const _SectionHeader(
        icon: LucideIcons.listTodo,
        title: 'Agenda de hoy',
      ),
      const SizedBox(height: 10),
      ..._buildAgendaRows(agenda),
    ];
  }

  /// The task rows themselves (today's agenda + completed-today + overdue),
  /// without a leading section header — shared by [_buildSections] (mobile,
  /// prepends its own "Agenda de hoy" header) and [_buildTabletBody] (prepends
  /// "Listado de órdenes para hoy" instead, see below).
  List<Widget> _buildAgendaRows(_Agenda agenda) {
    return [
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
    if (_groupFilter == AppFilterValues.noGroup) {
      if (task.groupId != null) return false;
    } else if (_groupFilter != null && task.groupId != _groupFilter) {
      return false;
    }
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
/// real day regardless of the Equipo/Encargado/Cliente/Estado filters below.
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
/// the active Equipo/Encargado/Cliente/Estado filters — the underlying counts
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
    final typeColor =
        catalog.taskTypeById(task.taskTypeId)?.parsedColor ?? colors.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showTaskDetailDialog(context, task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          // Only the left side is visible (others default to BorderSide.none)
          // so this stays a single-visible-color border, same as
          // _CounterCard above it. A Border with two different *visible*
          // colors (e.g. adding colors.divider on the other 3 sides) plus a
          // borderRadius throws a FlutterError at paint time ("A borderRadius
          // can only be given on borders with uniform colors") — the
          // RenderObject's content never paints, while layout/hit-testing
          // (and thus tap-to-open-detail) are unaffected, which is exactly
          // the "card looks blank but is still tappable" Sprint 5.5 regression.
          border: Border(left: BorderSide(color: typeColor, width: 4)),
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
                      TaskTypeChip(
                        label: catalog.taskTypeName(task.taskTypeId),
                        color: typeColor,
                        dense: true,
                      ),
                      const SizedBox(height: 4),
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

/// Combinable "Equipo / Encargado / Estado / Cliente" filter row. Every
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
    this.singleRow = false,
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

  /// Desktop layout: all 4 fields on one row instead of a 2×2 grid — there's
  /// enough horizontal space and it saves a row of vertical space.
  final bool singleRow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final users = List.of(catalog.users)..sort((a, b) => a.name.compareTo(b.name));
    final groups = List.of(catalog.groups)..sort((a, b) => a.name.compareTo(b.name));
    final statuses = List.of(catalog.statuses)..sort((a, b) => a.name.compareTo(b.name));

    final groupField = _FilterDropdown<String>(
      label: 'Equipo',
      icon: LucideIcons.users,
      value: groupFilter,
      items: [
        const DropdownMenuItem(value: AppFilterValues.noGroup, child: Text('Sin equipo')),
        for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
      ],
      onChanged: onGroupChanged,
    );
    final userField = _FilterDropdown<String>(
      label: 'Encargado',
      icon: LucideIcons.userCheck,
      value: userFilter,
      items: [for (final u in users) DropdownMenuItem(value: u.id, child: Text(u.name))],
      onChanged: onUserChanged,
    );
    final statusField = _FilterDropdown<String>(
      label: 'Estado',
      icon: LucideIcons.listChecks,
      value: statusFilter,
      items: [for (final s in statuses) DropdownMenuItem(value: s.id, child: Text(s.name))],
      onChanged: onStatusChanged,
    );
    final clientField = TextField(
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
    );

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
          if (singleRow)
            Row(
              children: [
                Expanded(child: groupField),
                const SizedBox(width: 10),
                Expanded(child: userField),
                const SizedBox(width: 10),
                Expanded(child: statusField),
                const SizedBox(width: 10),
                Expanded(child: clientField),
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(child: groupField),
                const SizedBox(width: 10),
                Expanded(child: userField),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: statusField),
                const SizedBox(width: 10),
                Expanded(child: clientField),
              ],
            ),
          ],
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

// ── Desktop layout (Home redesign) ───────────────────────────────────────────
// Everything below is reached from [_HomePageState._buildDesktopBody]
// (context.isDesktop, ≥1024 px). [_DesktopHeaderCard] is also reused by
// [_HomePageState._buildTabletBody] (600–1023 px) — there, [nextTask] is
// left null, so only the header renders (tablet already shows the next task
// in its own [_NextTaskCard] row). Mobile keeps using [_HomeHeader],
// [_AgendaTaskTile], [_CompletedTodaySection] and [_OverdueSection] above,
// completely unchanged.

/// Wraps [_HomeHeader] in a bordered card so it reads as one of the desktop
/// panels instead of floating on the bare background — same treatment as
/// the filters bar and the agenda table below it. On desktop, also shows a
/// compact "Próxima tarea" strip ([_NextTaskStrip]) next to the header
/// instead of the old full-height vertical card that used to occupy the
/// whole right column — that column is now the inline task-creation form.
///
/// Uses a [LayoutBuilder] (not just `context.isDesktop`) to fall back to a
/// stacked layout below ~700px of *actual* available width, so a narrower
/// window/sidebar-expanded state or a zoomed-out browser never crushes the
/// header and the next-task fields into unreadable columns.
class _DesktopHeaderCard extends StatelessWidget {
  const _DesktopHeaderCard({
    required this.user,
    required this.today,
    required this.agenda,
    this.showNextTaskStrip = false,
    this.nextTask,
  });

  final AppUser user;
  final DateTime today;
  final _Agenda agenda;

  /// True only for the desktop call site — see class doc. Tablet leaves
  /// this false (default) since it already shows the next task in its own
  /// [_NextTaskCard] row.
  final bool showNextTaskStrip;

  final TaskModel? nextTask;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final header = _HomeHeader(user: user, today: today, agenda: agenda);

    Widget content = header;
    if (showNextTaskStrip) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final strip = _NextTaskStrip(task: nextTask);
          if (constraints.maxWidth >= 700) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 2, child: header),
                  const SizedBox(width: AppSpacing.lg),
                  VerticalDivider(width: 1, color: colors.divider),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 3, child: strip),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: colors.divider),
              const SizedBox(height: AppSpacing.md),
              strip,
            ],
          );
        },
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: content,
    );
  }
}

/// Compact horizontal "Próxima tarea" — the same task [_NextTaskCard] shows
/// on mobile, condensed into a row of small icon+label+value fields (via
/// [_MiniField]) instead of a tall vertical card, so it fits next to the
/// greeting header instead of needing its own column. Tapping anywhere on
/// the strip opens the same [showTaskDetailDialog] every other task tile in
/// the app uses (Editar/Reprogramar/Papelera live there); "Completar" stays
/// as an inline quick action for the single most common one — same
/// tap-for-detail + inline-quick-action pattern as [_AgendaTaskTile].
class _NextTaskStrip extends StatelessWidget {
  const _NextTaskStrip({required this.task});

  final TaskModel? task;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final task = this.task;

    if (task == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.checkCircle2, size: 20, color: colors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¡Todo en orden!',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'No tienes tareas pendientes por el momento.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final catalog = context.watch<CatalogProvider>();
    final formattedPhone = Validators.formatPhone(task.clientPhone);
    final typeColor = catalog.taskTypeById(task.taskTypeId)?.parsedColor ?? colors.primary;
    final isCompleted = task.statusId == catalog.completedStatusId;

    return InkWell(
      onTap: () => showTaskDetailDialog(context, task),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.star, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'PRÓXIMA TAREA',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 22,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MiniField(
                icon: LucideIcons.tag,
                label: 'Tipo',
                child: TaskTypeChip(
                  label: catalog.taskTypeName(task.taskTypeId),
                  color: typeColor,
                  dense: true,
                ),
              ),
              _MiniField(
                icon: LucideIcons.calendar,
                label: 'Fecha',
                value: AppDateUtils.formatShortDate(AppDateUtils.parseDateKey(task.date)),
              ),
              _MiniField(icon: LucideIcons.clock, label: 'Hora', value: task.hour),
              _MiniField(icon: LucideIcons.userCircle, label: 'Cliente', value: task.clientName),
              _MiniField(
                icon: LucideIcons.userCheck,
                label: 'Encargado',
                value: catalog.userName(task.assignedUserId),
              ),
              _MiniField(
                icon: LucideIcons.users,
                label: 'Equipo',
                value: catalog.groupName(task.groupId),
              ),
              _MiniField(
                icon: LucideIcons.phone,
                label: 'Teléfono',
                value: formattedPhone.isEmpty ? 'Sin teléfono' : formattedPhone,
              ),
              if (!isCompleted)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.success,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => completeTaskWithConfirm(context, task),
                  icon: const Icon(LucideIcons.checkCircle2, size: 16),
                  label: const Text('Completar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small icon + caption + value group used by [_NextTaskStrip]'s [Wrap] —
/// either [value] (plain text) or [child] (e.g. a [TaskTypeChip]) must be
/// given.
class _MiniField extends StatelessWidget {
  const _MiniField({required this.icon, required this.label, this.value, this.child})
      : assert(value != null || child != null);

  final IconData icon;
  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: colors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 2),
        child ??
            Text(
              value!,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      ],
    );
  }
}

/// Right-column panel: "Agenda de hoy" as a compact data table instead of
/// stacked cards — hour / cliente / contacto / encargado / estado columns
/// plus inline quick actions, so acting on a task never requires opening a
/// dialog first. Only this panel's task list scrolls (via the inner
/// `Expanded` + `ListView`); the header and column labels stay pinned.
class _DesktopAgendaPanel extends StatelessWidget {
  const _DesktopAgendaPanel({
    required this.allAgenda,
    required this.agenda,
    required this.completedExpanded,
    required this.onToggleCompleted,
  });

  final _Agenda allAgenda;
  final _Agenda agenda;
  final bool completedExpanded;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: _SectionHeader(
              icon: LucideIcons.listTodo,
              title: 'Agenda de hoy',
              count: agenda.agendaToday.length,
            ),
          ),
          if (allAgenda.isEmpty)
            const Expanded(
              child: EmptyState(
                message: 'No tienes tareas pendientes para hoy. ¡Buen trabajo!',
                icon: LucideIcons.checkCircle2,
              ),
            )
          else if (agenda.isEmpty)
            const Expanded(
              child: EmptyState(
                message: 'Ningún resultado coincide con los filtros seleccionados.',
                icon: LucideIcons.search,
              ),
            )
          else ...[
            if (agenda.agendaToday.isNotEmpty) ...[
              const _DesktopAgendaColumnHeader(),
              Divider(height: 1, color: colors.divider),
            ],
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  if (agenda.agendaToday.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      child: Text(
                        'No hay tareas pendientes ni reprogramadas para hoy.',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  else
                    for (final t in agenda.agendaToday) _DesktopAgendaRow(task: t),
                  if (agenda.completedToday.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DesktopCompletedTodaySection(
                      tasks: agenda.completedToday,
                      expanded: completedExpanded,
                      onToggle: onToggleCompleted,
                    ),
                  ],
                  if (agenda.overdue.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DesktopOverdueSection(tasks: agenda.overdue),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Column labels aligned with [_DesktopAgendaRow]'s fixed-width columns.
class _DesktopAgendaColumnHeader extends StatelessWidget {
  const _DesktopAgendaColumnHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: context.colors.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(width: _kDesktopColHour, child: Text('HORA', style: style)),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: Text('CLIENTE', style: style)),
          SizedBox(width: _kDesktopColContacto, child: Text('CONTACTO', style: style)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Text('ENCARGADO', style: style)),
          SizedBox(width: _kDesktopColEstado, child: Text('ESTADO', style: style)),
          SizedBox(width: _kDesktopColActions),
        ],
      ),
    );
  }
}

/// Desktop equivalent of [_AgendaTaskTile]: one spreadsheet-style row
/// (hour / cliente / contacto / encargado / estado) with inline quick-action
/// icons (Editar / Reprogramar / Completar / Papelera) so common actions
/// don't require opening the full detail dialog first. Tapping anywhere else
/// on the row still opens it, for anything not covered by the quick actions.
class _DesktopAgendaRow extends StatefulWidget {
  const _DesktopAgendaRow({
    required this.task,
    this.overrideChipColor,
    this.showDate = false,
  });

  final TaskModel task;
  final Color? overrideChipColor;
  final bool showDate;

  @override
  State<_DesktopAgendaRow> createState() => _DesktopAgendaRowState();
}

class _DesktopAgendaRowState extends State<_DesktopAgendaRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final task = widget.task;
    final statusName = catalog.statusName(task.statusId);
    final chipColor = widget.overrideChipColor ?? _statusChipColor(colors, statusName);
    final isCompleted = task.statusId == catalog.completedStatusId;
    final isPending = task.statusId == catalog.pendingStatusId;
    final typeColor = catalog.taskTypeById(task.taskTypeId)?.parsedColor ?? colors.primary;
    final canEdit = auth.isSuperAdmin || isPending;
    final formattedPhone = Validators.formatPhone(task.clientPhone);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showTaskDetailDialog(context, task),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? colors.primary.withValues(alpha: 0.05) : colors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: typeColor, width: 4)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _kDesktopColHour,
                child: Text(
                  task.hour,
                  style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.clientName,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (widget.showDate) ...[
                          Text(
                            AppDateUtils.formatShortDate(AppDateUtils.parseDateKey(task.date)),
                            style: TextStyle(color: colors.textSecondary, fontSize: 11),
                          ),
                          const SizedBox(width: 6),
                          Text('·', style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            catalog.taskTypeName(task.taskTypeId),
                            style: TextStyle(color: colors.textSecondary, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: _kDesktopColContacto,
                child: Text(
                  formattedPhone.isEmpty ? '—' : formattedPhone,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  catalog.userName(task.assignedUserId),
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: _kDesktopColEstado,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: chipColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      statusName,
                      style: TextStyle(color: chipColor, fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _kDesktopColActions,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (canEdit)
                      _RowIconAction(
                        icon: LucideIcons.pencil,
                        tooltip: 'Editar',
                        onPressed: () => openEditTaskFlow(context, task),
                      ),
                    if (!isCompleted)
                      _RowIconAction(
                        icon: LucideIcons.repeat,
                        tooltip: 'Reprogramar',
                        color: colors.statusRescheduled,
                        onPressed: () => showRescheduleDialog(context, task),
                      ),
                    if (!isCompleted)
                      _RowIconAction(
                        icon: LucideIcons.checkCircle2,
                        tooltip: 'Completar',
                        color: colors.success,
                        onPressed: () => completeTaskWithConfirm(context, task),
                      ),
                    _RowIconAction(
                      icon: LucideIcons.trash2,
                      tooltip: 'Papelera',
                      color: colors.error,
                      onPressed: () => sendTaskToTrashWithConfirm(context, task),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small icon-only quick action for [_DesktopAgendaRow].
class _RowIconAction extends StatelessWidget {
  const _RowIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16),
        color: color ?? context.colors.textSecondary,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 18,
      ),
    );
  }
}

/// Desktop variant of [_CompletedTodaySection] — same collapsible behavior,
/// rendering [_DesktopAgendaRow] instead of [_AgendaTaskTile] so it matches
/// the table styling of the section above it.
class _DesktopCompletedTodaySection extends StatelessWidget {
  const _DesktopCompletedTodaySection({
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
        color: context.colors.background,
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
              child: Column(children: [for (final t in tasks) _DesktopAgendaRow(task: t)]),
            ),
        ],
      ),
    );
  }
}

/// Desktop variant of [_OverdueSection] — same red-accent grouping, rendering
/// [_DesktopAgendaRow] (with [_DesktopAgendaRow.showDate] on, since these
/// tasks aren't from today) instead of [_AgendaTaskTile].
class _DesktopOverdueSection extends StatelessWidget {
  const _DesktopOverdueSection({required this.tasks});

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
          for (final t in tasks)
            _DesktopAgendaRow(task: t, overrideChipColor: colors.error, showDate: true),
        ],
      ),
    );
  }
}
