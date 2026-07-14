import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import 'available_hours_page.dart';
import 'groups_page.dart';
import 'statuses_page.dart';
import 'task_types_page.dart';
import 'users_page.dart';

/// Hub for super_admin-only management screens.
class AdminPanelPage extends StatelessWidget {
  const AdminPanelPage({super.key, this.showAppBar = true, this.onModuleSelected});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  /// When provided (desktop/tablet shell context), called with a string key
  /// instead of pushing a new route, so the sidebar remains visible.
  /// Keys: 'grupos' | 'tiposTarea' | 'estados' | 'horarios' | 'usuarios'
  final void Function(String key)? onModuleSelected;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;
    final hPad = isDesktop
        ? AppSpacing.pagePaddingDesktop
        : isTablet
            ? AppSpacing.pagePaddingTablet
            : AppSpacing.pagePaddingMobile;
    final crossAxisCount = isDesktop ? 3 : isTablet ? 2 : 1;

    final modules = <_AdminModuleData>[
      _AdminModuleData(
        icon: LucideIcons.users,
        title: 'Grupos',
        subtitle: 'Crear grupos y asignar trabajadores.',
        moduleKey: 'grupos',
        accentColor: const Color(0xFF43C97A),
        builder: (_) => const GroupsPage(),
      ),
      _AdminModuleData(
        icon: LucideIcons.tag,
        title: 'Tipos de tarea',
        subtitle: 'Catálogo de tipos de tarea y colores.',
        moduleKey: 'tiposTarea',
        accentColor: const Color(0xFF4FA3F7),
        builder: (_) => const TaskTypesPage(),
      ),
      _AdminModuleData(
        icon: LucideIcons.listChecks,
        title: 'Estados',
        subtitle: 'Estados disponibles para las tareas.',
        moduleKey: 'estados',
        accentColor: const Color(0xFFB388F5),
        builder: (_) => const StatusesPage(),
      ),
      _AdminModuleData(
        icon: LucideIcons.clock,
        title: 'Horarios disponibles',
        subtitle: 'Horas habilitadas para agendar tareas.',
        moduleKey: 'horarios',
        accentColor: const Color(0xFFD4AF37),
        builder: (_) => const AvailableHoursPage(),
      ),
      _AdminModuleData(
        icon: LucideIcons.settings,
        title: 'Usuarios',
        subtitle: 'Roles, grupos, contraseñas y dispositivos.',
        moduleKey: 'usuarios',
        accentColor: const Color(0xFF26C6DA),
        builder: (_) => const UsersPage(),
      ),
    ];

    final body = SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          hPad,
          showAppBar ? AppSpacing.lg : AppSpacing.md,
          hPad,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAppBar) ...[
              const _AdminHeader(),
              const SizedBox(height: AppSpacing.lg),
            ],
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                mainAxisExtent: 240,
              ),
              itemCount: modules.length,
              itemBuilder: (context, index) {
                final module = modules[index];
                return _AdminModuleCard(
                  data: module,
                  onTap: () {
                    if (onModuleSelected != null) {
                      onModuleSelected!(module.moduleKey);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: module.builder),
                      );
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );

    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de administración')),
      body: body,
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _AdminHeader extends StatelessWidget {
  const _AdminHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Panel de administración',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Administra los catálogos y configuraciones principales de CheCu.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

// ── Module card ───────────────────────────────────────────────────────────────

class _AdminModuleCard extends StatefulWidget {
  const _AdminModuleCard({required this.data, required this.onTap});
  final _AdminModuleData data;
  final VoidCallback onTap;

  @override
  State<_AdminModuleCard> createState() => _AdminModuleCardState();
}

class _AdminModuleCardState extends State<_AdminModuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = widget.data.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: _hovered
                  ? accent.withValues(alpha: 0.45)
                  : colors.primary.withValues(alpha: 0.2),
              width: _hovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? accent.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.12),
                blurRadius: _hovered ? 20 : 4,
                spreadRadius: _hovered ? 2 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: AnimatedScale(
                  scale: _hovered ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.data.icon, color: accent, size: 28),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.data.title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.data.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _hovered
                        ? accent.withValues(alpha: 0.25)
                        : accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.arrowRight, color: accent, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _AdminModuleData {
  const _AdminModuleData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.moduleKey,
    required this.accentColor,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String moduleKey;
  final Color accentColor;
  final WidgetBuilder builder;
}
