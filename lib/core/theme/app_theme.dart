import 'package:flutter/material.dart';

import '../responsive/app_spacing.dart';
import 'theme_colors.dart';

/// Central theme definition for TaskFlow Executive.
///
/// [themeFor] builds a complete [ThemeData] for any accent +
/// brightness combination, driven entirely by [ThemeColors]. All
/// "chrome" widgets (AppBar, BottomNavigationBar, FloatingActionButton,
/// Switch, Chip, TabBar, Drawer, ProgressIndicator, buttons, cards,
/// dialogs, inputs, dividers, snackbars) read their colors from this
/// [ThemeData], so they automatically follow the user's selected accent
/// color and light/dark mode.
class AppTheme {
  AppTheme._();

  /// The app's typeface, bundled in `assets/fonts/`.
  static const String fontFamily = 'PlusJakartaSans';

  /// Larger text gets slightly negative tracking; small text gets none.
  ///
  /// Geometric sans faces look loose at display sizes and cramped at
  /// caption sizes, so tracking is applied proportionally to the font
  /// size rather than as one flat value across the whole scale.
  static TextTheme _typography(TextTheme base, ThemeColors colors) {
    TextStyle? tighten(TextStyle? style, double em) {
      if (style == null) return null;
      final size = style.fontSize;
      return size == null ? style : style.copyWith(letterSpacing: size * em);
    }

    final colored = base.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    );

    return colored.copyWith(
      displayLarge: tighten(colored.displayLarge, -0.025),
      displayMedium: tighten(colored.displayMedium, -0.025),
      displaySmall: tighten(colored.displaySmall, -0.022),
      headlineLarge: tighten(colored.headlineLarge, -0.022),
      headlineMedium: tighten(colored.headlineMedium, -0.02),
      headlineSmall: tighten(colored.headlineSmall, -0.02),
      titleLarge: tighten(colored.titleLarge, -0.018),
      titleMedium: tighten(colored.titleMedium, -0.012),
    );
  }

  /// Backwards-compatible getter: the original always-dark, gold-accented
  /// theme, kept identical to the historical `AppColors`-based palette.
  static ThemeData get darkTheme =>
      themeFor(kDefaultAccentColor, Brightness.dark);

  /// Builds a [ThemeData] for the given [accent] color + [brightness].
  static ThemeData themeFor(Color accent, Brightness brightness) {
    final colors = ThemeColors.forColor(accent, brightness);
    // Built via the unnamed constructor (rather than ThemeData.dark/.light)
    // so `fontFamily` reaches every default text style in one place.
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
    );

    final colorScheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: colors.primary,
            onPrimary: colors.onPrimary,
            secondary: colors.primaryLight,
            onSecondary: colors.onPrimary,
            surface: colors.surface,
            onSurface: colors.textPrimary,
            error: colors.error,
            onError: colors.onPrimary,
          )
        : ColorScheme.light(
            primary: colors.primary,
            onPrimary: colors.onPrimary,
            secondary: colors.primaryLight,
            onSecondary: colors.onPrimary,
            surface: colors.surface,
            onSurface: colors.textPrimary,
            error: colors.error,
            onError: colors.onPrimary,
          );

    return base.copyWith(
      textTheme: _typography(base.textTheme, colors),
      scaffoldBackgroundColor: colors.background,
      cardColor: colors.surface,
      primaryColor: colors.primary,
      dividerColor: colors.divider,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: colors.primary),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 20 * -0.018,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.18)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        labelStyle: TextStyle(color: colors.textSecondary),
        hintStyle: TextStyle(color: colors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.primary.withValues(alpha: 0.3),
          disabledForegroundColor: colors.onPrimary.withValues(alpha: 0.6),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.primaryLight),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.surface,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surface,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceVariant,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
        side: BorderSide(color: colors.primary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(colors.primary),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primary.withValues(alpha: 0.5);
          }
          return colors.surfaceVariant;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceVariant,
        selectedColor: colors.primary.withValues(alpha: 0.2),
        disabledColor: colors.surfaceVariant.withValues(alpha: 0.5),
        labelStyle: TextStyle(color: colors.textPrimary),
        secondaryLabelStyle: TextStyle(color: colors.onPrimary),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.4)),
        // StadiumBorder rather than a fixed 20px radius so chips stay a true
        // pill at any height (dense filter chips vs. regular ones).
        shape: const StadiumBorder(),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        useIndicator: true,
        indicatorColor: colors.primary.withValues(alpha: 0.18),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        selectedIconTheme: IconThemeData(color: colors.primary, size: 22),
        selectedLabelTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(color: colors.textSecondary, size: 22),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.textSecondary,
          fontSize: 12,
        ),
        minWidth: AppLayout.navigationRailWidth,
      ),
      extensions: [colors.toExtension()],
    );
  }
}
