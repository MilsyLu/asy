import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_manager.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_repository.dart';

/// "Configuración" screen (FASE 4): lets each user choose the app's
/// appearance (Seguir sistema / Modo claro / Modo oscuro) and accent
/// color (Dorado / Azul / Verde / Morado). Changes apply immediately via
/// [ThemeManager] and are persisted to the user's Firestore profile, so
/// each user keeps their own independent preferences.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = context.watch<ThemeManager>();
    final user = context.watch<AuthProvider>().appUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (user != null) ...[
            const _SectionTitle(
              icon: LucideIcons.bellRing,
              title: 'Notificaciones',
            ),
            const SizedBox(height: 4),
            _PushNotificationsOption(user: user),
            const SizedBox(height: 24),
          ],
          const _SectionTitle(icon: LucideIcons.sunMoon, title: 'Apariencia'),
          const SizedBox(height: 4),
          RadioGroup<ThemeMode>(
            groupValue: themeManager.themeMode,
            onChanged: (mode) {
              if (mode != null) context.read<ThemeManager>().setThemeMode(mode);
            },
            child: const Column(
              children: [
                _ThemeModeOption(
                  mode: ThemeMode.system,
                  label: 'Seguir sistema',
                  description: 'Usa el modo claro u oscuro del dispositivo.',
                  icon: LucideIcons.smartphone,
                ),
                _ThemeModeOption(
                  mode: ThemeMode.light,
                  label: 'Modo claro',
                  description: 'Fondo claro con texto oscuro.',
                  icon: LucideIcons.sun,
                ),
                _ThemeModeOption(
                  mode: ThemeMode.dark,
                  label: 'Modo oscuro',
                  description: 'Fondo oscuro con texto claro.',
                  icon: LucideIcons.moon,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(icon: LucideIcons.palette, title: 'Color principal'),
          const SizedBox(height: 4),
          RadioGroup<AppAccentColor>(
            groupValue: themeManager.accentColor,
            onChanged: (accent) {
              if (accent != null) context.read<ThemeManager>().setAccentColor(accent);
            },
            child: Column(
              children: [
                for (final accent in AppAccentColor.values) _AccentOption(accent: accent),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(icon: LucideIcons.eye, title: 'Vista previa'),
          const SizedBox(height: 8),
          const _ThemePreview(),
          const SizedBox(height: 24),
          const _SectionTitle(icon: LucideIcons.info, title: 'Acerca de'),
          const SizedBox(height: 8),
          const _AboutBlock(),
        ],
      ),
    );
  }
}

/// General toggle for every role (Sprint 7.4.8 Objetivo A/B — generalized
/// from the admin-only `_ReceiveTaskCreationPushOption` of Sprint 7.4.7):
/// controls whether this user gets an FCM push for any notification type.
/// The in-app `notifications` record (bell badge/counter/historial) is
/// always written server-side regardless of this preference — see
/// `functions/src/notifications.js` `sendNotificationToUser`.
class _PushNotificationsOption extends StatelessWidget {
  const _PushNotificationsOption({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(LucideIcons.bell),
      title: const Text('Recibir notificaciones push'),
      subtitle: const Text(
        'Las notificaciones seguirán apareciendo\n'
        'en el centro de notificaciones aunque\n'
        'los avisos push estén desactivados.',
      ),
      value: user.pushNotificationsEnabled,
      onChanged: (value) {
        context
            .read<UserRepository>()
            .updatePushNotificationsEnabled(user.id, value);
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.mode,
    required this.label,
    required this.description,
    required this.icon,
  });

  final ThemeMode mode;
  final String label;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ThemeMode>(
      value: mode,
      secondary: Icon(icon),
      title: Text(label),
      subtitle: Text(description),
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _AccentOption extends StatelessWidget {
  const _AccentOption({required this.accent});

  final AppAccentColor accent;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<AppAccentColor>(
      value: accent,
      secondary: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.swatch,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
      ),
      title: Text(accent.label),
      contentPadding: EdgeInsets.zero,
    );
  }
}

/// Live mock of the app's chrome (AppBar, buttons, switch, chip, FAB,
/// progress indicator) so the user sees the effect of their selection
/// before navigating away.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.appBarTheme.backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.layoutDashboard, color: theme.appBarTheme.iconTheme?.color),
                const SizedBox(width: 8),
                Text(AppConstants.appName, style: theme.appBarTheme.titleTextStyle),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Acción')),
              OutlinedButton(onPressed: () {}, child: const Text('Secundario')),
              TextButton(onPressed: () {}, child: const Text('Texto')),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
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

/// Branding block (Sprint 7.3.2A Parte 4): reuses this existing
/// "Configuración" screen instead of creating a separate "Acerca de" page.
class _AboutBlock extends StatelessWidget {
  const _AboutBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppConstants.appTagline,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            'Versión ${AppConstants.appVersion}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'Desarrollado por ${AppConstants.appDeveloper}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
