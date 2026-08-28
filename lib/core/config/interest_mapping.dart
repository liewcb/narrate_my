/// Maps Google Places types to human-readable interest categories.
class InterestMapping {
  /// Maps UI interest labels to Google Places types.
  static const Map<String, List<String>> interestToGoogleTypes = {
    'History & Culture': [
      'museum',
      'art_gallery',
      'place_of_worship',
      'hindu_temple',
      'church',
      'mosque',
      'synagogue',
    ],
    'Nature & Outdoors': [
      'park',
      'national_park', // Replaced 'forest'
      'natural_feature',
      'campground',
      'zoo',
      'aquarium',
      'botanical_garden', // Replaced 'garden'
      'hiking_area', // Added for better outdoor coverage
      // Removed duplicate 'park'
    ],
    'Food & Culinary': [
      'restaurant',
      'cafe',
      'bakery',
      'meal_takeaway',
      'meal_delivery',
      'bar',
    ],
    'Thrills & Entertainment': [
      'amusement_park', // Covers theme parks and water parks
      'stadium',
      'bowling_alley',
      'tourist_attraction',
      'movie_theater',
    ],
    'Shopping & Markets': [
      'shopping_mall',
      'clothing_store',
      'department_store',
      'book_store',
      'jewelry_store',
      'supermarket', // Replaced 'market'
      'convenience_store', // Added to catch smaller local markets
    ],
    'Nightlife & Social': [
      'night_club',
      'casino',
      'liquor_store',
      'bar', // Covers 'wine_bar'
      'movie_theater',
    ],
  };

  /// Google Places types mapped to attraction display sub-categories.
  static const Map<String, String> attractionTypesToSubCategory = {
    // Wildlife & Animals
    'zoo': 'Wildlife & Animals',
    'aquarium': 'Wildlife & Animals',
    // Theme Parks
    'amusement_park': 'Theme Parks',
    'theme_park': 'Theme Parks',
    'water_park': 'Theme Parks',
    // Games & Sports
    'bowling_alley': 'Games & Bowling',
    'stadium': 'Sports & Events',
    // Culture
    'museum': 'Museums',
    'art_gallery': 'Art Galleries',
    // Landmarks
    'tourist_attraction': 'Landmarks',
    // Historical Sites
    'place_of_worship': 'Historical Sites',
    'church': 'Historical Sites',
    'hindu_temple': 'Historical Sites',
    'mosque': 'Historical Sites',
    'synagogue': 'Historical Sites',
    // Nature
    'park': 'Parks & Gardens',
    'garden': 'Parks & Gardens',
    'natural_feature': 'Natural Wonders',
    'forest': 'Natural Wonders',
    'beach': 'Natural Wonders',
    // Entertainment
    'movie_theater': 'Cinemas',
    // Shopping
    'shopping_mall': 'Shopping & Retail',
    'clothing_store': 'Shopping & Retail',
    'department_store': 'Shopping & Retail',
    'book_store': 'Shopping & Retail',
    'jewelry_store': 'Shopping & Retail',
    'market': 'Shopping & Retail',
    // Nightlife
    'night_club': 'Nightlife',
    'casino': 'Nightlife',
    'liquor_store': 'Nightlife',
    'wine_bar': 'Nightlife',
  };

  /// Google Places types mapped to food display sub-categories.
  static const Map<String, String> foodTypesToSubCategory = {
    'cafe': 'Coffee & Cafe',
    'bakery': 'Bakery & Sweets',
    'restaurant': 'Restaurant',
    'meal_takeaway': 'Quick Bites',
    'meal_delivery': 'Delivery',
    'bar': 'Bars & Pubs',
    'night_club': 'Nightlife & Drinks',
    'wine_bar': 'Wine Bar',
  };

  /// Maps the 6 canonical app interest labels to normalized database tags
  /// used by the `destination_hotspots.tags` column.
  ///
  /// These canonical tags drive hotspot resolution in the candidate
  /// retrieval pipeline (hotspot-driven multi-center search).
  static const Map<String, String> interestToDatabaseTag = {
    'History & Culture': 'culture_history',
    'Culture & History': 'culture_history',
    'Nature & Outdoors': 'nature_outdoor',
    'Nature & Outdoor': 'nature_outdoor',
    'Food & Culinary': 'food_culinary',
    'Thrills & Entertainment': 'thrills_entertainment',
    'Shopping & Markets': 'shopping_markets',
    'Nightlife & Social': 'nightlife_social',
  };

  /// Resolves the normalized database tag for a traveler interest label.
  ///
  /// Tolerates common label variants so UI labels that differ slightly from
  /// the canonical names still resolve. Returns null when no mapping exists.
  static String? databaseTagForInterest(String interest) {
    final label = interest.trim();

    final direct = interestToDatabaseTag[label];
    if (direct != null) return direct;

    final lower = label.toLowerCase();

    if (lower.contains('culture') || lower.contains('histor')) {
      return 'culture_history';
    }
    if (lower.contains('nature') || lower.contains('outdoor')) {
      return 'nature_outdoor';
    }
    if (lower.contains('food') || lower.contains('culinary') ||
        lower.contains('dining')) {
      return 'food_culinary';
    }
    if (lower.contains('thrill') || lower.contains('entertain')) {
      return 'thrills_entertainment';
    }
    if (lower.contains('shopp') || lower.contains('market')) {
      return 'shopping_markets';
    }
    if (lower.contains('night') || lower.contains('social')) {
      return 'nightlife_social';
    }
    return null;
  }

  /// Resolves the normalized database tags for a list of interest labels.
  static List<String> databaseTagsForInterests(Iterable<String> interests) {
    final tags = <String>[];
    final seen = <String>{};
    for (final interest in interests) {
      final tag = databaseTagForInterest(interest);
      if (tag != null && seen.add(tag)) {
        tags.add(tag);
      }
    }
    return tags;
  }

  /// Gets the first interest category associated with a Google Places type.
  static String? getInterestForType(String googleType) {
    for (final entry in interestToGoogleTypes.entries) {
      if (entry.value.contains(googleType)) return entry.key;
    }
    return null;
  }

  /// Gets all Google Places types associated with a selected interest.
  static List<String> getGoogleTypesForInterest(String interest) {
    return interestToGoogleTypes[interest] ?? [];
  }

  /// Maps the 8 standard app interest labels to valid Google Places
  /// attraction types used by the candidate-retrieval pipeline.
  ///
  /// Strict type enforcement: only these types are queried as attractions
  /// (food venues are handled by the dedicated food type list).
  static const Map<String, List<String>> interestToAttractionGoogleTypes = {
    'Culture & History': [
      'tourist_attraction',
      'museum',
      'art_gallery',
      'place_of_worship',
      'hindu_temple',
      'church',
      'mosque',
      'synagogue',
    ],
    'Nature & Outdoor': [
      'park',
      'natural_feature',
      'zoo',
      'aquarium',
      'botanical_garden',
      'campground',
      'hiking_area',
    ],
    'Food & Culinary': [
      'tourist_attraction',
      'bakery',
      'restaurant',
      'cafe',
      'meal_takeaway',
    ],
    'Nightlife': [
      'night_club',
      'casino',
      'bar',
      'movie_theater',
    ],
    'Adventure/Sports': [
      'amusement_park',
      'water_park',
      'stadium',
      'bowling_alley',
      'hiking_area',
      'tourist_attraction',
    ],
    'Wellness & Relaxation': [
      'spa',
      'beauty_salon',
      'park',
      'garden',
      'tourist_attraction',
    ],
    'Shopping': [
      'shopping_mall',
      'clothing_store',
      'department_store',
      'book_store',
      'jewelry_store',
    ],
    'Photography': [
      'tourist_attraction',
      'art_gallery',
      'museum',
      'natural_feature',
      'park',
      'hiking_area',
    ],
  };

  /// Gets the attraction Google Places types for a standard interest label.
  ///
  /// Falls back to the legacy [interestToGoogleTypes] mapping for labels
  /// that predate the canonical 8.
  static List<String> getAttractionGoogleTypesForInterest(String interest) {
    final canonical = interestToAttractionGoogleTypes[interest];
    if (canonical != null) return canonical;
    return getGoogleTypesForInterest(interest);
  }

  /// Gets a display sub-category for a Google Places type.
  static String getSubCategory(String googleType, bool isFood) {
    if (isFood) {
      return foodTypesToSubCategory[googleType] ?? 'Food & Dining';
    }
    return attractionTypesToSubCategory[googleType] ?? 'Attraction';
  }
}