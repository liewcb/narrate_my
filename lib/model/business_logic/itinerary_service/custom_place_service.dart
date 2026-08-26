// lib/model/business_logic/itinerary_service/custom_place_service.dart
//
// Business logic for the "Add Custom Place" workflow.
//
// Responsibilities:
//   - Determine the insertion anchors (previous/next stop) for a day.
//   - Retrieve nearby eligible places around those anchors.
//   - Filter duplicates / invalid places / opening-hour conflicts.
//   - Rank candidates by detour + preference.
//   - Plan the AI-assisted insertion and validate the result.

import 'package:flutter/foundation.dart';

import '../../../core/config/interest_mapping.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/google_maps_service.dart';
import '../../data_sources/remote/places_remote_data_source.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import 'anchor_selection_service.dart';
import 'place_registry.dart';
import 'route_optimization_service.dart';
import 'schedule_construction_service.dart';
import 'scoring_service.dart';
import 'validation_service.dart';

/// The spatial anchors around an insertion position.
///
/// Both may be null (empty day), or either one may be null
/// (insert at start / insert at end).
class InsertionAnchors {
  final Place? previousStop;
  final Place? nextStop;

  const InsertionAnchors({this.previousStop, this.nextStop});

  bool get hasBoth => previousStop != null && nextStop != null;
}

/// A nearby place candidate with ranking metadata for the UI.
class NearbyPlaceResult {
  final Place place;
  final double? distanceFromPreviousKm;
  final double? distanceToNextKm;
  final double estimatedAdditionalTravelMinutes;
  final double rankScore;

  const NearbyPlaceResult({
    required this.place,
    this.distanceFromPreviousKm,
    this.distanceToNextKm,
    this.estimatedAdditionalTravelMinutes = 0,
    this.rankScore = 0,
  });
}

/// Distance/proximity information shown to the user for a searched place.
class PlaceProximityInfo {
  final Place place;
  final double distanceFromItineraryKm;
  final String proximity; // 'Near' | 'Moderate' | 'Far'
  final int travelMinutes;
  final String travelText;

  const PlaceProximityInfo({
    required this.place,
    required this.distanceFromItineraryKm,
    required this.proximity,
    required this.travelMinutes,
    required this.travelText,
  });
}

/// Result of planning the insertion of one place into a day.
class CustomPlacePlanResult {
  final bool success;
  final String? message;
  final ScheduledDay? proposedDay;
  final ValidationResult? validation;
  final List<ScoredAttraction>? orderedAttractions;

  const CustomPlacePlanResult({
    required this.success,
    this.message,
    this.proposedDay,
    this.validation,
    this.orderedAttractions,
  });
}

/// Business logic service for adding a custom place to an existing day.
class CustomPlaceService {
  final PlacesRemoteDataSource _placesDataSource;
  final GoogleMapsService _mapsService;
  final AIService _aiService;
  final ScoringService _scoringService;

  CustomPlaceService({
    PlacesRemoteDataSource? placesDataSource,
    GoogleMapsService? mapsService,
    AIService? aiService,
    ScoringService? scoringService,
  })  : _placesDataSource = placesDataSource ?? PlacesRemoteDataSource(),
        _mapsService = mapsService ?? GoogleMapsService(),
        _aiService = aiService ?? AIService(),
        _scoringService = scoringService ?? ScoringService();

  // ============================================================
  // 1. DETERMINE PREVIOUS / NEXT STOP
  // ============================================================

  /// Determine the previous/next stop for an insertion position.
  ///
  /// [dayStops] must be sorted in route order. [insertIndex] is the index
  /// at which the new place should be inserted (0-based). All edge cases
  /// (start, end, empty day) are handled without crashing.
  InsertionAnchors determineAnchors({
    required List<Place> dayStops,
    required int insertIndex,
  }) {
    if (dayStops.isEmpty) {
      return const InsertionAnchors(previousStop: null, nextStop: null);
    }

    final clamped = insertIndex.clamp(0, dayStops.length);
    final previous = clamped > 0 ? dayStops[clamped - 1] : null;
    final next = clamped < dayStops.length ? dayStops[clamped] : null;
    return InsertionAnchors(previousStop: previous, nextStop: next);
  }

  // ============================================================
  // 2. NEARBY PLACE RETRIEVAL
  // ============================================================

  /// Search Google Places by free-text query (the user types a name).
  ///
  /// Uses the existing Google Places text-search service. The search is
  /// biased towards the itinerary day's location when available, but the
  /// query is the primary input — the user is NOT required to type
  /// coordinates, URLs or lat/lng.
  Future<List<Place>> searchPlaces({
    required String query,
    Coordinates? locationBias,
  }) async {
    if (query.trim().isEmpty) return const [];
    return await _mapsService.searchTextPlaces(
      query: query.trim(),
      latitude: locationBias?.latitude,
      longitude: locationBias?.longitude,
    );
  }

  /// Compute distance/proximity information for a searched place relative
  /// to the itinerary day's existing stops.
  ///
  /// Distance is user information/warning only — it is NOT a rejection
  /// criterion. Near/Moderate/Far thresholds are deliberately simple and
  /// easy to adjust.
  Future<PlaceProximityInfo> evaluateProximity({
    required Place place,
    required List<Place> existingDayPlaces,
    required String transportMode,
  }) async {
    // Anchor = nearest existing stop (or the first stop as fallback).
    Coordinates? anchor;
    double nearestKm = double.infinity;
    for (final stop in existingDayPlaces) {
      final d = stop.coordinates.distanceTo(place.coordinates);
      if (d < nearestKm) {
        nearestKm = d;
        anchor = stop.coordinates;
      }
    }
    if (anchor == null) {
      anchor = place.coordinates; // empty day → distance 0
      nearestKm = 0;
    }

    final travel = await _getTravelTime(anchor, place.coordinates, transportMode);

    final proximity = nearestKm < 3.0
        ? 'Near'
        : nearestKm < 10.0
            ? 'Moderate'
            : 'Far';

    return PlaceProximityInfo(
      place: place,
      distanceFromItineraryKm: nearestKm,
      proximity: proximity,
      travelMinutes: travel.ceil(),
      travelText: '${travel.ceil()} min',
    );
  }

  /// Retrieve places geographically near the insertion anchors.
  ///
  /// Search strategy:
  ///   - Both anchors: search around previous stop, then around next stop,
  ///     merge + dedupe + rank (a place close to both ranks higher).
  ///   - Only next stop: search around the next stop.
  ///   - Only previous stop: search around the previous stop.
  ///   - No stops: use [fallbackCenter] (the day's destination).
  Future<List<Place>> retrieveNearbyPlaces({
    required InsertionAnchors anchors,
    required List<String> interests,
    required Coordinates? fallbackCenter,
    double radiusMeters = ItineraryConstants.customPlaceSearchRadiusMeters,
  }) async {
    final centers = <Coordinates>{};

    if (anchors.previousStop != null) {
      centers.add(anchors.previousStop!.coordinates);
    }
    if (anchors.nextStop != null) {
      centers.add(anchors.nextStop!.coordinates);
    }
    if (centers.isEmpty && fallbackCenter != null) {
      centers.add(fallbackCenter);
    }
    if (centers.isEmpty) {
      return const [];
    }

    // Resolve Google place types from the traveler's interests.
    final types = _resolveSearchTypes(interests);
    final merged = <String, Place>{};

    for (final center in centers) {
      try {
        final found = await _placesDataSource.searchNearbyPlaces(
          latitude: center.latitude,
          longitude: center.longitude,
          radiusMeters: radiusMeters,
          types: types,
        );
        for (final place in found) {
          merged.putIfAbsent(place.placeId, () => place);
        }
      } catch (e) {
        debugPrint('[CustomPlace] nearby search failed around $center: $e');
      }
    }

    return merged.values.toList();
  }

  List<String> _resolveSearchTypes(List<String> interests) {
    final types = <String>{};
    for (final interest in interests) {
      types.addAll(InterestMapping.getGoogleTypesForInterest(interest));
    }
    if (types.isEmpty) {
      types.add('tourist_attraction');
    }
    // Keep the set bounded to avoid extremely long API queries.
    return types.take(8).toList();
  }

  // ============================================================
  // 3. CANDIDATE FILTERING
  // ============================================================

  /// Filter out places that are not eligible for insertion.
  ///
  /// Checks (minimally):
  ///   - not already used in the itinerary
  ///   - has required identity info (id, name, coordinates)
  ///   - opening hours compatible with the selected day (when available)
  List<Place> filterCandidates({
    required List<Place> candidates,
    required Set<String> usedPlaceIds,
    int? dayOfWeek, // 1 = Monday ... 7 = Sunday (DateTime.weekday)
  }) {
    return candidates.where((place) {
      // Valid identity.
      if (place.placeId.isEmpty || place.placeName.isEmpty) return false;
      // Coordinates present.
      if (place.latitude == 0 && place.longitude == 0) return false;
      // Duplicate — already used in the itinerary.
      if (usedPlaceIds.contains(place.placeId)) return false;
      // Opening hours (only when known).
      if (dayOfWeek != null && place.openingHours != null) {
        if (!place.openingHours!.isOpenOnDay(dayOfWeek)) return false;
      }
      return true;
    }).toList();
  }

  // ============================================================
  // 4. CANDIDATE RANKING
  // ============================================================

  /// Rank candidates by detour minimization and preference score.
  ///
  /// A candidate that requires a small detour from
  /// `Previous → Candidate → Next` ranks higher.
  List<NearbyPlaceResult> rankCandidates({
    required List<Place> candidates,
    required InsertionAnchors anchors,
    required List<String> interests,
    required Coordinates? tripLocation,
    required String transportMode,
  }) {
    final scored = _scoringService.scorePlaces(
      places: candidates,
      selectedInterests: interests,
      mustVisitIds: const [],
      explorationTime: 'Standard',
      tripLocation: tripLocation,
    );

    final results = <NearbyPlaceResult>[];

    for (final s in scored) {
      final place = s.place;
      final prev = anchors.previousStop;
      final next = anchors.nextStop;

      final distPrev = prev != null ? prev.coordinates.distanceTo(place.coordinates) : null;
      final distNext = next != null ? place.coordinates.distanceTo(next.coordinates) : null;

      // Baseline straight-line distance of the original segment.
      double baseline = 0;
      if (prev != null && next != null) {
        baseline = prev.coordinates.distanceTo(next.coordinates);
      }

      // Detour = added distance caused by inserting the candidate.
      double detour = 0;
      if (prev != null && next != null) {
        detour = (distPrev! + distNext!) - baseline;
        if (detour < 0) detour = 0;
      } else if (prev != null && distPrev != null) {
        detour = distPrev;
      } else if (next != null && distNext != null) {
        detour = distNext;
      }

      // Estimated additional travel time (straight-line + mode speed).
      final travelMinutes = _estimateTravelMinutes(detour, transportMode);

      // Combine preference (0..1) with detour penalty.
      final rankScore = (s.score / 100) * 0.7 - (detour * 0.05);

      results.add(NearbyPlaceResult(
        place: place,
        distanceFromPreviousKm: distPrev,
        distanceToNextKm: distNext,
        estimatedAdditionalTravelMinutes: travelMinutes,
        rankScore: rankScore,
      ));
    }

    results.sort((a, b) => b.rankScore.compareTo(a.rankScore));
    return results;
  }

  double _estimateTravelMinutes(double distanceKm, String mode) {
    final speedKph = switch (mode) {
      'walking' => 5.0,
      'driving' => 40.0,
      'transit' => 30.0,
      _ => 5.0,
    };
    return (distanceKm / speedKph) * 60.0;
  }

  // ============================================================
  // 5. AI PLANNING + DETERMINISTIC VALIDATION
  // ============================================================

  /// Plan the insertion of [newPlace] into an existing day and validate
  /// the resulting schedule.
  ///
  /// The existing day's places plus the new place are sent to the AI
  /// (route order + schedule). The AI output is reconstructed from the
  /// original [Place] objects and validated against hard constraints.
  Future<CustomPlacePlanResult> planInsertion({
    required int dayIndex, // 0-based day index used by the pipeline
    required DateTime date,
    required List<Place> existingDayPlaces,
    required Place newPlace,
    required String explorationTime,
    required String transportMode,
    required String travelPace,
    required List<String> interests,
    Coordinates? tripLocation,
  }) async {
    // Build the candidate set: existing day + new place.
    final allPlaces = <Place>[...existingDayPlaces, newPlace];

    // Registry — the source of truth for place data (AI never invents).
    final registry = PlaceRegistry()..addAll(allPlaces);

    // Score so the day has an anchor.
    final scored = _scoringService.scorePlaces(
      places: allPlaces,
      selectedInterests: interests,
      mustVisitIds: const [],
      explorationTime: explorationTime,
      tripLocation: tripLocation,
    );

    if (scored.isEmpty) {
      return CustomPlacePlanResult(
        success: false,
        message: 'No places to plan.',
      );
    }

    final anchor = scored.first;
    final plan = DailyPlan(
      dayIndex: dayIndex,
      anchor: anchor,
      attractions: scored,
      date: date,
      isThemeParkDay: false,
    );

    // 1. AI-assisted route ordering.
    final routeService = RouteOptimizationService(aiService: _aiService);
    final optimized = await routeService.optimizeRoutes(
      dailyPlans: [plan],
      registry: registry,
      travelPace: travelPace,
      interests: interests,
      tripLocation: tripLocation,
    );

    // 2. Schedule construction (AI-assisted, deterministic fallback).
    final scheduleService = ScheduleConstructionService(
      mapsService: _mapsService,
      aiService: _aiService,
    );
    final scheduledDays = await scheduleService.constructSchedule(
      dailyPlans: optimized,
      explorationTime: explorationTime,
      transportMode: transportMode,
      useAi: true,
      travelPace: travelPace,
    );

    if (scheduledDays.isEmpty) {
      return CustomPlacePlanResult(
        success: false,
        message: 'Could not build a schedule for the day.',
      );
    }

    final proposedDay = scheduledDays.first;

    // 3. Deterministic validation (must-pass before applying).
    final validation = ValidationService().validate(
      scheduledDays: [proposedDay],
      mustVisitIds: const [],
      explorationTime: explorationTime,
    );

    return CustomPlacePlanResult(
      success: validation.passed,
      message: validation.passed
          ? null
          : (validation.issues.isEmpty
              ? 'Validation failed.'
              : validation.issues.first.message),
      proposedDay: proposedDay,
      validation: validation,
      orderedAttractions: optimized.isNotEmpty ? optimized.first.attractions : null,
    );
  }

  /// Get actual travel time (minutes) between two coordinates.
  Future<double> _getTravelTime(
    Coordinates origin,
    Coordinates destination,
    String mode,
  ) async {
    try {
      final info = await _mapsService.getTravelTime(
        origin: origin,
        destination: destination,
        mode: mode,
      );
      return info.durationMinutes;
    } catch (e) {
      // Fallback: straight-line estimate (never the schedule authority).
      final km = origin.distanceTo(destination);
      final speedKph = switch (mode) {
        'walking' => 5.0,
        'driving' => 40.0,
        'transit' => 30.0,
        _ => 5.0,
      };
      return (km / speedKph) * 60.0;
    }
  }
}
