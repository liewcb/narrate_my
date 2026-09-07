// lib/model/business_logic/itinerary_service/database_recommended_places_service.dart
//
// DB-FIRST Recommended Places.
//
// Candidate source: Supabase `places` table.
// No Google Places request is made by this service.

import '../../../core/config/itinerary_constants.dart';
import '../../data_sources/remote/place_remote_source.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import 'custom_place_service.dart';
import 'scoring_service.dart';

class DatabaseRecommendedPlacesService {
  final PlaceRemoteSource _placeSource;
  final ScoringService _scoringService;

  DatabaseRecommendedPlacesService({
    PlaceRemoteSource? placeSource,
    ScoringService? scoringService,
  })  : _placeSource = placeSource ?? PlaceRemoteSource(),
        _scoringService = scoringService ?? ScoringService();

  static const double defaultRadiusMeters = 5000;
  static const int defaultMaxPerCategory = 8;

  Future<DayRecommendations> recommendForDay({
    required List<Place> dayPlaces,
    required List<String> interests,
    required Coordinates? destinationCenter,
    required Set<String> usedPlaceIds,
    required String transportMode,
    int maxPerCategory = defaultMaxPerCategory,
    double radiusMeters = defaultRadiusMeters,
  }) async {
    final anchors = _buildAnchors(
      dayPlaces: dayPlaces,
      destinationCenter: destinationCenter,
    );

    if (anchors.isEmpty) {
      return const DayRecommendations.empty();
    }

    final responses = await Future.wait(
      anchors.map(
        (anchor) => _placeSource.searchNearbyPlaces(
          latitude: anchor.latitude,
          longitude: anchor.longitude,
          radiusMeters: radiusMeters,
          types: null,
        ),
      ),
    );

    final merged = <String, Place>{};

    for (final places in responses) {
      for (final place in places) {
        final id = place.placeId.trim();
        final duration = place.visitDurationMinutes ?? 60;

        if (id.isEmpty) continue;
        if (usedPlaceIds.contains(id)) continue;
        if (!_hasValidCoordinates(place)) continue;
        if (place.placeName.trim().isEmpty) continue;
        if (duration <= 0) continue;

        final nearestKm = _nearestAnchorDistanceKm(place, anchors);

        // searchNearbyPlaces is a bounding-box query, so enforce the
        // requested circular radius again locally.
        if (nearestKm * 1000 > radiusMeters) continue;

        merged.putIfAbsent(id, () => place);
      }
    }

    if (merged.isEmpty) {
      return const DayRecommendations.empty();
    }

    final candidates = merged.values.toList();

    final scored = _scoringService.scorePlaces(
      places: candidates,
      selectedInterests: interests,
      mustVisitIds: const [],
      explorationTime: 'Standard',
      tripLocation: destinationCenter ?? anchors.first,
      strictInterestFilter: false,
    );

    final scoredById = {
      for (final item in scored) item.place.placeId: item,
    };

    final results = <NearbyPlaceResult>[];

    for (final place in candidates) {
      final scoredItem = scoredById[place.placeId];
      final baseScore = scoredItem?.score ?? 0;

      final nearestKm = _nearestAnchorDistanceKm(place, anchors);
      final travelMinutes = _estimateTravelMinutes(
        nearestKm,
        transportMode,
      );

      // Preference relevance is the main signal.
      // Distance is only a light penalty because candidates are already nearby.
      final rankScore =
          (baseScore / 100.0) * 0.75 -
          (travelMinutes.clamp(0.0, 120.0) * 0.002);

      results.add(
        NearbyPlaceResult(
          place: place,
          distanceFromPreviousKm: nearestKm,
          distanceToNextKm: null,
          estimatedAdditionalTravelMinutes: travelMinutes,
          rankScore: rankScore,
        ),
      );
    }

    results.sort((a, b) => b.rankScore.compareTo(a.rankScore));

    final attractions = <NearbyPlaceResult>[];
    final restaurants = <NearbyPlaceResult>[];

    for (final item in results) {
      if (_isRestaurant(item.place)) {
        if (restaurants.length < maxPerCategory) {
          restaurants.add(item);
        }
      } else {
        if (attractions.length < maxPerCategory) {
          attractions.add(item);
        }
      }

      if (attractions.length >= maxPerCategory &&
          restaurants.length >= maxPerCategory) {
        break;
      }
    }

    return DayRecommendations(
      attractions: List.unmodifiable(attractions),
      restaurants: List.unmodifiable(restaurants),
    );
  }

  List<Coordinates> _buildAnchors({
    required List<Place> dayPlaces,
    required Coordinates? destinationCenter,
  }) {
    final result = <Coordinates>[];
    final seen = <String>{};

    for (final place in dayPlaces) {
      if (!_hasValidCoordinates(place)) continue;

      final key =
          '${place.latitude.toStringAsFixed(6)},'
          '${place.longitude.toStringAsFixed(6)}';

      if (!seen.add(key)) continue;

      result.add(
        Coordinates(
          latitude: place.latitude,
          longitude: place.longitude,
        ),
      );
    }

    if (result.isEmpty && destinationCenter != null) {
      result.add(destinationCenter);
    }

    return result;
  }

  bool _isRestaurant(Place place) {
    final types = place.types
        .map((e) => e.toLowerCase().trim())
        .toSet();

    const restaurantTypes = {
      'restaurant',
      'cafe',
      'coffee_shop',
      'bakery',
      'bar',
      'meal_takeaway',
      'meal_delivery',
      'food',
    };

    if (types.any(restaurantTypes.contains)) return true;

    final category = (place.category ?? '').toLowerCase();

    return category.contains('restaurant') ||
        category.contains('cafe') ||
        category.contains('food') ||
        category.contains('dining');
  }

  bool _hasValidCoordinates(Place place) {
    return place.latitude.abs() <= 90 &&
        place.longitude.abs() <= 180 &&
        !(place.latitude == 0 && place.longitude == 0);
  }

  double _nearestAnchorDistanceKm(
    Place place,
    List<Coordinates> anchors,
  ) {
    final point = place.coordinates;
    var nearest = double.infinity;

    for (final anchor in anchors) {
      final distance = anchor.distanceTo(point);
      if (distance < nearest) nearest = distance;
    }

    return nearest;
  }

  double _estimateTravelMinutes(
    double distanceKm,
    String mode,
  ) {
    final normalized = mode.toLowerCase().trim();

    final speedKph = switch (normalized) {
      'walking' => 5.0,
      'driving' => 40.0,
      'transit' => 30.0,
      _ => 5.0,
    };

    return (distanceKm / speedKph) * 60.0;
  }

// ============================================================
  // FAST DETERMINISTIC PRE-CHECK (UI FILTERING)
  // ============================================================

  /// Extremely fast mathematical check to see if a place has any logical chance
  /// of fitting into the day's available hours.
  bool canPlaceFitLocally({
    required Place place,
    required List<ExistingStopContext> existingStops,
    required String explorationTime,
  }) {
    // 1. Get the total minutes available in the day (e.g., 9am to 8pm = 660 mins)
    final window = ItineraryConstants.explorationWindows[explorationTime] ??
        ItineraryConstants.explorationWindows['Standard']!;

    final totalWindowMinutes = window.endMinutes - window.startMinutes;

    // 2. Calculate time already used by existing stops
    int usedMinutes = 0;
    for (final stop in existingStops) {
      usedMinutes += stop.durationMinutes;
      usedMinutes += stop.travelFromPrevMinutes ?? 0;
    }

    // 3. Get the candidate's required time
    final candidateDuration = place.visitDurationMinutes ?? 60;
    final estimatedTravel = 20; // 20 mins rough travel estimate

    // 4. If the used time + new time exceeds the day's limit, it physically cannot fit
    return (usedMinutes + candidateDuration + estimatedTravel) <= totalWindowMinutes;
  }

}
