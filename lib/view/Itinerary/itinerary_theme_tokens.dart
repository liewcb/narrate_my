// lib/view/Itinerary/itinerary_theme_tokens.dart
//
// Compatibility token layer for itinerary screens.
//
// The project's `app_theme.dart` now uses the "Warm Heritage Editorial"
// design tokens (bg/surface/ink/accent/teal/green/gold/...). The itinerary
// screens previously referenced a smaller set of names (AppTextStyles,
// AppRadius, AppSpacing, AppColors.background, ...). This file maps those
// names onto the new design tokens so every itinerary screen stays
// consistent with the current AppTheme without hardcoding raw hex values.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart' show AppColors;

export 'package:narrate_my/core/theme/app_theme.dart' show AppColors;

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

/// Alias token for soft shadows used on cards (kept out of raw hex here).
class AppShadows {
  AppShadows._();

  static const Color card = Color(0x0A000000);
}
