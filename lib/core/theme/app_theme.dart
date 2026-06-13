import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Central theme definition for TaskFlow Executive.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.surface,
      primaryColor: AppColors.gold,
      dividerColor: AppColors.divider,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.goldLight,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.background,
        onSecondary: AppColors.background,
        onSurface: AppColors.textPrimary,
        onError: AppColors.background,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.gold),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.18)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.3),
          disabledForegroundColor: AppColors.background.withValues(alpha: 0.6),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: const BorderSide(color: AppColors.gold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.goldLight),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.background,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.gold,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceVariant,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.gold;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(AppColors.background),
        side: const BorderSide(color: AppColors.gold),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(AppColors.gold),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.gold.withValues(alpha: 0.5);
          }
          return AppColors.surfaceVariant;
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.gold,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.gold,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.gold.withValues(alpha: 0.15),
        thickness: 1,
      ),
    );
  }
}
