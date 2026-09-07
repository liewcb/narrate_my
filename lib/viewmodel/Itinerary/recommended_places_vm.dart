// lib/viewmodel/Itinerary/recommended_places_vm.dart
//
// DB-FIRST Recommended Places.
//
// Recommendation loading:
//   Supabase `places`
//      -> selected-day stops as spatial anchors
//      -> exact distance filtering
//      -> remove globally-used place IDs
//      -> local preference/rating/distance ranking
//      -> FAST DART PRE-CHECK (mathematical feasibility)
//      -> Attractions / Restaurants
//
// Selection:
//   DB candidate
//      -> ONE AI request
//      -> AI ACCEPT/REJECT + insertion position + time
//      -> temporary ScheduledDay
//
// No database writes happen in this ViewModel.

import 'package:flutter/foundation.dart';

import '../../model/business_logic/itinerary_service/ai_place_insertion_service.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/database_recommended_places_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/business_logic/itinerary_service/scoring_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/place.dart';

enum RecommendationCategory {
  attractions,
  restaurants,
}

class RecommendedPlacesVM extends ChangeNotifier {
  static const int minimumRecommendations = 3;
  static const int maximumRecommendations = 8;

  final int dayNumber;
  final DateTime dayDate;
  final List<ExistingStopContext> existingStops;
  final Set<String> usedPlaceIds;
  final List<String> interests;
  final String transportMode;
  final String explorationTime;
  final String travelPace;
  final Coordinates? destinationCenter;

  final DatabaseRecommendedPlacesService _databaseService;
  final AiPlaceInsertionService _aiInsertionService;
  final CustomPlaceService _customPlaceService; // ✅ Added to inject pre-check

  static const Duration aiTimeout = Duration(seconds: 6);

  RecommendedPlacesVM({
    required this.dayNumber,
    required this.dayDate,
    required this.existingStops,
    required this.usedPlaceIds,
    required this.interests,
    required this.transportMode,
    required this.explorationTime,
    required this.travelPace,
    this.destinationCenter,
    DatabaseRecommendedPlacesService? databaseService,
    AiPlaceInsertionService? aiInsertionService,
    CustomPlaceService? customPlaceService,
  })  : _databaseService =
      databaseService ?? DatabaseRecommendedPlacesService(),
        _aiInsertionService =
            aiInsertionService ?? AiPlaceInsertionService(),
        _customPlaceService =
            customPlaceService ?? CustomPlaceService();

  bool isLoadingRecommendations = false;
  String? recommendationsError;
  bool _recommendationsLoaded = false;

  List<NearbyPlaceResult> _attractions = const [];
  List<NearbyPlaceResult> _restaurants = const [];

  Place? _selectedPlace;
  bool isPlanning = false;
  String? planError;
  CustomPlacePlanResult? _planResult;

  List<NearbyPlaceResult> get attractions => _attractions;
  List<NearbyPlaceResult> get restaurants => _restaurants;
  bool get recommendationsLoaded => _recommendationsLoaded;
  Place? get selectedPlace => _selectedPlace;
  CustomPlacePlanResult? get planResult => _planResult;

  // Keep this API for the existing screen.
  // Bookmark state is intentionally not changed by this DB-first rewrite.
  bool isBookmarked(String placeId) => false;

  List<NearbyPlaceResult> forCategory(
      RecommendationCategory category,
      ) {
    return category == RecommendationCategory.attractions
        ? _attractions
        : _restaurants;
  }

  Future<void> loadRecommendations() async {
    if (_recommendationsLoaded || isLoadingRecommendations) return;

    isLoadingRecommendations = true;
    recommendationsError = null;
    notifyListeners();

    try {
      final dayPlaces = existingStops.map((stop) => stop.place).toList();

      final result = await _databaseService.recommendForDay(
        dayPlaces: dayPlaces,
        interests: interests,
        destinationCenter: destinationCenter,
        usedPlaceIds: usedPlaceIds,
        transportMode: transportMode,
        maxPerCategory: 15, // Retrieve more initially so we can filter them down
      );

      // ✅ DART FAST PRE-CHECK FILTER: Hide places that exceed the day's hours
      final filteredAttractions = result.attractions.where((candidate) {
        return _databaseService.canPlaceFitLocally(
          place: candidate.place,
          existingStops: existingStops,
          explorationTime: explorationTime,
        );
      }).toList();

      // ✅ DART FAST PRE-CHECK FILTER
      final filteredRestaurants = result.restaurants.where((candidate) {
        return _databaseService.canPlaceFitLocally(
          place: candidate.place,
          existingStops: existingStops,
          explorationTime: explorationTime,
        );
      }).toList();

      _attractions = _cleanResults(filteredAttractions);
      _restaurants = _cleanResults(filteredRestaurants);
      _recommendationsLoaded = true;

      if (_attractions.isEmpty && _restaurants.isEmpty) {
        recommendationsError =
        'No recommended places are available in the database for this day.';
      }
    } catch (e, stack) {
      debugPrint('[Recommended Places DB] load failed: $e');
      debugPrintStack(stackTrace: stack);

      recommendationsError =
      'Unable to load recommended places from the database. '
          'Please try again.';
    } finally {
      isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  Future<void> selectAndPlan(Place place) async {
    if (isPlanning) return;

    final id = place.placeId.trim();

    if (id.isEmpty) {
      planError = 'This place does not have a valid place ID.';
      notifyListeners();
      return;
    }

    if (usedPlaceIds.contains(id)) {
      planError = 'This place is already used in your itinerary.';
      notifyListeners();
      return;
    }

    if (!_hasValidCoordinates(place)) {
      planError = 'This place does not have valid location data.';
      notifyListeners();
      return;
    }

    final defaultDuration = place.visitDurationMinutes ?? 60;
    if (defaultDuration <= 0) {
      planError = 'This place does not have a valid visit duration.';
      notifyListeners();
      return;
    }

    _selectedPlace = place;
    _planResult = null;
    planError = null;
    isPlanning = true;
    notifyListeners();

    try {
      final aiResult = await _aiInsertionService.validateAndPlan(
        dayIndex: dayNumber,
        date: dayDate,
        existingStops: existingStops,
        newPlace: place,
        defaultDurationMinutes: defaultDuration,
        explorationTime: explorationTime,
        transportMode: transportMode,
        travelPace: travelPace,
        interests: interests,
        tripLocation: destinationCenter ?? _centroidOfStops(),
        timeout: aiTimeout,
      );

      if (aiResult == null) {
        planError =
        'The AI validation timed out or failed. Please try another place.';
        _planResult = null;
        return;
      }

      if (!aiResult.accepted) {
        planError = aiResult.reason.isEmpty
            ? 'The AI determined that this place does not fit this day.'
            : aiResult.reason;

        _planResult = CustomPlacePlanResult.problem(planError!);
        return;
      }

      final insertIndex = _resolveInsertIndex(aiResult);

      if (insertIndex == null) {
        planError =
        'The AI returned an invalid insertion position. Please try again.';
        _planResult = null;
        return;
      }

      // The AI parser guarantees these are present for ACCEPT.
      final startTime = aiResult.startTime;
      final endTime = aiResult.endTime;

      if (startTime == null || endTime == null) {
        planError =
        'The AI returned an incomplete schedule. Please try again.';
        _planResult = null;
        return;
      }

      final proposedDay = _buildAiScheduledDay(
        insertIndex: insertIndex,
        place: place,
        durationMinutes: aiResult.durationMinutes,
        startTime: startTime,
        endTime: endTime,
        travelFromPreviousMinutes:
        aiResult.travelFromPreviousMinutes ?? 0,
        reason: aiResult.reason,
      );

      _planResult = CustomPlacePlanResult(
        success: true,
        proposedDay: proposedDay,
        validation: null,
        insertIndex: insertIndex,
        usedAi: true,
      );
    } catch (e, stack) {
      debugPrint('[Recommended Places AI] planning failed: $e');
      debugPrintStack(stackTrace: stack);

      _planResult = null;
      planError = 'AI validation failed. Please try another place.';
    } finally {
      isPlanning = false;
      notifyListeners();
    }
  }

  ScheduledDay? confirmedProposedDay() {
    if (_planResult?.success != true) return null;
    return _planResult!.proposedDay;
  }

  void clearSelection() {
    _selectedPlace = null;
    _planResult = null;
    planError = null;
    isPlanning = false;
    notifyListeners();
  }

  List<NearbyPlaceResult> _cleanResults(
      List<NearbyPlaceResult> source,
      ) {
    final seen = <String>{};
    final cleaned = <NearbyPlaceResult>[];

    for (final result in source) {
      final place = result.place;
      final id = place.placeId.trim();
      final duration = place.visitDurationMinutes ?? 60;

      if (id.isEmpty) continue;
      if (usedPlaceIds.contains(id)) continue;
      if (!seen.add(id)) continue;
      if (!_hasValidCoordinates(place)) continue;
      if (place.placeName.trim().isEmpty) continue;
      if (duration <= 0) continue;

      cleaned.add(result);

      if (cleaned.length >= maximumRecommendations) break;
    }

    return List.unmodifiable(cleaned);
  }

  int? _resolveInsertIndex(AiPlaceInsertionResult result) {
    final afterId = result.insertAfterPlaceId;

    // null = insert before the first stop.
    if (afterId == null || afterId.isEmpty) {
      return 0;
    }

    final index = existingStops.indexWhere(
          (stop) => stop.place.placeId == afterId,
    );

    if (index < 0) return null;

    return index + 1;
  }

  ScheduledDay _buildAiScheduledDay({
    required int insertIndex,
    required Place place,
    required int durationMinutes,
    required DateTime startTime,
    required DateTime endTime,
    required int travelFromPreviousMinutes,
    required String reason,
  }) {
    final stops = <ScheduledStop>[];

    for (var i = 0; i <= existingStops.length; i++) {
      if (i == insertIndex) {
        stops.add(
          ScheduledStop(
            attraction: ScoredAttraction(
              place: place,
              score: 0,
              breakdown: const {},
            ),
            startTime: startTime,
            endTime: endTime,
            durationMinutes: durationMinutes,
            travelFromPreviousMinutes: travelFromPreviousMinutes,
            scheduleReason: reason,
            weatherNote: '',
          ),
        );
      }

      if (i < existingStops.length) {
        final existing = existingStops[i];

        stops.add(
          ScheduledStop(
            attraction: ScoredAttraction(
              place: existing.place,
              score: 0,
              breakdown: const {},
            ),
            startTime: existing.startTime,
            endTime: existing.endTime,
            durationMinutes: existing.durationMinutes,
            travelFromPreviousMinutes: existing.travelFromPrevMinutes,
            scheduleReason: '',
            weatherNote: '',
          ),
        );
      }
    }

    final totalDuration = stops.fold<int>(
      0,
          (sum, stop) => sum + stop.durationMinutes,
    );

    final totalTravelTime = stops.fold<double>(
      0,
          (sum, stop) => sum + stop.travelFromPreviousMinutes,
    );

    return ScheduledDay(
      dayIndex: dayNumber,
      date: dayDate,
      stops: stops,
      totalDuration: totalDuration,
      totalTravelTime: totalTravelTime,
    );
  }

  Coordinates? _centroidOfStops() {
    var lat = 0.0;
    var lng = 0.0;
    var count = 0;

    for (final stop in existingStops) {
      final place = stop.place;

      if (!_hasValidCoordinates(place)) continue;

      lat += place.latitude;
      lng += place.longitude;
      count++;
    }

    if (count == 0) return null;

    return Coordinates(
      latitude: lat / count,
      longitude: lng / count,
    );
  }

  bool _hasValidCoordinates(Place place) {
    return place.latitude.abs() <= 90 &&
        place.longitude.abs() <= 180 &&
        !(place.latitude == 0 && place.longitude == 0);
  }
}