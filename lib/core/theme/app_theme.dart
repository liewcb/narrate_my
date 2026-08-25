/// NarrateMy design tokens + ThemeData for Module 5 (User Profile & Language
/// Management) screens — matches the published design canvas 1:1.
///
/// Canvas: https://claude.ai/code/artifact/34afab66-1712-4337-847f-7bde85a754c3
/// Palette: "Warm Heritage Editorial" — warm cream background, terracotta
/// accent, teal/green secondary accents. Typeface: Nunito (Google Font).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Raw design tokens, exposed directly for widgets that need a color not
/// covered by [ThemeData] (e.g. the specific teal/gold accents used for
/// tags and status pills in the design canvas).
class AppColors {
  AppColors._();

  static const bg = Color(0xFFFBF3EA);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF5EAD8);
  static const ink = Color(0xFF2B241D);
  static const inkSoft = Color(0xFF6B5D4F);
  static const inkFaint = Color(0xFF9C8A76);
  static const border = Color(0xFFE6D7C3);
  static const accent = Color(0xFFC1622D);
  static const accentDark = Color(0xFF8F4620);
  static const accentSoft = Color(0xFFF1DCC3);
  static const green = Color(0xFF3F6B52);
  static const teal = Color(0xFF3E7C8A);
  static const gold = Color(0xFFD9A441);

  /// Standard error/failure red — not part of the original palette, chosen
  /// to sit comfortably alongside the warm tones (not a cold pure red).
  static const error = Color(0xFFC0392B);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
        primary: AppColors.accent,
        onPrimary: AppColors.bg,
        secondary: AppColors.teal,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.ink,
        ),
      ),
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.bg,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.nunito(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.nunito(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        labelStyle: GoogleFonts.nunito(
          fontSize: 10.5,
          color: AppColors.inkFaint,
        ),
        hintStyle: GoogleFonts.nunito(
          fontSize: 14.5,
          color: AppColors.inkFaint,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.border,
        ),
        thumbColor: const WidgetStatePropertyAll(AppColors.surface),
      ),
    );
  }
}
