import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import 'available_hours_page.dart';
import 'groups_page.dart';
import 'statuses_page.dart';
import 'task_types_page.dart';
import 'users_page.dart';

/// Hub for super_admin-only management screens.
class AdminPanelPage extends StatelessWidget {
  const AdminPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <_AdminSectionData>[
      _AdminSectionData(
        icon: LucideIcons.users,
        title: 'Grupos',
        subtitle: 'Crear grupos y asignar trabajadores',
        builder: (_) => const GroupsPage(),
      ),
      _AdminSectionData(
        icon: LucideIcons.tag,
        title: 'Tipos de tarea',
        subtitle: 'Catálogo de tipos de tarea y colores',
        builder: (_) => const TaskTypesPage(),
      ),
      _AdminSectionData(
        icon: LucideIcons.listChecks,
        title: 'Estados',
        subtitle: 'Estados disponibles para las tareas',
        builder: (_) => const StatusesPage(),
      ),
      _AdminSectionData(
        icon: LucideIcons.clock,
        title: 'Horarios disponibles',
        subtitle: 'Horas habilitadas para agendar tareas',
        builder: (_) => const AvailableHoursPage(),
      ),
      _AdminSectionData(
        icon: LucideIcons.settings,
        title: 'Usuarios',
        subtitle: 'Roles, grupos, contraseñas y dispositivos',
        builder: (_) => const UsersPage(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Panel de administración')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final section = sections[index];
          return Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: section.builder),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                      ),
                      child: Icon(section.icon, color: AppColors.gold, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            section.subtitle,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight, color: AppColors.gold, size: 18),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AdminSectionData {
  const _AdminSectionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}
