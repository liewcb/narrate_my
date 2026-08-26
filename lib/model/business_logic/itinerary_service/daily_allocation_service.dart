import '../../../core/config/interest_mapping.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import 'clustering_service.dart';
import 'scoring_service.dart';

/// Represents a full day's itinerary with activities.
class AllocatedDay {
  final int dayIndex;
  final ScoredAttraction anchor;
  final List<ScoredAttraction> morningActivities;
  final List<ScoredAttraction> afternoonActivities;
  final List<ScoredAttraction> restaurants;
  final DateTime date;

  const AllocatedDay({
    required this.dayIndex,
    required this.anchor,
    required this.morningActivities,
    required this.afternoonActivities,
    required this.restaurants,
    required this.date,
  });

  /// Get all activities in chronological order.
  List<ScoredAttraction> get allActivities {
    return [
      anchor,
      ...morningActivities,
      ...restaurants.where((r) => r.place.category == 'restaurant'),
      ...afternoonActivities,
    ];
  }

  /// Count total stops for the day.
  int get totalStops => allActivities.length;
}

/// Pipeline Step 6: Daily Allocation.
///
/// Allocates activities around each day's anchor, split into morning and
/// afternoon blocks, and ensures every day has a restaurant stop.
class DailyAllocationService {
  /// Allocate activities for each day based on anchor and cluster.
  List<AllocatedDay> allocateDailyActivities({
    required List<Cluster> clusters,
    required List<ScoredAttraction> allScoredPlaces,
    required DateTime startDate,
    required String travelPace,
    required List<String> interests,
  }) {
    final List<AllocatedDay> allocatedDays = [];

    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final date = startDate.add(Duration(days: i));

      // 1. Sort cluster attractions by score
      final sortedCluster = [...cluster.attractions]
        ..sort((a, b) => b.score.compareTo(a.score));

      // 2. Pick anchor (highest scored)
      final anchor = sortedCluster.first;

      // 3. Get remaining attractions (excluding anchor)
      final remaining = sortedCluster.sublist(1);

      // 4. Determine how many attractions to add per day based on pace
      final attractionsPerDay = _getAttractionsPerDay(travelPace);

      // 5. Filter attractions by interests
      final filtered = _filterByInterests(remaining, interests);

      // 6. Select top attractions to fill the day
      final selectedAttractions = <ScoredAttraction>[];
      final maxToTake = attractionsPerDay - 1; // minus the anchor

      for (final place in filtered) {
        if (selectedAttractions.length >= maxToTake) break;
        selectedAttractions.add(place);
      }

      // 7. Split into morning and afternoon
      final midPoint = (selectedAttractions.length / 2).ceil();
      final morningActivities = selectedAttractions.sublist(0, midPoint);
      final afternoonActivities = selectedAttractions.sublist(midPoint);

      // 8. Find restaurants (food places)
      var restaurants = _findRestaurants(cluster.attractions, interests);

      // 9. Ensure at least 1 restaurant per day
      if (restaurants.isEmpty) {
        restaurants = _findNearbyRestaurants(
          allScoredPlaces,
          anchor.place.coordinates,
        );
      }

      // 10. Limit restaurants to 2 per day
      if (restaurants.length > 2) {
        restaurants = restaurants.sublist(0, 2);
      }

      allocatedDays.add(AllocatedDay(
        dayIndex: i,
        anchor: anchor,
        morningActivities: morningActivities,
        afternoonActivities: afternoonActivities,
        restaurants: restaurants,
        date: date,
      ));
    }

    return allocatedDays;
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Get number of attractions per day based on pace.
  int _getAttractionsPerDay(String travelPace) {
    return ItineraryConstants.paceToAttractionsPerDay[travelPace] ?? 4;
  }

  /// Filter places by user interests.
  List<ScoredAttraction> _filterByInterests(
    List<ScoredAttraction> places,
    List<String> interests,
  ) {
    if (interests.isEmpty) return places;

    return places.where((place) {
      // Check if any of the place's types match any interest
      for (final type in place.place.types) {
        final matchedInterest = InterestMapping.getInterestForType(type);
        if (matchedInterest != null && interests.contains(matchedInterest)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  /// Find restaurants from the cluster.
  List<ScoredAttraction> _findRestaurants(
    List<ScoredAttraction> places,
    List<String> interests,
  ) {
    final restaurants = <ScoredAttraction>[];

    for (final place in places) {
      final isRestaurant = place.place.types.any((type) =>
          type == 'restaurant' ||
          type == 'cafe' ||
          type == 'bakery' ||
          type == 'meal_takeaway');

      if (isRestaurant) {
        restaurants.add(place);
      }
    }

    // Sort by rating (highest first)
    restaurants.sort((a, b) => b.place.rating.compareTo(a.place.rating));

    return restaurants;
  }

  /// Find nearby restaurants if none in cluster.
  List<ScoredAttraction> _findNearbyRestaurants(
    List<ScoredAttraction> allPlaces,
    Coordinates anchorCoord,
  ) {
    // Filter all places that are restaurants
    final restaurants = allPlaces.where((place) {
      return place.place.types.any((type) =>
          type == 'restaurant' || type == 'cafe' || type == 'bakery');
    }).toList();

    // Sort by distance to anchor
    restaurants.sort((a, b) {
      final distA = a.place.coordinates.distanceTo(anchorCoord);
      final distB = b.place.coordinates.distanceTo(anchorCoord);
      return distA.compareTo(distB);
    });

    return restaurants;
  }
}
