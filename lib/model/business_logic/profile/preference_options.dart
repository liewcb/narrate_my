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
/// and explicitly rejected — a fixed toggle list only (Wheelchair
/// Accessible / Mobility Assistance / Visual Assistance), each with a
/// leading emoji shown in the UI ([kAccessibilityEmoji]) — no
/// [Preferences.accessibilityNotes] field exists any more. "Hearing
/// Assistance" was removed 6 Sep at Foo's request.
///
/// Category Exclusions ([kAttractionCategories]-based) was ALSO removed
/// entirely from both Preferences screens 6 Sep at Foo's request — same
/// "which is exclude which is include" confusion the REQ_503_7 rework
/// below already flagged for the attraction-category version of this idea.
/// `Preferences.categoryExclusions` stays in the entity/DB (untouched,
/// never overwritten by either screen now) in case it's revisited, but
/// nothing in the UI reads or writes it any more.
///
/// ASSUMPTION carried forward: "Food & Cuisine Interests"
/// ([kFoodCuisineOptions], REQ_503_8) is kept even though it's periodically
/// dropped from the team's own re-plans — it maps directly to a graded
/// requirement, so it stays until someone explicitly confirms cutting it.
library;

import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';

/// Translation-key lookup for the option-value constants below.
///
/// The constants (e.g. [kAttractionCategories]) hold their ENGLISH values
/// on purpose — those strings are the stable identifiers used everywhere
/// else in the code: stored in the DB via [Preferences], used as
/// `Set<String>.contains()` selection keys, and used as `Map` keys for
/// [kAttractionCategoryImages] / [kAccessibilityEmoji] /
/// [kAccessibilityDescriptions]. Changing them to a translated string would
/// break all of that. Instead, this map translates an English option value
/// to its display label ONLY — call [optionLabel] wherever an option value
/// is shown to the user, and keep passing the raw English value everywhere
/// else (selection sets, storage, image/icon/emoji lookups).
const Map<String, String> _kOptionLabelKeys = {
  'Heritage': 'pref.attr.heritage',
  'Nature': 'pref.attr.nature',
  'Food': 'pref.attr.food',
  'Shopping': 'pref.attr.shopping',
  'Adventure': 'pref.attr.adventure',
  'Malay': 'pref.cuisine.malay',
  'Chinese': 'pref.cuisine.chinese',
  'Indian': 'pref.cuisine.indian',
  'Peranakan/Nyonya': 'pref.cuisine.peranakan',
  'Western': 'pref.cuisine.western',
  'Street Food': 'pref.cuisine.streetFood',
  'Seafood': 'pref.cuisine.seafood',
  'Vegetarian-Friendly': 'pref.cuisine.vegetarianFriendly',
  'Halal': 'pref.dietary.halal',
  'Vegetarian': 'pref.dietary.vegetarian',
  'Vegan': 'pref.dietary.vegan',
  'No Pork': 'pref.restriction.noPork',
  'No Beef': 'pref.restriction.noBeef',
  'Gluten-Free': 'pref.restriction.glutenFree',
  'Nut Allergy': 'pref.restriction.nutAllergy',
  'Shellfish Allergy': 'pref.restriction.shellfishAllergy',
  'Dairy-Free / Lactose Intolerant': 'pref.restriction.dairyFree',
  'Wheelchair Accessible': 'pref.access.wheelchair',
  'Mobility Assistance': 'pref.access.mobility',
  'Visual Assistance': 'pref.access.visual',
};

/// Translated display label for an option value from any of the lists
/// below (falls back to the raw English value if it isn't in the map, so
/// a newly-added option that hasn't been translated yet still renders).
String optionLabel(String englishValue) {
  final key = _kOptionLabelKeys[englishValue];
  return key == null ? englishValue : AppLocalizations.t(key);
}

/// Translation key lookup for [kAccessibilityDescriptions]' English values.
const Map<String, String> _kAccessibilityDescKeys = {
  'Wheelchair Accessible': 'pref.access.wheelchairDesc',
  'Mobility Assistance': 'pref.access.mobilityDesc',
  'Visual Assistance': 'pref.access.visualDesc',
};

/// Translated subtitle for an accessibility option (see
/// [kAccessibilityDescriptions] for the English source values).
String? accessibilityDescription(String englishValue) {
  final key = _kAccessibilityDescKeys[englishValue];
  return key == null ? kAccessibilityDescriptions[englishValue] : AppLocalizations.t(key);
}

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

/// REQ_503_6 — a fixed toggle list. Deliberately no open-ended "other"
/// option/free-text field (tried once, explicitly rejected — a catch-all
/// text box doesn't behave like the rest of the toggles and can't be
/// filtered on). "Hearing Assistance" removed 6 Sep at Foo's request.
const List<String> kAccessibilityOptions = [
  'Wheelchair Accessible',
  'Mobility Assistance',
  'Visual Assistance',
];

/// Leading emoji shown on each accessibility toggle row.
const Map<String, String> kAccessibilityEmoji = {
  'Wheelchair Accessible': '♿',
  'Mobility Assistance': '🦯',
  'Visual Assistance': '👁️',
};

/// One-line subtitle shown under each accessibility option's toggle switch
/// (design canvas treats this section as toggles + description, not chips).
const Map<String, String> kAccessibilityDescriptions = {
  'Wheelchair Accessible': 'Prioritize ramps, lifts, and step-free routes',
  'Mobility Assistance': 'Favor shorter routes and seating along the way',
  'Visual Assistance': 'Highlight audio guides and tactile cues',
};
