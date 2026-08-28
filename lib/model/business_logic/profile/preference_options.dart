/// Pick-list options for the Preferences / Initial-Preferences screens.
///
/// NOTE: the spec (REQ_503_4/5/6/7/8) only defines the category *names*
/// (attraction interests, food & cuisine interests, dietary preferences and
/// restrictions, accessibility preferences, category exclusions) — it does
/// not define the individual option values within each. These lists match
/// the taxonomy re-agreed on 24 Aug (revised again same day after review —
/// see `module5-preferences-feasibility.md` for history).
///
/// REQ_503_7 Category Exclusions: revised again after review — an
/// attraction-category exclusion list read as a near-duplicate of
/// Attraction & Activity Interests ("which is exclude which is include"),
/// so it was dropped entirely (not selecting a category as an Interest
/// already means "not interested"). REQ_503_7 is instead scoped to Food &
/// Cuisine only — "cuisines to avoid" — using [kFoodCuisineOptions]'
/// vocabulary and a warning-styled box (`_ExcludeBox` in
/// `preferences_screen.dart`) so it reads as "avoid this" at a glance
/// instead of a re-tinted copy of the Interests chips above it.
///
/// "Travel Preferences" (Relaxed/Balanced/Adventure) was added, then
/// REMOVED same day — confirmed against `collab temporary workfile 32.pdf`
/// to be Module 3's field (REQ_301_08/12/13, entered per itinerary request,
/// official labels Relaxed/Moderate/Fast-paced), not a Module 5 saved
/// profile preference at all.
///
/// REQ_503_5 ("dietary preferences AND restrictions") is deliberately split
/// into two separate sections/vocabularies here — [kDietaryOptions] (a
/// lifestyle choice: Halal/Vegetarian/Vegan) and
/// [kDietaryRestrictionOptions] (a hard restriction/allergy) — rather than
/// one flat chip list, since conflating "I prefer vegetarian food" with
/// "I have a nut allergy" reads as the same kind of tag when they aren't.
///
/// REQ_503_6 Accessibility Preferences: a free-text "other" field was tried
/// and explicitly rejected — a fixed 4-option toggle list only
/// (Wheelchair Accessible / Mobility Assistance / Visual Assistance /
/// Hearing Assistance), each with a leading emoji shown in the UI
/// ([kAccessibilityEmoji]) — no [Preferences.accessibilityNotes] field
/// exists any more.
///
/// ASSUMPTION carried forward: "Food & Cuisine Interests"
/// ([kFoodCuisineOptions], REQ_503_8) is kept even though it's periodically
/// dropped from the team's own re-plans — it maps directly to a graded
/// requirement, so it stays until someone explicitly confirms cutting it.
library;

import 'package:flutter/material.dart';

/// REQ_503_4 vocabulary — what kind of attractions/activities a tourist is
/// interested in (Preferences / onboarding). No longer doubles as an
/// exclusion vocabulary — see the REQ_503_7 note above.
const List<String> kAttractionCategories = [
  'Heritage',
  'Nature',
  'Food',
  'Shopping',
  'Adventure',
];

/// Real category photo for each attraction-tile — bundled app assets (see
/// `pubspec.yaml`'s `flutter.assets`, files under `assets/images/attractions/`).
/// [AttractionTile] falls back to a plain icon+gradient tile for any label
/// not listed here (keeps the grid working for a category added later,
/// before its photo exists).
const Map<String, String> kAttractionCategoryImages = {
  'Heritage': 'assets/images/attractions/heritage.jpg',
  'Nature': 'assets/images/attractions/nature.jpg',
  'Food': 'assets/images/attractions/food.jpg',
  'Shopping': 'assets/images/attractions/shopping.jpg',
  'Adventure': 'assets/images/attractions/adventure.jpg',
};

/// Fallback icon for [AttractionTile] when a label has no entry in
/// [kAttractionCategoryImages] yet.
const Map<String, IconData> kAttractionCategoryIcons = {
  'Heritage': Icons.account_balance,
  'Nature': Icons.forest,
  'Food': Icons.restaurant,
  'Shopping': Icons.shopping_bag,
  'Adventure': Icons.terrain,
};

const List<String> kFoodCuisineOptions = [
  'Malay',
  'Chinese',
  'Indian',
  'Peranakan/Nyonya',
  'Western',
  'Street Food',
  'Seafood',
  'Vegetarian-Friendly',
];

/// REQ_503_5, first half — a dietary *lifestyle* choice, not a hard
/// restriction. Shown as its own "Dietary Preferences" section.
const List<String> kDietaryOptions = ['Halal', 'Vegetarian', 'Vegan'];

/// REQ_503_5, second half — hard restrictions/allergies. Shown as its own
/// "Dietary Restrictions & Allergies" section, separate from the lifestyle
/// chips above so the two aren't read as the same kind of thing.
const List<String> kDietaryRestrictionOptions = [
  'No Pork',
  'No Beef',
  'Gluten-Free',
  'Nut Allergy',
  'Shellfish Allergy',
  'Dairy-Free / Lactose Intolerant',
];

/// REQ_503_6 — a fixed 4-option toggle list. Deliberately no open-ended
/// "other" option/free-text field (tried once, explicitly rejected — a
/// catch-all text box doesn't behave like the rest of the toggles and can't
/// be filtered on).
const List<String> kAccessibilityOptions = [
  'Wheelchair Accessible',
  'Mobility Assistance',
  'Visual Assistance',
  'Hearing Assistance',
];

/// Leading emoji shown on each accessibility toggle row.
const Map<String, String> kAccessibilityEmoji = {
  'Wheelchair Accessible': '♿',
  'Mobility Assistance': '🦯',
  'Visual Assistance': '👁️',
  'Hearing Assistance': '👂',
};

/// One-line subtitle shown under each accessibility option's toggle switch
/// (design canvas treats this section as toggles + description, not chips).
const Map<String, String> kAccessibilityDescriptions = {
  'Wheelchair Accessible': 'Prioritize ramps, lifts, and step-free routes',
  'Mobility Assistance': 'Favor shorter routes and seating along the way',
  'Visual Assistance': 'Highlight audio guides and tactile cues',
  'Hearing Assistance': 'Highlight captions and visual signage',
};
