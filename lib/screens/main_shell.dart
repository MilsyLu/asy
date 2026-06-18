import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../services/notification_service.dart';
import '../services/task_repository.dart';
import '../widgets/app_drawer.dart';
import 'calendar/calendar_page.dart';
import 'dashboard/dashboard_page.dart';
import 'home/home_page.dart';
import 'profile/profile_page.dart';
import 'reports/reports_page.dart';
import 'week/week_page.dart';

/// Root authenticated shell: Drawer + BottomNavigationBar.
///
/// Tabs shown (Sprint 6.2):
/// - Trabajador: Inicio, Calendario, Semana, Perfil — unchanged.
/// - Administrador: Dashboard (replaces Inicio), Calendario, Semana,
///   Reportes, Perfil. The old Inicio screen ([HomePage]) is not removed —
///   it's still reachable for admins as "Agenda diaria" from [AppDrawer].
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _startupRemindersDone = false;

  static const _titles = ['Dashboard', 'Calendario', 'Semana', 'Reportes', 'Perfil'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startupRemindersDone) {
      _startupRemindersDone = true;
      _scheduleUpcomingReminders();
    }
  }

  /// Re-schedules local reminder notifications for the current user's upcoming
  /// tasks. Runs once after login so reminders survive app restarts and updates.
  Future<void> _scheduleUpcomingReminders() async {
    try {
      final auth = context.read<AuthProvider>();
      final currentUserId = auth.appUser?.id;
      if (currentUserId == null) return;

      final repo = context.read<TaskRepository>();
      final catalog = context.read<CatalogProvider>();
      final now = DateTime.now();
      final tasks = await repo.getTasksInRange(
        now,
        now.add(const Duration(days: 60)),
      );

      for (final task in tasks) {
        if (task.assignedUserId != currentUserId) continue;
        final reminder = task.reminderTime;
        if (reminder == null || reminder.isBefore(now)) continue;
        await NotificationService.instance.scheduleReminder(
          taskId: task.id,
          clientName: task.clientName,
          taskTypeName: catalog.taskTypeName(task.taskTypeId),
          taskHour: task.hour,
          reminderTime: reminder,
        );
      }
    } catch (e) {
      debugPrint('Startup reminder rebuild failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isSuperAdmin;

    final pages = <Widget>[
      isAdmin ? const DashboardPage() : const HomePage(),
      const CalendarPage(),
      const WeekPage(),
      if (isAdmin) const ReportsPage(),
      const ProfilePage(),
    ];

    final items = <BottomNavigationBarItem>[
      isAdmin
          ? const BottomNavigationBarItem(icon: Icon(LucideIcons.gauge), label: 'Dashboard')
          : const BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Inicio'),
      const BottomNavigationBarItem(icon: Icon(LucideIcons.calendar), label: 'Calendario'),
      const BottomNavigationBarItem(icon: Icon(LucideIcons.calendarDays), label: 'Semana'),
      if (isAdmin)
        const BottomNavigationBarItem(icon: Icon(LucideIcons.barChart3), label: 'Reportes'),
      const BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Perfil'),
    ];

    if (_index >= pages.length) _index = 0;

    final titleIndexOffset = isAdmin ? 0 : (_index >= 3 ? 1 : 0);
    final title = _index == 0
        ? AppConstants.appName
        : _titles[_index + titleIndexOffset];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: const AppDrawer(),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        items: items,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
