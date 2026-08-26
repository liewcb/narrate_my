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

  /// Gets a display sub-category for a Google Places type.
  static String getSubCategory(String googleType, bool isFood) {
    if (isFood) {
      return foodTypesToSubCategory[googleType] ?? 'Food & Dining';
    }
    return attractionTypesToSubCategory[googleType] ?? 'Attraction';
  }
}