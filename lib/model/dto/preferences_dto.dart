import '../entities/preferences.dart';

class PreferencesDto {
  final List<String> attractionInterests;
  final List<String> foodCuisineInterests;
  final List<String> dietaryPreferences;
  final List<String> dietaryRestrictions;
  final List<String> accessibilityPreferences;
  final List<String> categoryExclusions;

  PreferencesDto({
    required this.attractionInterests,
    required this.foodCuisineInterests,
    required this.dietaryPreferences,
    required this.dietaryRestrictions,
    required this.accessibilityPreferences,
    required this.categoryExclusions,
  });

  factory PreferencesDto.fromJson(Map<String, dynamic> json) {
    List<String> arr(String key) =>
        (json[key] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    return PreferencesDto(
      attractionInterests: arr('attraction_interests'),
      foodCuisineInterests: arr('food_cuisine_interests'),
      dietaryPreferences: arr('dietary_preferences'),
      // Null until 0004_preferences_dietary_accessibility_split.sql has
      // been run — a row fetched before that migration just won't have
      // this key at all.
      dietaryRestrictions: arr('dietary_restrictions'),
      accessibilityPreferences: arr('accessibility_preferences'),
      categoryExclusions: arr('category_exclusions'),
    );
  }

  Preferences toEntity() => Preferences(
        attractionInterests: attractionInterests,
        foodCuisineInterests: foodCuisineInterests,
        dietaryPreferences: dietaryPreferences,
        dietaryRestrictions: dietaryRestrictions,
        accessibilityPreferences: accessibilityPreferences,
        categoryExclusions: categoryExclusions,
      );

  /// Column-scoped map for the `preferences` table `UPDATE` — REQ_503_11:
  /// this is the ENTIRE atomic Preferences save, never merged with Personal
  /// Info or Language columns.
  static Map<String, dynamic> toUpdateJson(Preferences p) => {
        'attraction_interests': p.attractionInterests,
        'food_cuisine_interests': p.foodCuisineInterests,
        'dietary_preferences': p.dietaryPreferences,
        'dietary_restrictions': p.dietaryRestrictions,
        'accessibility_preferences': p.accessibilityPreferences,
        'category_exclusions': p.categoryExclusions,
      };
}
