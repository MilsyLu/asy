import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_manager.dart';
import '../../models/app_user.dart';
import '../../models/system_config_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/system_config_provider.dart';
import '../../services/user_repository.dart';

/// "Configuración" screen (Sprint 19 UX redesign): modern two-column
/// preference hub on desktop, single column on tablet/mobile.
/// All persistence logic is identical: ThemeManager.setThemeMode(),
/// ThemeManager.setAccentColor(), UserRepository.updatePushNotificationMode().
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final themeManager = context.watch<ThemeManager>();
    final user = context.watch<AuthProvider>().appUser;
    final isDesktop = context.isDesktop;
    final hPad = isDesktop
        ? AppSpacing.pagePaddingDesktop
        : context.isTablet
            ? AppSpacing.pagePaddingTablet
            : AppSpacing.pagePaddingMobile;

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
              const _SettingsHeader(),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _MainPrefsColumn(themeManager: themeManager, user: user),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    flex: 2,
                    child: _SidePanelColumn(),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MainPrefsColumn(themeManager: themeManager, user: user),
                  const SizedBox(height: AppSpacing.md),
                  _SidePanelColumn(),
                ],
              ),
          ],
        ),
      ),
    );

    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: body,
    );
  }
}

// ── Page header ───────────────────────────────────────────────────────────────

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configuración',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Personaliza la experiencia de CheCu según tus preferencias.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

// ── Two-column layout pieces ──────────────────────────────────────────────────

class _MainPrefsColumn extends StatelessWidget {
  const _MainPrefsColumn({required this.themeManager, required this.user});

  final ThemeManager themeManager;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (user != null) ...[
          _NotificationsSection(user: user!),
          const SizedBox(height: AppSpacing.md),
        ],
        if (user != null && user!.isSuperAdmin) ...[
          const _AgendaSection(),
          const SizedBox(height: AppSpacing.md),
        ],
        _AppearanceSection(themeManager: themeManager),
        const SizedBox(height: AppSpacing.md),
        _AccentColorSection(themeManager: themeManager),
      ],
    );
  }
}

class _SidePanelColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _ThemePreviewCard(),
        SizedBox(height: AppSpacing.md),
        _AboutCard(),
        SizedBox(height: AppSpacing.md),
        _TipsCard(),
      ],
    );
  }
}

// ── Shared preference card shell ──────────────────────────────────────────────

class _PrefCard extends StatelessWidget {
  const _PrefCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primary, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

// ── Notifications section ─────────────────────────────────────────────────────

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.isSuperAdmin;
    final current = user.pushNotificationMode;

    void pick(String mode) =>
        context.read<UserRepository>().updatePushNotificationMode(user.id, mode);

    return _PrefCard(
      icon: LucideIcons.bellRing,
      title: 'Notificaciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotifRow(
            icon: LucideIcons.bellRing,
            label: 'Todas las notificaciones',
            description: 'Recibe alertas de todas las tareas.',
            selected: current == AppPushNotificationModes.all,
            onTap: () => pick(AppPushNotificationModes.all),
          ),
          if (isAdmin) ...[
            const SizedBox(height: AppSpacing.xs),
            _NotifRow(
              icon: LucideIcons.users,
              label: 'Solo tareas de mi grupo',
              description: 'Solo notificaciones del grupo asignado.',
              selected: current == AppPushNotificationModes.groupOnly,
              onTap: () => pick(AppPushNotificationModes.groupOnly),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          _NotifRow(
            icon: LucideIcons.userCheck,
            label: 'Solo tareas asignadas',
            description: 'Solo las tareas directamente asignadas a ti.',
            selected: current == AppPushNotificationModes.assignedOnly,
            onTap: () => pick(AppPushNotificationModes.assignedOnly),
          ),
          const SizedBox(height: AppSpacing.xs),
          _NotifRow(
            icon: LucideIcons.bellOff,
            label: 'No recibir notificaciones push',
            description: 'Las alertas del centro de notificaciones siguen activas.',
            selected: current == AppPushNotificationModes.none,
            onTap: () => pick(AppPushNotificationModes.none),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Las notificaciones seguirán apareciendo en el centro aunque '
            'elijas "No recibir notificaciones push".',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  const _NotifRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colors.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? colors.primary : colors.textSecondary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.onPrimary,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Agenda section (super_admin only) ────────────────────────────────────────

class _AgendaSection extends StatelessWidget {
  const _AgendaSection();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<SystemConfigProvider>();
    final current = config.config.timeSelectionMode;

    return _PrefCard(
      icon: LucideIcons.clock,
      title: 'Agenda',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Modo de selección de hora',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _NotifRow(
            icon: LucideIcons.listChecks,
            label: 'Usar horarios configurados',
            description: 'Solo las horas del catálogo de administración.',
            selected: current == SystemConfigModel.modeCatalog,
            onTap: () => config.setTimeSelectionMode(SystemConfigModel.modeCatalog),
          ),
          const SizedBox(height: AppSpacing.xs),
          _NotifRow(
            icon: LucideIcons.clock,
            label: 'Permitir cualquier hora',
            description: 'El usuario elige la hora libremente con un selector.',
            selected: current == SystemConfigModel.modeFree,
            onTap: () => config.setTimeSelectionMode(SystemConfigModel.modeFree),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Este ajuste aplica a toda la aplicación en todos los dispositivos.',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Appearance section ────────────────────────────────────────────────────────

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.themeManager});

  final ThemeManager themeManager;

  @override
  Widget build(BuildContext context) {
    return _PrefCard(
      icon: LucideIcons.sunMoon,
      title: 'Apariencia',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ThemeModeCard(
              icon: LucideIcons.smartphone,
              label: 'Seguir sistema',
              description: 'Modo del dispositivo',
              selected: themeManager.themeMode == ThemeMode.system,
              onTap: () => context.read<ThemeManager>().setThemeMode(ThemeMode.system),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ThemeModeCard(
              icon: LucideIcons.sun,
              label: 'Modo claro',
              description: 'Fondo claro',
              selected: themeManager.themeMode == ThemeMode.light,
              onTap: () => context.read<ThemeManager>().setThemeMode(ThemeMode.light),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ThemeModeCard(
              icon: LucideIcons.moon,
              label: 'Modo oscuro',
              description: 'Fondo oscuro',
              selected: themeManager.themeMode == ThemeMode.dark,
              onTap: () => context.read<ThemeManager>().setThemeMode(ThemeMode.dark),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.08)
                : colors.background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: selected ? colors.primary : colors.divider,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Check indicator aligned to top-right
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedOpacity(
                    opacity: selected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary,
                      ),
                      child: Icon(
                        LucideIcons.check,
                        size: 9,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Icon(
                icon,
                size: 22,
                color: selected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? colors.textPrimary : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Accent color section ──────────────────────────────────────────────────────

class _AccentColorSection extends StatelessWidget {
  const _AccentColorSection({required this.themeManager});

  final ThemeManager themeManager;

  @override
  Widget build(BuildContext context) {
    return _PrefCard(
      icon: LucideIcons.palette,
      title: 'Color principal',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final accent in AppAccentColor.values)
            _AccentChip(
              accent: accent,
              selected: themeManager.accentColor == accent,
              onTap: () => context.read<ThemeManager>().setAccentColor(accent),
            ),
        ],
      ),
    );
  }
}

class _AccentChip extends StatelessWidget {
  const _AccentChip({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppAccentColor accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? accent.swatch.withValues(alpha: 0.12)
              : colors.background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: selected ? accent.swatch : colors.divider,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.swatch,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              accent.label,
              style: TextStyle(
                color: selected ? colors.textPrimary : colors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(LucideIcons.check, size: 12, color: accent.swatch),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Theme preview card ────────────────────────────────────────────────────────

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.eye, color: colors.primary, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Vista previa',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Mini AppBar mock
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: theme.appBarTheme.backgroundColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.layoutDashboard,
                  color: theme.appBarTheme.iconTheme?.color,
                  size: 15,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppConstants.appName,
                  style: theme.appBarTheme.titleTextStyle?.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Acción')),
              OutlinedButton(onPressed: () {}, child: const Text('Ver')),
              TextButton(onPressed: () {}, child: const Text('Cancelar')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Switch(value: true, onChanged: (_) {}),
              const Chip(label: Text('Etiqueta')),
              FloatingActionButton.small(
                onPressed: () {},
                child: const Icon(LucideIcons.plus),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── About card ────────────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, color: colors.primary, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Acerca de',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppConstants.appTagline,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.sm),
          _AboutRow(label: 'Versión', value: AppConstants.appVersion),
          const SizedBox(height: 2),
          _AboutRow(label: 'Desarrollado por', value: AppConstants.appDeveloper),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$label: ',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Tips card ─────────────────────────────────────────────────────────────────

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  static const _tips = [
    'Los cambios se aplican automáticamente.',
    'No necesitas guardar ni reiniciar la aplicación.',
    'Tus preferencias se sincronizan en todos tus dispositivos.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, color: colors.primary, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Consejos',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (int i = 0; i < _tips.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _tips[i],
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (i < _tips.length - 1) const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}
