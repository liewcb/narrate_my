import 'package:flutter/material.dart';

/// Centralised colour tokens for NarrateMy.
///
/// `AppColors` is the single source of truth for every screen. Screens
/// must reference these tokens instead of hardcoding hex values, so the
/// brand palette stays consistent and themeable in one place.
class AppColors {
  // ─── Brand Colours ──────────────────────────────────────────
  static const brandGreen = Color(0xFF0F3D35);       // primary dark green
  static const brandGreenLight = Color(0xFFEAF0ED);  // light green tint
  static const brandTerracotta = Color(0xFFD4856E);  // warm accent
  static const brandCharcoal = Color(0xFF1A1A1A);    // near-black text

  // ─── Background & Surfaces ──────────────────────────────────
  static const background = Color(0xFFF9F9F7);       // main background
  static const creamBg = Color(0xFFF6F3EB);          // warmer cream
  static const surfaceCard = Color(0xFFFFFFFF);      // white cards
  static const white = Color(0xFFFFFFFF);
  static const warmBg = Color(0xFFFCF9F8);           // warm edit screens
  static const warmGrayLight = Color(0xFFF6F3F2);    // very light warm gray
  static const backgroundTint = Color(0xFFF8FAF7);   // green-tinted bg

  // ─── Itinerary greens ───────────────────────────────────────
  static const pineGreen = Color(0xFF194D44);        // itinerary primary
  static const pineDark = Color(0xFF1B4F46);         // darker pine
  static const tealGreen = Color(0xFF35675D);        // secondary green
  static const darkGreenMuted = Color(0xFF3F4945);   // muted green-gray
  static const brandGreenDark = Color(0xFF00342B);   // very dark green
  static const textPrimary = Color(0xFF1A201E);      // green-tinted near-black
  static const mintLight = Color(0xFFD4E6E5);        // mint tint

  // ─── Terracotta / accents ───────────────────────────────────
  static const terracotta = Color(0xFFD48152);       // itinerary accent
  static const terracottaDark = Color(0xFF914C21);   // deep terracotta
  static const orange = Color(0xFFFF8A65);           // rating star

  // ─── Text colours ───────────────────────────────────────────
  static const charcoal = Color(0xFF1B1B1B);         // headings
  static const charcoalAlt = Color(0xFF1C1C1C);      // alt charcoal
  static const nearBlack = Color(0xFF191C1B);        // deep near-black
  static const mutedText = Color(0xFF9E9B93);        // muted labels
  static const tertiary = Color(0xFF5F5E58);         // secondary text
  static const textSecondary = Color(0xFF516161);    // muted green-gray text
  static const warmBrown = Color(0xFF54433B);        // brown text
  static const taupe = Color(0xFF87736A);            // muted brown-gray

  // ─── Outlines & Borders ────────────────────────────────────
  static const outline = Color(0xFF707975);          // muted gray-green
  static const outlineVariant = Color(0xFFD4D8D5);   // light border
  static const outlineLight = Color(0xFFE8E3D8);     // very light
  static const surfaceInactive = Color(0xFFE6E2D6);  // warm inactive pill
  static const surfaceDim = Color(0xFFDCD9D9);       // dim surface
  static const borderLight = Color(0xFFE1E3E0);      // subtle border
  static const brandGrayLight = Color(0xFFF2F2F2);
  static const mutedGreen = Color(0xFFBFC9C4);       // green-gray border
  static const grayWarm = Color(0xFFE5E2E1);         // warm gray

  // ─── Status / semantic ──────────────────────────────────────
  static const dangerText = Color(0xFFD9534F);       // error red
  static const dangerRed = Color(0xFFBA1A1A);        // deep red
  static const dangerBg = Color(0xFFF9E4E4);         // light error bg
  static const successGreenLight = Color(0xFFE8EFEA); // success tint
  static const pinkLight = Color(0xFFFFDAD6);        // light pink

  // ─── Category segment palette ───────────────────────────────
  static const indigo = Color(0xFF5C6BC0);
  static const brown = Color(0xFF8D6E63);
  static const teal = Color(0xFF0097A7);
  static const purple = Color(0xFF7B1FA2);

  // ─── Aliases ────────────────────────────────────────────────
  static const black = Color(0xFF1A1A1A);            // alias for brandCharcoal

  // ─── Text-on-color tokens ───────────────────────────────────
  static const textTertiary = Color(0xFF9E9B93);     // muted tertiary text
  static const textOnTerracotta = Color(0xFFFFFFFF); // text on terracotta
  static const textOnBrandGreen = Color(0xFFFFFFFF); // text on brand green
}
