import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../services/notification_repository.dart';
import '../widgets/app_drawer.dart';
import 'calendar/calendar_page.dart';
import 'dashboard/dashboard_page.dart';
import 'home/home_page.dart';
import 'notifications/notifications_page.dart';
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

  static const _titles = ['Dashboard', 'Calendario', 'Semana', 'Reportes', 'Perfil'];

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
      appBar: AppBar(title: Text(title), actions: const [_NotificationBellAction()]),
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

/// AppBar bell action (Sprint 7.4): opens [NotificationsPage] as a normal
/// pushed route and shows a live unread-count badge sourced from
/// [NotificationRepository.unreadCount].
class _NotificationBellAction extends StatelessWidget {
  const _NotificationBellAction();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NotificationRepository>();
    final userId = context.watch<AuthProvider>().appUser?.id;
    if (userId == null) return const SizedBox.shrink();

    return StreamBuilder<int>(
      stream: repo.unreadCount(userId),
      builder: (context, snapshot) {
        // Sprint 7.4.1: a permission/index error here must not be silently
        // swallowed as "0 unread" — that's indistinguishable from a healthy
        // empty state and was hiding exactly the kind of bug Sprint 7.4.1
        // set out to find (push arrives, bell shows nothing).
        if (snapshot.hasError) {
          debugPrint('[Notifications] unreadCount stream error: ${snapshot.error}');
        }
        final count = snapshot.data ?? 0;
        return IconButton(
          icon: Badge(
            label: Text(count > 9 ? '9+' : '$count'),
            isLabelVisible: count > 0,
            backgroundColor: Theme.of(context).colorScheme.error,
            child: const Icon(LucideIcons.bell),
          ),
          tooltip: 'Notificaciones',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
        );
      },
    );
  }
}
