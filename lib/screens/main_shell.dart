import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_drawer.dart';
import 'calendar/calendar_page.dart';
import 'home/home_page.dart';
import 'profile/profile_page.dart';
import 'reports/reports_page.dart';
import 'week/week_page.dart';

/// Root authenticated shell: Drawer + BottomNavigationBar.
/// Tabs shown: Inicio, Calendario, Semana, Reportes (solo admin), Perfil.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['Inicio', 'Calendario', 'Semana', 'Reportes', 'Perfil'];

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isSuperAdmin;

    final pages = <Widget>[
      const HomePage(),
      const CalendarPage(),
      const WeekPage(),
      if (isAdmin) const ReportsPage(),
      const ProfilePage(),
    ];

    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Inicio'),
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
