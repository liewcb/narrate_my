/// Domain entity for UC402's Preferences section (REQ_503_4/5/6/7/8).
/// Deliberately separate from [Profile] — REQ_503_11 requires Personal
/// Info, Preferences, and Language to save as independent atomic updates,
/// and this maps 1:1 onto `public.preferences`, its own table.
class Preferences {
  final List<String> attractionInterests; // REQ_503_4
  final List<String> foodCuisineInterests; // REQ_503_8 (distinct from dietary)
  final List<String> dietaryPreferences; // REQ_503_5 (lifestyle: Halal/Vegetarian/Vegan)
  final List<String> dietaryRestrictions; // REQ_503_5 (hard restrictions/allergies)
  final List<String> accessibilityPreferences; // REQ_503_6 (fixed 4-option toggle list)
  final List<String> categoryExclusions; // REQ_503_7

  const Preferences({
    this.attractionInterests = const [],
    this.foodCuisineInterests = const [],
    this.dietaryPreferences = const [],
    this.dietaryRestrictions = const [],
    this.accessibilityPreferences = const [],
    this.categoryExclusions = const [],
  });

  Preferences copyWith({
    List<String>? attractionInterests,
    List<String>? foodCuisineInterests,
    List<String>? dietaryPreferences,
    List<String>? dietaryRestrictions,
    List<String>? accessibilityPreferences,
    List<String>? categoryExclusions,
  }) {
    return Preferences(
      attractionInterests: attractionInterests ?? this.attractionInterests,
      foodCuisineInterests: foodCuisineInterests ?? this.foodCuisineInterests,
      dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
      dietaryRestrictions: dietaryRestrictions ?? this.dietaryRestrictions,
      accessibilityPreferences: accessibilityPreferences ?? this.accessibilityPreferences,
      categoryExclusions: categoryExclusions ?? this.categoryExclusions,
    );
  }
}
