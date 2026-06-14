import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/theme_manager.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
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
        ],
      ),
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
                Text('TaskFlow Executive', style: theme.appBarTheme.titleTextStyle),
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
