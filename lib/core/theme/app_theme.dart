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

  /// Backwards-compatible getter: the original always-dark, gold-accented
  /// theme, kept identical to the historical `AppColors`-based palette.
  static ThemeData get darkTheme =>
      themeFor(kDefaultAccentColor, Brightness.dark);

  /// Builds a [ThemeData] for the given [accent] color + [brightness].
  static ThemeData themeFor(Color accent, Brightness brightness) {
    final colors = ThemeColors.forColor(accent, brightness);
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

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
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.primary.withValues(alpha: 0.3),
          disabledForegroundColor: colors.onPrimary.withValues(alpha: 0.6),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceVariant,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedIconTheme: IconThemeData(color: colors.textSecondary, size: 22),
        unselectedLabelTextStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
        ),
        minWidth: AppLayout.navigationRailWidth,
      ),
      extensions: [colors.toExtension()],
    );
  }
}
