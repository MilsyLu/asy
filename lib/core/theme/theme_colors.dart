import 'package:flutter/material.dart';

/// Accent color options available for user customization (FASE 2).
///
/// `gold` matches the original TaskFlow Executive palette exactly, so it
/// remains the default for all users and preserves the historical look.
enum AppAccentColor {
  gold,
  blue,
  green,
  purple;

  /// Spanish display label shown in the preferences screen.
  String get label {
    switch (this) {
      case AppAccentColor.gold:
        return 'Dorado';
      case AppAccentColor.blue:
        return 'Azul';
      case AppAccentColor.green:
        return 'Verde';
      case AppAccentColor.purple:
        return 'Morado';
    }
  }

  /// Representative swatch color used by the color picker preview.
  Color get swatch {
    switch (this) {
      case AppAccentColor.gold:
        return const Color(0xFFD4AF37);
      case AppAccentColor.blue:
        return const Color(0xFF4FA3F7);
      case AppAccentColor.green:
        return const Color(0xFF43C97A);
      case AppAccentColor.purple:
        return const Color(0xFFB388F5);
    }
  }

  /// Value persisted in `users/{uid}.accentColor`.
  String get storageValue => name;

  /// Parses a Firestore value, defaulting to [gold] for legacy/unknown values.
  static AppAccentColor fromStorage(String? value) {
    return AppAccentColor.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AppAccentColor.gold,
    );
  }
}

/// Full color palette for a given accent + brightness combination.
///
/// This is the single source of truth consumed by [AppTheme.themeFor] to
/// build a [ThemeData]. `forAccent(gold, dark)` reproduces the exact values
/// previously hardcoded in `AppColors`, so the default configuration looks
/// identical to the original always-dark theme.
class ThemeColors {
  const ThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.primary,
    required this.primaryLight,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color primary;
  final Color primaryLight;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;
  final Color divider;

  /// Returns the palette for [accent] + [brightness].
  static ThemeColors forAccent(AppAccentColor accent, Brightness brightness) {
    final palettes = brightness == Brightness.dark ? _dark : _light;
    return palettes[accent]!;
  }

  static const Map<AppAccentColor, ThemeColors> _dark = {
    AppAccentColor.gold: ThemeColors(
      background: Color(0xFF0A0A0A),
      surface: Color(0xFF1A1A1A),
      surfaceVariant: Color(0xFF222222),
      primary: Color(0xFFD4AF37),
      primaryLight: Color(0xFFE4C568),
      onPrimary: Color(0xFF0A0A0A),
      textPrimary: Color(0xFFF5F5F5),
      textSecondary: Color(0xFFB0B0B0),
      error: Color(0xFFCF6679),
      success: Color(0xFF4CAF50),
      divider: Color(0x33D4AF37),
    ),
    AppAccentColor.blue: ThemeColors(
      background: Color(0xFF0A0A0A),
      surface: Color(0xFF1A1A1A),
      surfaceVariant: Color(0xFF222222),
      primary: Color(0xFF4FA3F7),
      primaryLight: Color(0xFF8AC4FB),
      onPrimary: Color(0xFF0A0A0A),
      textPrimary: Color(0xFFF5F5F5),
      textSecondary: Color(0xFFB0B0B0),
      error: Color(0xFFCF6679),
      success: Color(0xFF4CAF50),
      divider: Color(0x334FA3F7),
    ),
    AppAccentColor.green: ThemeColors(
      background: Color(0xFF0A0A0A),
      surface: Color(0xFF1A1A1A),
      surfaceVariant: Color(0xFF222222),
      primary: Color(0xFF43C97A),
      primaryLight: Color(0xFF8FE6B4),
      onPrimary: Color(0xFF0A0A0A),
      textPrimary: Color(0xFFF5F5F5),
      textSecondary: Color(0xFFB0B0B0),
      error: Color(0xFFCF6679),
      success: Color(0xFF4CAF50),
      divider: Color(0x3343C97A),
    ),
    AppAccentColor.purple: ThemeColors(
      background: Color(0xFF0A0A0A),
      surface: Color(0xFF1A1A1A),
      surfaceVariant: Color(0xFF222222),
      primary: Color(0xFFB388F5),
      primaryLight: Color(0xFFD2B8FF),
      onPrimary: Color(0xFF0A0A0A),
      textPrimary: Color(0xFFF5F5F5),
      textSecondary: Color(0xFFB0B0B0),
      error: Color(0xFFCF6679),
      success: Color(0xFF4CAF50),
      divider: Color(0x33B388F5),
    ),
  };

  /// Builds the [AppColorsExtension] registered on [ThemeData] for this
  /// palette (see [AppTheme.themeFor]).
  AppColorsExtension toExtension() => AppColorsExtension(
        background: background,
        surface: surface,
        surfaceVariant: surfaceVariant,
        primary: primary,
        primaryLight: primaryLight,
        onPrimary: onPrimary,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        error: error,
        success: success,
        divider: divider,
      );

  static const Map<AppAccentColor, ThemeColors> _light = {
    AppAccentColor.gold: ThemeColors(
      background: Color(0xFFF5F5F5),
      surface: Color(0xFFFFFFFF),
      surfaceVariant: Color(0xFFECECEC),
      primary: Color(0xFFB8860B),
      primaryLight: Color(0xFFD4AF37),
      onPrimary: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1A1A1A),
      textSecondary: Color(0xFF5C5C5C),
      error: Color(0xFFC62828),
      success: Color(0xFF2E7D32),
      divider: Color(0x33B8860B),
    ),
    AppAccentColor.blue: ThemeColors(
      background: Color(0xFFF5F5F5),
      surface: Color(0xFFFFFFFF),
      surfaceVariant: Color(0xFFECECEC),
      primary: Color(0xFF1565C0),
      primaryLight: Color(0xFF4FA3F7),
      onPrimary: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1A1A1A),
      textSecondary: Color(0xFF5C5C5C),
      error: Color(0xFFC62828),
      success: Color(0xFF2E7D32),
      divider: Color(0x331565C0),
    ),
    AppAccentColor.green: ThemeColors(
      background: Color(0xFFF5F5F5),
      surface: Color(0xFFFFFFFF),
      surfaceVariant: Color(0xFFECECEC),
      primary: Color(0xFF2E7D32),
      primaryLight: Color(0xFF4CAF50),
      onPrimary: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1A1A1A),
      textSecondary: Color(0xFF5C5C5C),
      error: Color(0xFFC62828),
      success: Color(0xFF2E7D32),
      divider: Color(0x332E7D32),
    ),
    AppAccentColor.purple: ThemeColors(
      background: Color(0xFFF5F5F5),
      surface: Color(0xFFFFFFFF),
      surfaceVariant: Color(0xFFECECEC),
      primary: Color(0xFF7E3FF2),
      primaryLight: Color(0xFFB388F5),
      onPrimary: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1A1A1A),
      textSecondary: Color(0xFF5C5C5C),
      error: Color(0xFFC62828),
      success: Color(0xFF2E7D32),
      divider: Color(0x337E3FF2),
    ),
  };
}

/// [ThemeData] extension exposing [ThemeColors] to every widget via
/// `Theme.of(context)`.
///
/// This is the single source of truth for "raw" colors that don't map
/// cleanly onto [ColorScheme] (e.g. [surfaceVariant], [success],
/// [textSecondary]). Widgets should read colors through this extension (via
/// the [AppColorsContext.colors] getter) instead of the legacy `AppColors`
/// constants, so every color automatically follows the user's selected
/// accent color and light/dark mode.
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  const AppColorsExtension({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.primary,
    required this.primaryLight,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color primary;
  final Color primaryLight;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;
  final Color divider;

  @override
  AppColorsExtension copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? primary,
    Color? primaryLight,
    Color? onPrimary,
    Color? textPrimary,
    Color? textSecondary,
    Color? error,
    Color? success,
    Color? divider,
  }) {
    return AppColorsExtension(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      onPrimary: onPrimary ?? this.onPrimary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      error: error ?? this.error,
      success: success ?? this.success,
      divider: divider ?? this.divider,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

/// Convenience accessor for [AppColorsExtension] on any [BuildContext].
///
/// Usage: `context.colors.primary`, `context.colors.surface`, etc. Reacts
/// to theme changes the same way `Theme.of(context)` does.
extension AppColorsContext on BuildContext {
  AppColorsExtension get colors =>
      Theme.of(this).extension<AppColorsExtension>()!;
}
