import 'package:flutter/foundation.dart';

import '../../../core/config/interest_mapping.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../data_sources/remote/places_remote_data_source.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import '../../entities/trip_request.dart';

class QueryDestination {
  final String name;
  final double latitude;
  final double longitude;

  const QueryDestination({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class CandidatePool {
  final List<Place> attractions;
  final List<Place> food;

  const CandidatePool({
    required this.attractions,
    required this.food,
  });

  List<Place> get all => List.unmodifiable([...attractions, ...food]);
  int get attractionCount => attractions.length;
  int get foodCount => food.length;
  int get totalCount => attractionCount + foodCount;

  Place? findByPlaceId(String placeId) {
    for (final place in all) {
      if (place.placeId == placeId) return place;
    }
    return null;
  }

  bool contains(String placeId) => findByPlaceId(placeId) != null;
}

class CandidateRetrievalService {
  final PlacesRemoteDataSource _placesDataSource;

  static const int requiredAttractions = 70;
  static const int requiredFood = 30;
  static const int requiredTotal = 100;

  static const List<String> foodTypes = [
    'restaurant',
    'cafe',
    'bakery',
    'meal_takeaway',
    'meal_delivery',
    'bar',
    'night_club',
    'wine_bar',
  ];

  CandidateRetrievalService({
    PlacesRemoteDataSource? placesDataSource,
  }) : _placesDataSource = placesDataSource ?? PlacesRemoteDataSource();

  Future<CandidatePool> retrieveCandidates({
    required TripRequest request,
  }) async {
    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint('════════════════════════════════════');
      debugPrint('📍 STEP 3 - CANDIDATE RETRIEVAL (CHAINING DISCOVERY)');
      debugPrint('════════════════════════════════════');
      debugPrint('🗺️ Destinations: ${request.destinations}');
      debugPrint('📅 Trip duration: ${request.duration} days');
      debugPrint('🚶 Travel pace: ${request.travelPace}');
      debugPrint('🎯 Interests: ${request.interests}');
    }

    // ============================================================
    // 1. CONVERT TRIP REQUEST DESTINATIONS
    // ============================================================

    final List<QueryDestination> destinations =
    request.destinations.map((name) {
      final coords =
          request.destinationCoordinates[name] ??
              request.tripLocation ??
              const Coordinates(
                latitude: 3.139,
                longitude: 101.687,
              );

      return QueryDestination(
        name: name,
        latitude: coords.latitude,
        longitude: coords.longitude,
      );
    }).toList();

    // ============================================================
    // 2. READ TRIP REQUEST VALUES
    // ============================================================

    final List<String> selectedInterests = request.interests;

    final int tripDays = request.duration;

    // ============================================================
    // 3. CONVERT TRAVEL PACE
    // ============================================================

    int? pace;

    switch (request.travelPace.toLowerCase().trim()) {
      case 'slow':
      case 'slow-paced':
      case 'relaxed':
        pace = 2;
        break;

      case 'standard':
      case 'balanced':
      case 'medium':
        pace = 4;
        break;

      case 'fast':
      case 'fast-paced':
        pace = 6;
        break;

      default:
        pace = 4;
    }

    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint('📍 Query destinations: ${destinations.length}');
      debugPrint('📅 Trip days: $tripDays');
      debugPrint('🚶 Parsed pace: $pace');
    }

    // ============================================================
    // 4. RESOLVE INTEREST TYPES
    // ============================================================

    final attractionTypes = <String>{};

    for (final interest in selectedInterests) {
      attractionTypes.addAll(
        InterestMapping.getGoogleTypesForInterest(interest),
      );
    }

    // Remove food-related types from attraction search.
    attractionTypes.removeWhere(foodTypes.contains);

    // Always include general attraction categories.
    attractionTypes.addAll([
      'tourist_attraction',
      'museum',
      'art_gallery',
      'park',
      'garden',
      'zoo',
      'aquarium',
      'amusement_park',
      'water_park',
      'bowling_alley',
      'stadium',
      'place_of_worship',
      'church',
      'hindu_temple',
      'mosque',
      'shopping_mall',
      'clothing_store',
      'department_store',
      'book_store',
      'movie_theater',
      'night_club',
      'casino',
      'beach',
    ]);

    // ============================================================
    // 5. RAW CANDIDATE COLLECTION
    // ============================================================

    final List<Place> rawAttractions = [];
    final List<Place> rawFood = [];

    // Prevent searching the exact same coordinate repeatedly.
    final Set<String> searchedCenterKeys = {};

    // ============================================================
    // 6. INITIAL SEARCH QUEUE
    // ============================================================

    final List<Coordinates> searchQueue = destinations
        .map(
          (destination) => Coordinates(
        latitude: destination.latitude,
        longitude: destination.longitude,
      ),
    )
        .toList();

    CandidatePool currentPool = const CandidatePool(
      attractions: [],
      food: [],
    );

    // Initial radius.
    var searchRadiusKm = ItineraryConstants.searchRadiusKm;

    // ============================================================
    // 7. CHAINING DISCOVERY
    // ============================================================

    for (
    int hop = 0;
    hop <= ItineraryConstants.maxExpansionAttempts;
    hop++
    ) {
      if (searchQueue.isEmpty) {
        break;
      }

      // Take current queue and clear it.
      final currentHopCenters =
      List<Coordinates>.from(searchQueue);

      searchQueue.clear();

      // ==========================================================
      // SEARCH EACH CENTER
      // ==========================================================

      for (final center in currentHopCenters) {
        final centerKey =
            '${center.latitude.toStringAsFixed(4)},'
            '${center.longitude.toStringAsFixed(4)}';

        // Skip duplicate search center.
        if (!searchedCenterKeys.add(centerKey)) {
          continue;
        }

        if (ItineraryConstants.enableCandidateDebugLogs) {
          debugPrint(
            '[STEP 3 - SEARCH] '
                'Center @ ${center.latitude}, ${center.longitude} '
                '(Radius: ${searchRadiusKm}km, Hop: $hop)',
          );
        }

        // --------------------------------------------------------
        // SEARCH ATTRACTIONS
        // --------------------------------------------------------

        final newAttractions =
        await _placesDataSource.searchNearbyPlaces(
          latitude: center.latitude,
          longitude: center.longitude,
          radiusMeters: searchRadiusKm * 1000,
          types: attractionTypes.toList(),
        );

        // --------------------------------------------------------
        // SEARCH FOOD
        // --------------------------------------------------------

        final newFood =
        await _placesDataSource.searchNearbyPlaces(
          latitude: center.latitude,
          longitude: center.longitude,
          radiusMeters: searchRadiusKm * 1000,
          types: foodTypes,
        );

        rawAttractions.addAll(newAttractions);
        rawFood.addAll(newFood);

        if (ItineraryConstants.enableCandidateDebugLogs) {
          debugPrint(
            '[STEP 3 - RESULT] '
                'Found ${newAttractions.length} attractions, '
                '${newFood.length} food',
          );
        }
      }

      // ==========================================================
      // 8. BASIC HYGIENE FILTERING
      // ==========================================================

      var filteredAttractions =
      _applyBasicFiltering(rawAttractions);

      var filteredFood =
      _applyBasicFiltering(rawFood);

      if (ItineraryConstants.enableCandidateDebugLogs) {
        debugPrint(
          '[STEP 3 - BASIC FILTER] '
              'Attractions: ${filteredAttractions.length}, '
              'Food: ${filteredFood.length}',
        );
      }

      // ==========================================================
      // 9. SPATIAL DIVERSITY FILTERING
      // ==========================================================

      filteredAttractions =
          _applySpatialFiltering(
            filteredAttractions,
            0.5,
          );

      filteredFood =
          _applySpatialFiltering(
            filteredFood,
            0.1,
          );

      // ==========================================================
      // 10. BUILD CURRENT POOL
      // ==========================================================

      currentPool = CandidatePool(
        attractions: filteredAttractions,
        food: filteredFood,
      );

      if (ItineraryConstants.enableCandidateDebugLogs) {
        debugPrint(
          '[STEP 3 - POOL] '
              'Attractions: ${currentPool.attractionCount}/'
              '$requiredAttractions, '
              'Food: ${currentPool.foodCount}/'
              '$requiredFood',
        );
      }

      // ==========================================================
      // 11. CHECK WHETHER ENOUGH CANDIDATES EXIST
      // ==========================================================

      final bool isSufficient =
          currentPool.attractionCount >= requiredAttractions &&
              currentPool.foodCount >= requiredFood;

      if (isSufficient) {
        if (ItineraryConstants.enableCandidateDebugLogs) {
          debugPrint(
            '✅ SUFFICIENT - '
                'Reached candidate targets with chaining discovery.',
          );
        }

        return _enforceRatio(currentPool);
      }

      // ==========================================================
      // 12. EXPAND SEARCH USING ACCEPTED CANDIDATES
      // ==========================================================

      if (hop < ItineraryConstants.maxExpansionAttempts) {
        if (ItineraryConstants.enableCandidateDebugLogs) {
          debugPrint(
            '⚠️ INSUFFICIENT '
                '(${currentPool.attractionCount}/'
                '$requiredAttractions attractions, '
                '${currentPool.foodCount}/'
                '$requiredFood food). '
                'Chaining from filtered candidates...',
          );
        }

        // --------------------------------------------------------
        // Add accepted attractions as new search centers.
        // --------------------------------------------------------

        for (final place in currentPool.attractions) {
          final placeKey =
              '${place.placeLatitude.toStringAsFixed(4)},'
              '${place.placeLongitude.toStringAsFixed(4)}';

          if (!searchedCenterKeys.contains(placeKey)) {
            searchQueue.add(
              Coordinates(
                latitude: place.placeLatitude,
                longitude: place.placeLongitude,
              ),
            );
          }
        }

        // --------------------------------------------------------
        // Keep expansion radius controlled.
        // --------------------------------------------------------

        searchRadiusKm = 15.0;
      }
    }

    // ============================================================
    // 13. FINAL FALLBACK
    // ============================================================

    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint(
        '⚠️ INSUFFICIENT AFTER ALL HOPS - '
            'Returning best available pool with strict 70/30 ratio.',
      );
    }

    return _enforceRatio(currentPool);
  }

  // ------------------------------------------------------------
  // Filtering & Processing
  // ------------------------------------------------------------

  List<Place> _applyBasicFiltering(List<Place> places) {
    final seenIds = <String>{};
    final valid = <Place>[];

    for (final place in places) {
      if (place.placeId.isEmpty || place.placeName.isEmpty) continue;
      if (place.placeLatitude == 0 && place.placeLongitude == 0) continue;

      // 🛑 NEW: Hard Ban on Hotels and Accommodations
      // 'lodging' is Google's universal tag for hotels, hostels, and motels.
      if (place.types.contains('lodging')) {
        continue; // Instantly reject this place
      }

      if (ItineraryConstants.deduplicateByPlaceId && !seenIds.add(place.placeId)) {
        continue;
      }

      // ... rest of your rating checks ...

      valid.add(place);
    }
    return valid;
  }

  List<Place> _applySpatialFiltering(List<Place> places, double minDistanceKm) {
    final List<Place> diversifiedPool = [];

    // Prioritize higher-rated places so they secure geographic territory first
    final sortedPlaces = List<Place>.from(places)
      ..sort((a, b) => b.placeRating.compareTo(a.placeRating));

    for (final place in sortedPlaces) {
      final currentCoords = Coordinates(
        latitude: place.placeLatitude,
        longitude: place.placeLongitude,
      );

      bool isTooClose = false;
      for (final accepted in diversifiedPool) {
        final acceptedCoords = Coordinates(
          latitude: accepted.placeLatitude,
          longitude: accepted.placeLongitude,
        );

        if (currentCoords.distanceTo(acceptedCoords) < minDistanceKm) {
          isTooClose = true;
          break;
        }
      }

      if (!isTooClose) {
        diversifiedPool.add(place);
      }
    }
    return diversifiedPool;
  }

// REPLACE WITH THIS:
  CandidatePool _enforceRatio(CandidatePool pool) {
    // If we have fewer than 50 attractions, don't delete anything!
    // We need all the candidates we can get for clustering.
    if (pool.attractions.length < 50) {
      return pool;
    }

    // Otherwise, only trim if the pool is excessively large (e.g. > 100)
    List<Place> finalAttractions = List.from(pool.attractions);
    if (finalAttractions.length > 100) {
      finalAttractions = finalAttractions.sublist(0, 100);
    }

    return CandidatePool(
      attractions: finalAttractions,
      food: pool.food,
    );
  }
}