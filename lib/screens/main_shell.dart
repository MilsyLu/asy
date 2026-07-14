import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/responsive/app_spacing.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/theme_colors.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../services/auth_service.dart';
import '../services/notification_repository.dart';
import '../widgets/app_drawer.dart';
import '../widgets/brand_logo.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/user_avatar.dart';
import 'admin/admin_panel_page.dart';
import '../widgets/update_banner.dart';
import 'admin/available_hours_page.dart';
import 'admin/groups_page.dart';
import 'admin/statuses_page.dart';
import 'admin/task_types_page.dart';
import 'admin/users_page.dart';
import 'calendar/calendar_page.dart';
import 'dashboard/dashboard_page.dart';
import 'home/home_page.dart';
import 'notifications/notifications_page.dart';
import 'profile/profile_page.dart';
import 'profile/settings_page.dart';
import 'reports/reports_page.dart';
import 'trash/trash_page.dart';
import 'week/week_page.dart';

// ── Navigation data model (single source of truth) ──────────────────────────

/// A desktop/tablet shell entry. Both primary tabs (sidebar section 1) and
/// secondary sections (sidebar section 2) are modelled with this class so
/// they all feed the same [IndexedStack] without any [Navigator.push].
class _ShellEntry {
  const _ShellEntry({
    required this.icon,
    required this.label,
    required this.page,
  });

  final IconData icon;
  final String label;
  final Widget page;
}

// ── Calendar view toggle (desktop/tablet only) ───────────────────────────────

enum _CalView { mes, semana }

/// Wraps [CalendarPage] and [WeekPage] in a single shell section.
///
/// A Material 3 [SegmentedButton] at the top lets the user switch between
/// the monthly calendar view and the weekly agenda view without leaving the
/// Calendario section. The last selected view is persisted to
/// [SharedPreferences] so it is restored on the next session.
class _CalendarSection extends StatefulWidget {
  const _CalendarSection();

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  _CalView _view = _CalView.mes;
  static const String _kPrefsKey = 'calendar_view';

  @override
  void initState() {
    super.initState();
    _loadView();
  }

  Future<void> _loadView() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefsKey);
    if (mounted && saved != null) {
      final v = _CalView.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => _CalView.mes,
      );
      setState(() => _view = v);
    }
  }

  Future<void> _setView(_CalView v) async {
    setState(() => _view = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, v.name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SegmentedButton<_CalView>(
                segments: const [
                  ButtonSegment(
                    value: _CalView.mes,
                    label: Text('Mes'),
                    icon: Icon(LucideIcons.calendar, size: 15),
                  ),
                  ButtonSegment(
                    value: _CalView.semana,
                    label: Text('Semana'),
                    icon: Icon(LucideIcons.calendarDays, size: 15),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => _setView(s.first),
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view == _CalView.mes ? 0 : 1,
            children: const [CalendarPage(), WeekPage()],
          ),
        ),
      ],
    );
  }
}

// ── Admin panel section (desktop/tablet only) ────────────────────────────────

/// Wraps [AdminPanelPage] and its five sub-modules in a single shell section.
///
/// Tapping a module card switches the central content area to that module
/// (with [showAppBar: false]) while the sidebar stays permanently visible.
/// A breadcrumb bar at the top lets the user navigate back to the hub without
/// any [Navigator.push].
class _AdminSection extends StatefulWidget {
  const _AdminSection();

  @override
  State<_AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends State<_AdminSection> {
  String? _subKey;

  @override
  Widget build(BuildContext context) {
    if (_subKey == null) {
      return AdminPanelPage(
        showAppBar: false,
        onModuleSelected: (key) => setState(() => _subKey = key),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdminBreadcrumb(
          subTitle: _subTitle(_subKey!),
          onBack: () => setState(() => _subKey = null),
        ),
        Expanded(child: _buildSubPage(_subKey!)),
      ],
    );
  }

  String _subTitle(String key) => switch (key) {
        'grupos' => 'Grupos',
        'tiposTarea' => 'Tipos de tarea',
        'estados' => 'Estados',
        'horarios' => 'Horarios disponibles',
        'usuarios' => 'Usuarios',
        _ => key,
      };

  Widget _buildSubPage(String key) => switch (key) {
        'grupos' => const GroupsPage(showAppBar: false),
        'tiposTarea' => const TaskTypesPage(showAppBar: false),
        'estados' => const StatusesPage(showAppBar: false),
        'horarios' => const AvailableHoursPage(showAppBar: false),
        'usuarios' => const UsersPage(showAppBar: false),
        _ => const SizedBox.shrink(),
      };
}

/// Breadcrumb bar rendered when a sub-module is active inside [_AdminSection].
/// Tapping anywhere on it returns to the [AdminPanelPage] hub.
class _AdminBreadcrumb extends StatelessWidget {
  const _AdminBreadcrumb({required this.subTitle, required this.onBack});

  final String subTitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onBack,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.arrowLeft, size: 16, color: colors.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Panel de administración',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(LucideIcons.chevronRight, size: 14, color: colors.textSecondary),
            ),
            Expanded(
              child: Text(
                subTitle,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── MainShell ────────────────────────────────────────────────────────────────

/// Root authenticated shell.
///
/// Mobile (< 600 px): AppBar + hamburger [AppDrawer] + [BottomNavigationBar].
/// Completely unchanged from Sprint 16.
///
/// Tablet (600–1023 px) + Desktop (≥ 1024 px): permanent collapsible
/// [_AppSidebar]. Every top-level module — tabs AND secondary sections
/// (Perfil, Agenda diaria, Panel de administración, Papelera, Configuración)
/// — lives inside a single [IndexedStack]. No [Navigator.push] for top-level
/// modules. The sidebar therefore never disappears during navigation. Collapse
/// state is persisted via [SharedPreferences].
///
/// Navigation items are defined once:
///   [_buildTabEntries]     → primary sidebar section + first portion of IndexedStack
///   [_buildSectionEntries] → secondary sidebar section + rest of IndexedStack
/// No parallel nav lists anywhere.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // ── Content-area nested Navigator controls ───────────────────────────────
  // Used only in the tablet/desktop sidebar layout. Null-safe: `.currentState`
  // is only non-null once the content area has been built.
  final _contentNavKey = GlobalKey<NavigatorState>();
  final _contentBaseKey = GlobalKey<_ContentBaseState>();

  /// Switches the shell to index [i]:
  ///   1. Pops any pushed pages back to the IndexedStack base route.
  ///   2. Tells [_ContentBase] to show child [i].
  ///   3. Rebuilds the outer scaffold to update the AppBar title.
  void _navigateToIndex(int i) {
    _contentNavKey.currentState?.popUntil((route) => route.isFirst);
    _contentBaseKey.currentState?.setIndex(i);
    setState(() => _index = i);
  }

  // Used only for mobile BottomNavigationBar title computation (unchanged).
  static const _mobileTitles = [
    'Dashboard',
    'Calendario',
    'Semana',
    'Reportes',
    'Perfil',
  ];

  // ── Single source of truth: primary tabs (sidebar section 1) ────────────
  // [0] Dashboard / Inicio
  // [1] Calendario  (_CalendarSection wraps CalendarPage + WeekPage toggle)
  // [2] Reportes    (admin only)
  List<_ShellEntry> _buildTabEntries(bool isAdmin) => [
        _ShellEntry(
          icon: isAdmin ? LucideIcons.gauge : LucideIcons.home,
          label: isAdmin ? 'Dashboard' : 'Inicio',
          page: isAdmin ? const DashboardPage() : const HomePage(),
        ),
        const _ShellEntry(
          icon: LucideIcons.calendar,
          label: 'Calendario',
          page: _CalendarSection(),
        ),
        if (isAdmin)
          const _ShellEntry(
            icon: LucideIcons.barChart3,
            label: 'Reportes',
            page: ReportsPage(),
          ),
      ];

  // ── Single source of truth: secondary sections (sidebar section 2) ──────
  // [0] Perfil                    — user-card tap only, not a nav item
  // [1] Agenda diaria             (admin only)
  // [2] Panel de administración   (admin only)
  // [3] Papelera                  (admin only)
  // [4 / 1] Configuración
  List<_ShellEntry> _buildSectionEntries(bool isAdmin) => [
        const _ShellEntry(
          icon: LucideIcons.user,
          label: 'Perfil',
          page: ProfilePage(),
        ),
        if (isAdmin) ...[
          const _ShellEntry(
            icon: LucideIcons.clipboardList,
            label: 'Agenda diaria',
            page: HomePage(),
          ),
          const _ShellEntry(
            icon: LucideIcons.layoutDashboard,
            label: 'Panel de administración',
            page: _AdminSection(),
          ),
          const _ShellEntry(
            icon: LucideIcons.trash2,
            label: 'Papelera',
            page: TrashPage(showAppBar: false),
          ),
        ],
        const _ShellEntry(
          icon: LucideIcons.settings,
          label: 'Configuración',
          page: SettingsPage(showAppBar: false),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isSuperAdmin;

    // ── Tablet + Desktop: permanent sidebar layout ───────────────────────
    if (!context.isMobile) {
      return _buildSidebarLayout(context, isAdmin);
    }

    // ── Mobile: UNCHANGED ────────────────────────────────────────────────
    final pages = <Widget>[
      isAdmin ? const DashboardPage() : const HomePage(),
      const CalendarPage(),
      const WeekPage(),
      if (isAdmin) const ReportsPage(),
      const ProfilePage(),
    ];

    final items = <BottomNavigationBarItem>[
      isAdmin
          ? const BottomNavigationBarItem(
              icon: Icon(LucideIcons.gauge), label: 'Dashboard')
          : const BottomNavigationBarItem(
              icon: Icon(LucideIcons.home), label: 'Inicio'),
      const BottomNavigationBarItem(
          icon: Icon(LucideIcons.calendar), label: 'Calendario'),
      const BottomNavigationBarItem(
          icon: Icon(LucideIcons.calendarDays), label: 'Semana'),
      if (isAdmin)
        const BottomNavigationBarItem(
            icon: Icon(LucideIcons.barChart3), label: 'Reportes'),
      const BottomNavigationBarItem(
          icon: Icon(LucideIcons.user), label: 'Perfil'),
    ];

    if (_index >= pages.length) _index = 0;

    final titleIndexOffset = isAdmin ? 0 : (_index >= 3 ? 1 : 0);
    final title = _index == 0
        ? AppConstants.appName
        : _mobileTitles[_index + titleIndexOffset];

    final stack = IndexedStack(index: _index, children: pages);
    return Scaffold(
      appBar: AppBar(
          title: Text(title), actions: const [_NotificationBellAction()]),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          const UpdateBanner(),
          Expanded(child: stack),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        items: items,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }

  Widget _buildSidebarLayout(BuildContext context, bool isAdmin) {
    final tabs = _buildTabEntries(isAdmin);
    final sections = _buildSectionEntries(isAdmin);
    final all = [...tabs, ...sections];

    if (_index >= all.length) _index = 0;

    // Index 0 shows the app name; every other section shows its own label.
    final String title;
    if (_index < tabs.length) {
      title = _index == 0 ? AppConstants.appName : tabs[_index].label;
    } else {
      title = sections[_index - tabs.length].label;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        actions: [_NotificationBellAction(contentNavKey: _contentNavKey)],
      ),
      body: Column(
        children: [
          const UpdateBanner(),
          Expanded(
            child: Row(
              children: [
                _AppSidebar(
                  selectedIndex: _index,
                  onTabSelected: _navigateToIndex,
                  tabEntries: tabs,
                  sectionEntries: sections,
                ),
                Expanded(
                  // Nested Navigator: every Navigator.push() call from within a
                  // content-area page (AddEditTaskPage, SettingsPage, etc.) lands
                  // here instead of the root Navigator, so the sidebar is never
                  // covered. onGenerateInitialRoutes is called only once at mount;
                  // subsequent index changes are driven by _contentBaseKey.
                  child: Navigator(
                    key: _contentNavKey,
                    onDidRemovePage: (_) {},
                    onGenerateInitialRoutes: (state, initialRouteName) {
                      final children = all.map((e) => e.page).toList();
                      return [
                        MaterialPageRoute<void>(
                          builder: (_) => _ContentBase(
                            key: _contentBaseKey,
                            index: _index,
                            children: children,
                          ),
                        ),
                      ];
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── _AppSidebar ──────────────────────────────────────────────────────────────

class _AppSidebar extends StatefulWidget {
  const _AppSidebar({
    required this.selectedIndex,
    required this.onTabSelected,
    required this.tabEntries,
    required this.sectionEntries,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final List<_ShellEntry> tabEntries;

  /// [sectionEntries[0]] is always Perfil (user-card access only, not rendered
  /// as a nav item). The remaining entries are shown in the secondary sidebar
  /// section after the divider.
  final List<_ShellEntry> sectionEntries;

  @override
  State<_AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<_AppSidebar> {
  bool _collapsed = false;

  static const double _kExpandedWidth = 220;
  static const double _kCollapsedWidth = AppLayout.navigationRailWidth; // 72
  static const String _kPrefsKey = 'sidebar_collapsed';

  @override
  void initState() {
    super.initState();
    _loadCollapsedState();
  }

  Future<void> _loadCollapsedState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _collapsed = prefs.getBool(_kPrefsKey) ?? false);
    }
  }

  Future<void> _toggleCollapsed() async {
    final next = !_collapsed;
    setState(() => _collapsed = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsKey, next);
  }

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Cerrar sesión',
      message: '¿Estás seguro que deseas cerrar sesión?',
      confirmLabel: 'Cerrar sesión',
      destructive: true,
      confirmForegroundColor: Colors.white,
    );
    if (confirm && context.mounted) {
      await context.read<AuthProvider>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final catalog = context.watch<CatalogProvider>();
    final user = auth.appUser;
    final colors = context.colors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _collapsed ? _kCollapsedWidth : _kExpandedWidth,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: logo + collapse toggle ───────────────────────────
          _buildHeader(colors),
          Divider(height: 1, thickness: 1, color: colors.divider),

          // ── User card → Perfil section ───────────────────────────────
          _buildUserCard(context, user, catalog, colors),
          Divider(height: 1, thickness: 1, color: colors.divider),

          // ── Navigation items (scrollable) ────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xs),

                  // Primary tab items (section 1)
                  ...widget.tabEntries.asMap().entries.map((e) {
                    return _SidebarNavItem(
                      icon: e.value.icon,
                      label: e.value.label,
                      collapsed: _collapsed,
                      selected: widget.selectedIndex == e.key,
                      onTap: () => widget.onTabSelected(e.key),
                    );
                  }),

                  // Secondary section items (section 2, skip Profile at [0])
                  if (widget.sectionEntries.length > 1) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Divider(height: 1, color: colors.divider),
                    ),
                    ...widget.sectionEntries.skip(1).toList().asMap().entries.map((e) {
                      // Profile is at sectionEntries[0], so visible items start at [1].
                      // Global index = tabEntries.length + 1 (skip profile) + e.key.
                      final globalIdx = widget.tabEntries.length + 1 + e.key;
                      return _SidebarNavItem(
                        icon: e.value.icon,
                        label: e.value.label,
                        collapsed: _collapsed,
                        selected: widget.selectedIndex == globalIdx,
                        onTap: () => widget.onTabSelected(globalIdx),
                      );
                    }),
                  ],

                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),

          // ── Footer: logout + version ─────────────────────────────────
          Divider(height: 1, thickness: 1, color: colors.divider),
          _SidebarNavItem(
            icon: LucideIcons.logOut,
            label: 'Cerrar sesión',
            collapsed: _collapsed,
            isDestructive: true,
            onTap: () => _signOut(context),
          ),
          if (!_collapsed)
            Padding(
              padding: const EdgeInsets.only(
                  bottom: AppSpacing.sm, top: AppSpacing.xs),
              child: Center(
                child: Text(
                  '${AppConstants.appName} v${AppConstants.appVersion}',
                  style: TextStyle(
                    color: colors.textSecondary.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildHeader(AppColorsExtension colors) {
    if (_collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(
          child: Tooltip(
            message: 'Expandir menú',
            child: IconButton(
              icon: Icon(LucideIcons.panelLeftOpen,
                  color: colors.textSecondary, size: 18),
              onPressed: _toggleCollapsed,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const BrandLogo(size: 32),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppConstants.appName,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'Contraer menú',
            child: IconButton(
              icon: Icon(LucideIcons.panelLeftClose,
                  color: colors.textSecondary, size: 18),
              onPressed: _toggleCollapsed,
              style: IconButton.styleFrom(
                  minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    AppUser? user,
    CatalogProvider catalog,
    AppColorsExtension colors,
  ) {
    // Navigate to the Perfil section (always at tabEntries.length + 0)
    // instead of pushing a new route over the sidebar.
    void goToProfile() {
      widget.onTabSelected(widget.tabEntries.length);
    }

    if (_collapsed) {
      return Tooltip(
        message: user?.name ?? 'Perfil',
        child: InkWell(
          onTap: goToProfile,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: user != null
                  ? UserAvatarDisplay(
                      user: user, size: 40, borderWidth: 1.5)
                  : Icon(LucideIcons.userCircle,
                      color: colors.primary, size: 40),
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: goToProfile,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                user != null
                    ? UserAvatarDisplay(
                        user: user, size: 52, borderWidth: 2)
                    : Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: colors.primary, width: 2),
                        ),
                        child: Icon(LucideIcons.userCircle,
                            color: colors.primary, size: 28),
                      ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user?.name ?? '',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _SidebarBadge(
                  icon: LucideIcons.userCheck,
                  label: AuthService.roleLabel(user?.role ?? ''),
                  colors: colors,
                ),
                if (user?.groupId != null)
                  _SidebarBadge(
                    icon: LucideIcons.users,
                    label: catalog.groupName(user?.groupId),
                    colors: colors,
                  ),
                _SidebarBadge(
                  icon: LucideIcons.flame,
                  label: '${user?.streakDays ?? 0} días racha',
                  colors: colors,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── _SidebarNavItem ──────────────────────────────────────────────────────────

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.selected = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final VoidCallback onTap;
  final bool selected;
  final bool isDestructive;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Color itemColor = widget.isDestructive
        ? colors.error
        : (widget.selected ? colors.primary : colors.textSecondary);

    final Color hoverBg = widget.isDestructive
        ? colors.error.withValues(alpha: 0.08)
        : colors.primary.withValues(alpha: 0.08);

    return Tooltip(
      message: widget.collapsed ? widget.label : '',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs, vertical: 1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.primary.withValues(alpha: 0.10)
                  : (_hovered ? hoverBg : Colors.transparent),
              borderRadius:
                  BorderRadius.circular(AppSpacing.radiusSm),
              border: widget.selected
                  ? Border.all(
                      color: colors.primary.withValues(alpha: 0.20))
                  : null,
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius:
                  BorderRadius.circular(AppSpacing.radiusSm),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.collapsed
                      ? AppSpacing.sm
                      : AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                child: Row(
                  mainAxisAlignment: widget.collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(widget.icon, color: itemColor, size: 20),
                    if (!widget.collapsed) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            color: itemColor,
                            fontSize: 13,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── _SidebarBadge ────────────────────────────────────────────────────────────

class _SidebarBadge extends StatelessWidget {
  const _SidebarBadge({
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: colors.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.primary),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: colors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}

// ── _ContentBase ─────────────────────────────────────────────────────────────

/// Base route widget for the desktop/tablet content [Navigator].
///
/// Contains the shell's [IndexedStack]. Because it lives inside the nested
/// content [Navigator], any [Navigator.push] call from a child page
/// (e.g. [AddEditTaskPage], [NotificationsPage]) is captured by that
/// Navigator, keeping the sidebar permanently visible.
///
/// The active [index] is updated at runtime via [_ContentBaseState.setIndex],
/// called through the [GlobalKey<_ContentBaseState>] in [_MainShellState].
class _ContentBase extends StatefulWidget {
  const _ContentBase({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_ContentBase> createState() => _ContentBaseState();
}

class _ContentBaseState extends State<_ContentBase> {
  late int _currentIndex = widget.index;

  void setIndex(int i) => setState(() => _currentIndex = i);

  @override
  Widget build(BuildContext context) {
    return IndexedStack(index: _currentIndex, children: widget.children);
  }
}

// ── _NotificationBellAction ──────────────────────────────────────────────────

/// AppBar bell action (Sprint 7.4): opens [NotificationsPage] and shows a
/// live unread-count badge sourced from [NotificationRepository.unreadCount].
///
/// On desktop/tablet the caller passes [contentNavKey] so the page is pushed
/// onto the content [Navigator], keeping the sidebar visible. On mobile
/// [contentNavKey] is null and the root Navigator is used instead.
class _NotificationBellAction extends StatelessWidget {
  const _NotificationBellAction({this.contentNavKey});

  final GlobalKey<NavigatorState>? contentNavKey;

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
          debugPrint(
              '[Notifications] unreadCount stream error: ${snapshot.error}');
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
            final navState = contentNavKey?.currentState;
            if (navState != null) {
              navState.push(
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
            }
          },
        );
      },
    );
  }
}
