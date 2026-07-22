import 'package:flutter/material.dart';

/// Default accent color (the original TaskFlow Executive gold), used when a
/// user has no stored preference yet.
const Color kDefaultAccentColor = Color(0xFFD4AF37);

/// Preset names written to `users/{uid}.accentColor` before the accent
/// picker became a full color wheel (FASE 2) — mapped to their exact
/// original hex so users who had picked one of these keep looking the same
/// after that change.
const Map<String, Color> _legacyAccentPresets = {
  'gold': kDefaultAccentColor,
  'blue': Color(0xFF4FA3F7),
  'green': Color(0xFF43C97A),
  'purple': Color(0xFFB388F5),
};

/// Parses a persisted `users/{uid}.accentColor` value into a [Color].
/// Accepts a "#RRGGBB" hex string (the current format, chosen via the full
/// color-wheel picker) or one of the legacy preset names above.
Color accentColorFromStorage(String? value) {
  if (value == null) return kDefaultAccentColor;
  final legacy = _legacyAccentPresets[value];
  if (legacy != null) return legacy;
  final cleaned = value.replaceFirst('#', '');
  final parsed = int.tryParse('FF$cleaned', radix: 16);
  return parsed != null ? Color(parsed) : kDefaultAccentColor;
}

/// Serializes a [Color] for storage as `users/{uid}.accentColor`.
String accentColorToStorage(Color color) {
  String channel(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}'.toUpperCase();
}

/// Full color palette for a given accent + brightness combination.
///
/// This is the single source of truth consumed by [AppTheme.themeFor] to
/// build a [ThemeData]. `forColor(kDefaultAccentColor, dark)` reproduces the
/// exact values previously hardcoded in `AppColors`, so the default
/// configuration looks identical to the original always-dark theme.
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
    required this.statusPending,
    required this.statusRescheduled,
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

  /// Soft amber used for the "Pendiente" status (FASE 3B). Fixed across
  /// accent colors, like [error]/[success], and only varies by brightness.
  final Color statusPending;

  /// Soft blue used for the "Reprogramada" status (FASE 3B). Fixed across
  /// accent colors, like [error]/[success], and only varies by brightness.
  final Color statusRescheduled;

  /// Fixed (brightness-only) palette values — identical for every accent
  /// color, so a custom [primary] only needs to override [primary]/
  /// [primaryLight]/[onPrimary]/[divider] below.
  static const _darkFixed = ThemeColors(
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF1A1A1A),
    surfaceVariant: Color(0xFF222222),
    primary: kDefaultAccentColor, // overridden by forColor
    primaryLight: kDefaultAccentColor, // overridden by forColor
    onPrimary: Color(0xFF0A0A0A), // overridden by forColor
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFB0B0B0),
    error: Color(0xFFCF6679),
    success: Color(0xFF4CAF50),
    divider: Color(0x33D4AF37), // overridden by forColor
    statusPending: Color(0xFFFFC107),
    statusRescheduled: Color(0xFF64B5F6),
  );

  static const _lightFixed = ThemeColors(
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFECECEC),
    primary: kDefaultAccentColor, // overridden by forColor
    primaryLight: kDefaultAccentColor, // overridden by forColor
    onPrimary: Color(0xFFFFFFFF), // overridden by forColor
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF5C5C5C),
    error: Color(0xFFC62828),
    success: Color(0xFF2E7D32),
    divider: Color(0x33B8860B), // overridden by forColor
    statusPending: Color(0xFFFF8F00),
    statusRescheduled: Color(0xFF1976D2),
  );

  /// Builds the palette for an arbitrary [primary] accent color (chosen via
  /// the full color-wheel picker in Configuración) + [brightness]. Every
  /// field except primary/primaryLight/onPrimary/divider stays fixed per
  /// brightness — matching how the old hand-picked accent presets worked,
  /// just generalized to any color instead of 4 fixed choices.
  static ThemeColors forColor(Color primary, Brightness brightness) {
    final fixed = brightness == Brightness.dark ? _darkFixed : _lightFixed;
    final primaryLight = Color.lerp(primary, Colors.white, 0.35)!;
    // Luminance-based contrast, not tied to app brightness — a very light
    // custom color still needs dark text/icons on top of it even in dark
    // mode, and vice versa.
    final onPrimary =
        primary.computeLuminance() > 0.45 ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
    return ThemeColors(
      background: fixed.background,
      surface: fixed.surface,
      surfaceVariant: fixed.surfaceVariant,
      primary: primary,
      primaryLight: primaryLight,
      onPrimary: onPrimary,
      textPrimary: fixed.textPrimary,
      textSecondary: fixed.textSecondary,
      error: fixed.error,
      success: fixed.success,
      divider: primary.withValues(alpha: 0.2),
      statusPending: fixed.statusPending,
      statusRescheduled: fixed.statusRescheduled,
    );
  }

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
        statusPending: statusPending,
        statusRescheduled: statusRescheduled,
      );
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
    required this.statusPending,
    required this.statusRescheduled,
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
  final Color statusPending;
  final Color statusRescheduled;

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
    Color? statusPending,
    Color? statusRescheduled,
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
      statusPending: statusPending ?? this.statusPending,
      statusRescheduled: statusRescheduled ?? this.statusRescheduled,
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
      statusPending: Color.lerp(statusPending, other.statusPending, t)!,
      statusRescheduled: Color.lerp(statusRescheduled, other.statusRescheduled, t)!,
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
