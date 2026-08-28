/// NarrateMy design tokens + ThemeData for Module 5 (User Profile & Language
/// Management) screens — matches the published design canvas 1:1.
///
/// Canvas: https://claude.ai/code/artifact/34afab66-1712-4337-847f-7bde85a754c3
/// Palette: "Warm Heritage Editorial" — warm cream background, terracotta
/// accent, teal/green secondary accents. Typeface: Nunito (Google Font).
///
/// MERGE NOTE (25 Aug): this file used to diverge from a teammate's simpler
/// green-primary theme (used by `AppBottomNavBar`, shared across every
/// module's tab). Merged rather than picking one side — every Module 5
/// screen already depends on the tokens below (`ink`/`accent`/`error`/etc,
/// confirmed by grepping the whole `lib/` tree), while `AppBottomNavBar` is
/// the ONLY file outside Module 5 that touches `AppColors` at all, and it
/// only needs `primary`/`unselected`/`surface`/`border`. Everything from
/// both sides is kept; the one real collision (`border` meant a different
/// color on each side) is resolved by leaving the teammate's `border`
/// value and name exactly as they wrote it (so `AppBottomNavBar`, a shared
/// component, needed zero edits) and renaming Module 5's own warm-tan
/// divider color to `moduleBorder` instead — only Module 5's own files
/// needed updating to the new name, never anyone else's code.
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
  /// Module 5's own warm-tan divider/border color (dividers, outlined
  /// buttons, input underlines, switch tracks). Named `moduleBorder`, not
  /// `border`, so it never collides with the shared `border` token below
  /// that `AppBottomNavBar` (a component shared across every module) was
  /// already written against.
  static const moduleBorder = Color(0xFFE6D7C3);
  static const accent = Color(0xFFC1622D);
  static const accentDark = Color(0xFF8F4620);
  static const accentSoft = Color(0xFFF1DCC3);
  static const green = Color(0xFF3F6B52);
  static const teal = Color(0xFF3E7C8A);
  static const gold = Color(0xFFD9A441);

  /// Standard error/failure red — not part of the original palette, chosen
  /// to sit comfortably alongside the warm tones (not a cold pure red).
  static const error = Color(0xFFC0392B);

  // --- Shared app-wide tokens (from the teammate's theme, kept for
  // AppBottomNavBar and any other module's screens) ---------------------

  /// Primary brand green — selected/active states in the bottom nav bar
  /// (active tab, etc.), used app-wide outside Module 5.
  static const Color primary = Color(0xFF2D6A5E);

  static const Color unselected = Color(0xFF9CA3AF);

  /// Bottom nav bar's own border color — the teammate's original name and
  /// value, unchanged. `AppBottomNavBar` already reads `AppColors.border`
  /// directly, so this stays as `border` rather than being renamed; see
  /// [moduleBorder] above for Module 5's own (differently-named) divider
  /// color, which is what actually moved to avoid the collision.
  static const Color border = Color(0xFFF3F4F6);

  static const Color background = Colors.white;
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
          side: const BorderSide(color: AppColors.moduleBorder),
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
          borderSide: BorderSide(color: AppColors.moduleBorder, width: 1.5),
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
        color: AppColors.moduleBorder,
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.moduleBorder,
        ),
        thumbColor: const WidgetStatePropertyAll(AppColors.surface),
      ),
      // --- From the teammate's theme — kept so AppBottomNavBar (and any
      // other module relying on Theme-driven nav/filled-button styling)
      // keeps working exactly as they built it.
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

// ──────────────────────────────────────────────────────────────────────
// ADDED FROM itinerary_theme_tokens.dart (merged)
// ──────────────────────────────────────────────────────────────────────

/// Itinerary screens' text styles, expressed with the current theme's
/// palette and Nunito typeface.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get pageTitle => GoogleFonts.nunito(
    fontWeight: FontWeight.w600,
    fontSize: 24,
    color: AppColors.ink,
  );

  static TextStyle get sectionLabel => GoogleFonts.nunito(
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1.1,
    color: AppColors.inkSoft,
  );

  static TextStyle get bodyLg => GoogleFonts.nunito(
    fontWeight: FontWeight.w400,
    fontSize: 16,
    color: AppColors.ink,
  );

  static TextStyle get bodySm => GoogleFonts.nunito(
    fontWeight: FontWeight.w400,
    fontSize: 14,
    color: AppColors.ink,
  );

  static TextStyle get labelSm => GoogleFonts.nunito(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: AppColors.inkFaint,
  );

  static TextStyle get button => GoogleFonts.nunito(
    fontWeight: FontWeight.w600,
    fontSize: 15,
    color: AppColors.bg,
  );
}

/// Corner radius tokens used by itinerary screens.
class AppRadius {
  AppRadius._();

  static const double card = 16.0;
  static const double iconSm = 6.0;
  static const double pill = 999.0;
}

/// Spacing tokens used by itinerary screens (mapped to the theme grid).
class AppSpacing {
  AppSpacing._();

  static const double componentGap = 8.0;
  static const double cardPadding = 16.0;
  static const double screenMargin = 20.0;
  static const double sectionGap = 24.0;
  static const double pillPaddingX = 16.0;
  static const double pillPaddingY = 8.0;
}

/// Alias token for soft shadows used on cards.
class AppShadows {
  AppShadows._();

  static const Color card = Color(0x0A000000);
}