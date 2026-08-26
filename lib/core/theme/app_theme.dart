import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
// APP THEME — "Serene Traveler" Design System
// ═══════════════════════════════════════════════════════════════

// ─── Colors ───────────────────────────────────────────────────
class AppColors {
  // Background & surfaces
  static const background = Color(0xFFFCF9F8);       // background / surface
  static const surfaceCard = Color(0xFFFFFFFF);      // surface-container-lowest
  static const surfaceInactive = Color(0xFFE6E2D6);  // Inactive pills / disabled

  // Primary Terracotta family
  static const primaryTerracotta = Color(0xFF914C21);
  static const primaryContainer = Color(0xFFD48152);
  static const onPrimary = Color(0xFFFFFFFF);

  // Secondary Pine Green family
  static const secondaryPine = Color(0xFF35675D);
  static const secondaryActive = Color(0xFF194D44);  // Active Choice Pills
  static const onSecondary = Color(0xFFFFFFFF);

  // Text
  static const textPrimary = Color(0xFF1B1B1B);      // Charcoal
  static const textSecondary = Color(0xFF54433B);    // on-surface-variant
  static const textMuted = Color(0xFF9E9B93);        // text-muted
  static const textInactive = Color(0xFF6B6A65);     // Inactive pill text

  // Lines & borders
  static const outline = Color(0xFF87736A);
  static const outlineVariant = Color(0xFFD9C2B7);
  static const divider = Color(0xFFE6E2D6);          // 1px inner card dividers

  // Semantic (Danger/Error)
  static const error = Color(0xFFBA1A1A);
  static const dangerBg = Color(0xFFF9E4E4);
  static const dangerText = Color(0xFFD9534F);

  // Overlays
  static const shadow = Color(0x0A000000);           // 4% opacity (rgba(0,0,0,0.04))
}

// ─── Fonts ────────────────────────────────────────────────────
const String _bodyFont = 'Inter';

class AppTextStyles {
  // Displays
  static const pageTitle = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24, // 32px line height
    letterSpacing: -0.48, // -0.02em
    color: AppColors.textPrimary,
  );

  static const sectionLabel = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 16 / 11,
    letterSpacing: 1.1, // 0.1em
    color: AppColors.textSecondary,
  );

  // Body
  static const bodyLg = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppColors.textPrimary,
  );

  static const bodySm = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppColors.textPrimary,
  );

  // Labels & Meta
  static const labelSm = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    color: AppColors.textMuted,
  );

  // Buttons
  static const button = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 24 / 16,
    color: AppColors.onPrimary,
  );
}

// ─── Spacing & Sizes ─────────────────────────────────────────
class AppSpacing {
  static const componentGap = 8.0;
  static const cardPadding = 16.0;
  static const screenMargin = 20.0;
  static const sectionGap = 24.0;

  // Custom button padding mapping
  static const pillPaddingX = 16.0;
  static const pillPaddingY = 8.0;
}

class AppRadius {
  static const iconSm = 6.0; // 4px - 6px for icons within lists
  static const card = 16.0;  // Standard for cards & inputs
  static const pill = 999.0; // Fully rounded
}

// ─── ThemeData ──────────────────────────────────────────────
class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: _bodyFont,

      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryTerracotta,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.secondaryPine,
        onSecondary: AppColors.onSecondary,
        error: AppColors.error,
        onError: AppColors.onPrimary,
        surface: AppColors.surfaceCard,
        onSurface: AppColors.textPrimary,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
      ),

      textTheme: const TextTheme(
        displayLarge: AppTextStyles.pageTitle,
        titleMedium: AppTextStyles.sectionLabel,
        bodyLarge: AppTextStyles.bodyLg,
        bodyMedium: AppTextStyles.bodySm,
        labelSmall: AppTextStyles.labelSm,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.pageTitle,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),

      // CARDS: White background, 16px radius, subtle 4% shadow
      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 2,
        shadowColor: AppColors.shadow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // BUTTONS: Full-width pill, Terracotta Orange, 16px vertical padding
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryTerracotta,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.surfaceInactive,
          disabledForegroundColor: AppColors.textInactive,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          textStyle: AppTextStyles.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          elevation: 0, // Flat styling as per "Interactive Depth" rule
        ),
      ),

      // INPUTS: White container, 16px radius, NO border, 16px padding
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCard,
        hintStyle: AppTextStyles.bodyLg.copyWith(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.all(AppSpacing.cardPadding),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide.none, // Removes the border
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.primaryTerracotta, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),

      // CHOICE PILLS: Dark Pine active, Light Warm Gray inactive
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceInactive,
        selectedColor: AppColors.secondaryActive,
        labelStyle: AppTextStyles.bodySm.copyWith(color: AppColors.textInactive),
        secondaryLabelStyle: AppTextStyles.bodySm.copyWith(color: AppColors.onSecondary),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pillPaddingX,
            vertical: AppSpacing.pillPaddingY
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        side: BorderSide.none, // Depth communicated via color, not borders
      ),

      // DIVIDERS: 1px subtle separation within cards
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      iconTheme: const IconThemeData(
        color: AppColors.secondaryPine,
      ),
    );
  }
}