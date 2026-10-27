import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../providers/auth_provider.dart';
import 'available_hours_page.dart';
import 'clients_page.dart';
import 'developers_page.dart';
import 'groups_page.dart';
import 'statuses_page.dart';
import 'task_types_page.dart';
import 'users_page.dart';

/// Hub for admin management screens — every module is visible to
/// super_admin; a scoped admin_equipo only sees the ones matching their own
/// [AppPermissions] (Equipos→manageTeams, Tipos de tarea/Estados/Horarios→
/// manageCatalogs, Usuarios→manageUsers, Clientes→manageClients).
class AdminPanelPage extends StatelessWidget {
  const AdminPanelPage({
    super.key,
    this.showAppBar = true,
    this.onModuleSelected,
  });

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  /// When provided (desktop/tablet shell context), called with a string key
  /// instead of pushing a new route, so the sidebar remains visible.
  /// Keys: 'grupos' | 'tiposTarea' | 'estados' | 'horarios' | 'usuarios' | 'clientes'
  final void Function(String key)? onModuleSelected;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;
    final auth = context.watch<AuthProvider>();
    final hPad = isDesktop
        ? AppSpacing.pagePaddingDesktop
        : isTablet
        ? AppSpacing.pagePaddingTablet
        : AppSpacing.pagePaddingMobile;
    final crossAxisCount = isDesktop
        ? 3
        : isTablet
        ? 2
        : 1;

    final modules = adminModules(auth);

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
                // 240 px para un título, una línea y una flecha: la
                // tarjeta era casi toda espacio vacío. En horizontal, lo
                // mismo cabe en 84.
                mainAxisExtent: 84,
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
                      // Como ruta propia sí lleva su barra superior: no
                      // hay panel alrededor que la ponga.
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => module.builder(true)),
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
  final AdminModuleData data;
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
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
                    : Colors.black.withValues(alpha: 0.08),
                blurRadius: _hovered ? 14 : 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // En fila y no en columna: el icono a la izquierda, el texto al
          // medio y la flecha a la derecha. Antes el icono iba arriba
          // centrado, el texto debajo y la flecha al fondo, con todo el hueco
          // de por medio — una tarjeta de 240 px de alto para decir "Equipos"
          // y una línea más.
          child: Row(
            children: [
              AnimatedScale(
                scale: _hovered ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.data.icon, color: accent, size: 20),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      widget.data.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _hovered
                      ? accent.withValues(alpha: 0.25)
                      : accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.arrowRight, color: accent, size: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los módulos del Panel de administración.
///
/// Una sola lista, y de ahí salen las dos cosas que antes vivían separadas:
/// las tarjetas del panel y la pantalla que se abre al tocar una. El shell
/// tenía su propio `switch` por clave, y agregar "Equipo técnico" a esta
/// lista sin agregarlo allá hizo que el módulo abriera **en blanco**: el
/// `switch` caía en su caso por defecto, que devuelve un widget vacío, sin
/// error ni aviso de ninguna clase.
///
/// Ya no hay un segundo mapa que mantener: quien agregue un módulo aquí lo
/// agrega en todas partes.
List<AdminModuleData> adminModules(AuthProvider auth) => [
  AdminModuleData(
    icon: LucideIcons.users,
    title: 'Equipos',
    subtitle: 'Crear equipos y asignar trabajadores.',
    moduleKey: 'grupos',
    accentColor: const Color(0xFF43C97A),
    builder: (showAppBar) => GroupsPage(showAppBar: showAppBar),
    requiredPermission: AppPermissions.manageTeams,
  ),
  AdminModuleData(
    icon: LucideIcons.tag,
    title: 'Tipos de tarea',
    subtitle: 'Catálogo de tipos de tarea y colores.',
    moduleKey: 'tiposTarea',
    accentColor: const Color(0xFF4FA3F7),
    builder: (showAppBar) => TaskTypesPage(showAppBar: showAppBar),
    requiredPermission: AppPermissions.manageCatalogs,
  ),
  AdminModuleData(
    icon: LucideIcons.listChecks,
    title: 'Estados',
    subtitle: 'Estados disponibles para las tareas.',
    moduleKey: 'estados',
    accentColor: const Color(0xFFB388F5),
    builder: (showAppBar) => StatusesPage(showAppBar: showAppBar),
    requiredPermission: AppPermissions.manageCatalogs,
  ),
  AdminModuleData(
    icon: LucideIcons.clock,
    title: 'Horarios disponibles',
    subtitle: 'Horas habilitadas para agendar tareas.',
    moduleKey: 'horarios',
    accentColor: const Color(0xFFD4AF37),
    builder: (showAppBar) => AvailableHoursPage(showAppBar: showAppBar),
    requiredPermission: AppPermissions.manageCatalogs,
  ),
  AdminModuleData(
    icon: LucideIcons.settings,
    title: 'Usuarios',
    subtitle: 'Roles, equipos, contraseñas y dispositivos.',
    moduleKey: 'usuarios',
    accentColor: const Color(0xFF26C6DA),
    builder: (showAppBar) => UsersPage(showAppBar: showAppBar),
    requiredPermission: AppPermissions.manageUsers,
  ),
  AdminModuleData(
    icon: LucideIcons.contact,
    title: 'Clientes',
    subtitle: 'Ficha, teléfono e historial de cada cliente.',
    moduleKey: 'clientes',
    accentColor: const Color(0xFFE67E9C),
    builder: (showAppBar) => ClientsPage(showAppBar: showAppBar),
    requiredPermission: AppPermissions.manageClients,
  ),
  AdminModuleData(
    icon: LucideIcons.userCog,
    title: 'Equipo técnico',
    subtitle: 'A quién se le asignan los requerimientos.',
    moduleKey: 'desarrolladores',
    accentColor: const Color(0xFF7C5CD6),
    builder: (showAppBar) => DevelopersPage(showAppBar: showAppBar),
    requiredPermission: AppPermissions.manageRequirements,
  ),
].where((m) => auth.hasPermission(m.requiredPermission)).toList();

/// El módulo de esa clave, o `null` si no existe o el usuario no lo tiene.
AdminModuleData? adminModuleByKey(AuthProvider auth, String key) {
  for (final m in adminModules(auth)) {
    if (m.moduleKey == key) return m;
  }
  return null;
}

// ── Data ──────────────────────────────────────────────────────────────────────

class AdminModuleData {
  const AdminModuleData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.moduleKey,
    required this.accentColor,
    required this.builder,
    required this.requiredPermission,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String moduleKey;
  final Color accentColor;

  /// Construye la pantalla del módulo. Recibe si debe traer su propia barra
  /// superior: suelta la trae, embebida dentro del panel no — ahí el panel ya
  /// pone la suya con la miga de pan.
  final Widget Function(bool showAppBar) builder;

  /// One of [AppPermissions] — a super_admin always has every permission;
  /// a scoped admin_equipo only sees this module if it's on for them.
  final String requiredPermission;
}
