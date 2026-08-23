import 'package:flutter/material.dart';

/// Centralized color palette. Change a value here and it propagates
/// everywhere it's referenced — never hardcode a hex color directly in a
/// widget; add/reuse a constant here instead.
class AppColors {
  AppColors._();

  /// Primary brand green — selected/active states across the app
  /// (bottom nav active tab, primary buttons, links, etc.)
  /// Was previously hardcoded only inside AppBottomNavBar.
  static const Color primary = Color(0xFF2D6A5E);

  static const Color unselected = Color(0xFF9CA3AF);
  static const Color border = Color(0xFFF3F4F6);
  static const Color surface = Colors.white;
  static const Color background = Colors.white;
}

/// App-wide ThemeData, built from [AppColors]. Apply via
/// `MaterialApp(theme: AppTheme.light, ...)`.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.primary,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.unselected,
        backgroundColor: AppColors.surface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
      ),
    );
  }
}