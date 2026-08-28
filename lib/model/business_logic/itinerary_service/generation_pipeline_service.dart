// lib/model/business_logic/itinerary_service/itinerary_generation_pipeline.dart

import 'package:flutter/foundation.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/weather_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/trip_request.dart';
import '../../entities/weather.dart';
import 'candidate_retrieval_service.dart';
import 'anchor_selection_service.dart';
import 'clustering_service.dart';
import 'place_registry.dart';
import 'route_optimization_service.dart';
import 'schedule_construction_service.dart';
import 'scoring_service.dart';
import 'validation_service.dart';

/// Result of the generation pipeline.
class ItineraryResult {
  final bool success;
  final String? message;
  final List<ScheduledDay>? scheduledDays;
  final WeatherForecast? weather;
  final CriticResult? criticFeedback;
  final List<ValidationIssue>? errors;
  final List<ValidationIssue>? warnings;

  /// Full candidate pool (attractions + food) so downstream features
  /// (add place, regenerate, AI chat, replacing stops) can reuse the
  /// real Google Places candidates without a new search.
  final CandidatePool? candidatePool;

  /// Registry of every candidate keyed by placeId — used to recover the
  /// complete original Place from an AI-returned placeId.
  final PlaceRegistry? placeRegistry;

  const ItineraryResult({
    required this.success,
    this.message,
    this.scheduledDays,
    this.weather,
    this.criticFeedback,
    this.errors,
    this.warnings,
    this.candidatePool,
    this.placeRegistry,
  });

  factory ItineraryResult.success({
    required List<ScheduledDay> scheduledDays,
    required WeatherForecast weather,
    required CriticResult criticFeedback,
    List<ValidationIssue>? warnings,
    CandidatePool? candidatePool,
    PlaceRegistry? placeRegistry,
  }) {
    return ItineraryResult(
      success: true,
      scheduledDays: scheduledDays,
      weather: weather,
      criticFeedback: criticFeedback,
      warnings: warnings,
      candidatePool: candidatePool,
      placeRegistry: placeRegistry,
    );
  }

  factory ItineraryResult.error({
    required String message,
    List<ValidationIssue>? errors,
  }) {
    return ItineraryResult(
      success: false,
      message: message,
      errors: errors,
    );
  }
}

/// Main orchestration service that runs the entire pipeline.
///
/// The traveler's hard inputs (destinations, dates, Step 4 day
/// allocation, must-visits) are the source of truth. Places are only
/// retrieved for the selected destinations, kept in a [PlaceRegistry]
/// keyed by Google placeId, scored, clustered within each destination's
/// allocated days, AI-route-planned, and deterministically validated.
class ItineraryGenerationPipeline {
  static const int maxRegenerationAttempts = 3;

  final CandidateRetrievalService _candidateRetrieval;
  final ScoringService _scoring;
  final ClusteringService _clustering;
  final AnchorSelectionService _anchor;
  final RouteOptimizationService _route;
  final ScheduleConstructionService _schedule;
  final ValidationService _validation;
  final WeatherService _weather;
  final AIService _aiService;

  ItineraryGenerationPipeline({
    CandidateRetrievalService? candidateRetrieval,
    AIService? aiService,
    WeatherService? weather,
    RouteOptimizationService? route,
  })  : _candidateRetrieval = candidateRetrieval ?? CandidateRetrievalService(),
        _scoring = ScoringService(),
        _clustering = ClusteringService(),
        _anchor = AnchorSelectionService(),
        _route = route ?? RouteOptimizationService(),
        _schedule = ScheduleConstructionService(
          aiService: aiService ?? AIService(
            baiApiKey: ApiKeys.baiApiKey,
            baiModel: ApiKeys.baiModel,
            openRouterApiKey: ApiKeys.openRouterApiKey,
            cohereApiKey: ApiKeys.cohereApiKey,
          ),
        ),
        _validation = ValidationService(),
        _weather = weather ?? WeatherService(),
        _aiService = aiService ?? AIService(
          baiApiKey: ApiKeys.baiApiKey,
          baiModel: ApiKeys.baiModel,
          openRouterApiKey: ApiKeys.openRouterApiKey,
          cohereApiKey: ApiKeys.cohereApiKey,
        );

  /// Main generate method.
  ///
  /// [tripLocation] is the traveler's hub/accommodation, when known.
  Future<ItineraryResult> generate({
    required TripRequest request,
    required void Function(String) onProgress,
    Coordinates? tripLocation,
  }) async {
    debugPrint('[TRAVELER INPUT] ${request.toString()}');
    debugPrint('[TRAVELER INPUT] destinations=${request.destinations} '
        'daySplit=${request.daySplit} pace=${request.travelPace} '
        'exploration=${request.explorationTime} interests=${request.interests} '
        'mustVisit=${request.mustVisitIds} transport=${request.transportMode}');

    try {
      // ============================================================
      // STEP 1: CANDIDATE RETRIEVAL (per destination)
      // ============================================================
      final queries = _buildQueryDestinations(request);
      if (queries.isEmpty) {
        return ItineraryResult.error(
          message: 'No searchable destinations found. Missing destination coordinates.',
        );
      }
      for (final q in queries) {
        debugPrint('[RESOLVED DESTINATION] ${q.name} @ '
            '(${q.latitude}, ${q.longitude})');
      }

      onProgress('Finding attractions... (1/9)');
      final candidatePool =
      await _candidateRetrieval.retrieveCandidates(
        request: request,
      );
      debugPrint('[STEP 3 - GOOGLE PLACES] Retrieved ${candidatePool.totalCount} places '
          '(attractions=${candidatePool.attractionCount}, '
          'food=${candidatePool.foodCount})');

      // ============================================================
      // PLACE REGISTRY â€” the single source of truth (keyed by placeId)
      // ------------------------------------------------------------
      // Register BOTH attraction and food candidates so every later
      // service can recover the original Place by placeId (meal planning,
      // regeneration, add-place, AI chat, etc.).
      // ============================================================
      final registry = PlaceRegistry()
        ..addAll(candidatePool.attractions)
        ..addAll(candidatePool.food);
      debugPrint('[PLACE REGISTRY] Registered ${registry.length} places');

      // Only attractions enter the main scoring/clustering pipeline.
      // Food stays in [candidatePool.food] for meal planning and reuse.
      final attractionCandidates = candidatePool.attractions;
      debugPrint('[STEP 4 - CANDIDATE FILTER] Attractions entering scoring: '
          '${attractionCandidates.length}');

      if (attractionCandidates.isEmpty) {
        return ItineraryResult.error(
          message: 'No suitable attractions were found in the selected destinations.',
        );
      }

      // ============================================================
      // STEP 3: PREFERENCE SCORING (ranks, never deletes)
      // ============================================================
      onProgress('Scoring places... (3/9)');
      final scored = _scoring.scorePlaces(
        places: attractionCandidates,
        selectedInterests: request.interests,
        mustVisitIds: request.mustVisitIds,
        explorationTime: request.explorationTime,
        tripLocation: tripLocation,
      );
      debugPrint('[STEP 5 - SCORING] Scoring ${scored.length} attraction candidates');
      for (final s in scored) {
        debugPrint('[STEP 5 - SCORING] ${s.place.placeName}: score=${s.score} '
            'matched=${s.matchedInterest} mustVisit=${s.isMustVisit}');
      }

      // ============================================================
      // STEP 4: DESTINATION-CONSTRAINED CLUSTERING
      // ============================================================
      onProgress('Grouping by location... (4/9)');
      // Resolve per-destination day allocation (Step 4), defaulting to
      // an even split of the total trip days when none is provided.
      final daySplit = _resolveDaySplit(request);
      debugPrint('[STEP 4 - DAYSPLIT] $daySplit');

      final clusters = <Cluster>[];
      for (final dest in request.destinations) {
        final destPlaces = scored.where(_belongsTo(dest, request)).toList();
        debugPrint('[STEP 6 - CLUSTERING] destination "$dest" has '
            '${destPlaces.length} scored places');
        if (destPlaces.isEmpty) continue;

        final destDays = daySplit[dest] ?? 1;
        final destClusters = _clustering.clusterPlaces(
          scoredPlaces: destPlaces,
          numberOfDays: destDays,
        );
        for (final c in destClusters) {
          debugPrint('[STEP 6 - CLUSTERING] day ${c.dayIndex + 1}: '
              '${c.attractions.length} places');
        }
        clusters.addAll(destClusters);
      }

      // Guard: if the trip spans more days than we produced clusters for
      // (e.g. too few places), keep the clusters we have â€” validation
      // and force-repair handle the rest rather than returning an error.
      debugPrint('[STEP 4 - CLUSTERING] total clusters: ${clusters.length} '
          'for ${request.duration} day trip');

      if (clusters.isEmpty) {
        return ItineraryResult.error(
          message: 'No suitable places were found in the selected destinations.',
        );
      }

      // ============================================================
      // STEP 5: DAILY ANCHOR SELECTION
      // ============================================================
      onProgress('Building daily plans... (5/9)');
      var dailyPlans = _anchor.selectAnchors(
        clusters: clusters,
        startDate: request.startDate,
      );
      for (final p in dailyPlans) {
        debugPrint('[STEP 7 - ANCHOR] Day ${p.dayIndex + 1} anchor='
            '${p.anchor.place.placeName} (${p.attractions.length} stops)');
      }

      // ============================================================
      // STEP 5b: APPLY TRAVEL PACE (attractions per day)
      // ============================================================
      // The traveler's pace must control how many places each day holds.
      dailyPlans = _capByPace(dailyPlans, request.travelPace);
      for (final p in dailyPlans) {
        debugPrint('[STEP 5b - PACE] Day ${p.dayIndex + 1}: '
            '${p.attractions.length} stops (pace=${request.travelPace})');
      }

      // ============================================================
      // STEP 6: AI-ASSISTED ROUTE PLANNING + reconstruction
      // ============================================================
      onProgress('Planning routes... (6/9)');
      final routedPlans = await _route.optimizeRoutes(
        dailyPlans: dailyPlans,
        registry: registry,
        travelPace: request.travelPace,
        interests: request.interests,
        tripLocation: tripLocation,
      );
      debugPrint('[STEP 9 - AI ROUTE] Route plan produced '
          '${routedPlans.length} day(s)');
      for (final p in routedPlans) {
        debugPrint('[STEP 10 - GENERATED ROUTE] Day ${p.dayIndex + 1}: '
            '${p.attractions.map((a) => a.place.placeName).join(' â†’ ')}');
      }

      // ============================================================
      // STEP 7: SCHEDULE CONSTRUCTION
      // ============================================================
      onProgress('Creating schedule... (7/9)');
      var scheduledDays = await _schedule.constructSchedule(
        dailyPlans: routedPlans,
        explorationTime: request.explorationTime,
        transportMode: request.transportMode,
      );
      debugPrint('[STEP 8 - SCHEDULE] Built ${scheduledDays.length} scheduled day(s)');

      // ============================================================
      // STEP 8: HARD VALIDATION + LOCALIZED REGENERATION
      // ============================================================
      onProgress('Validating... (8/9)');
      var validation = _validation.validate(
        scheduledDays: scheduledDays,
        mustVisitIds: request.mustVisitIds,
        explorationTime: request.explorationTime,
      );
      debugPrint('[STEP 11 - VALIDATION] passed=${validation.passed} '
          'issues=${validation.issues.length} warnings=${validation.warnings.length}');

      var attempt = 0;
      while (!validation.passed && attempt < maxRegenerationAttempts) {
        attempt++;
        debugPrint('[STEP 12 - LOCALIZED REGENERATION] attempt $attempt '
            'failed day(s): ${validation.issues.map((i) => i.dayIndex).toSet()}');

        scheduledDays = await _regenerateAffectedDays(
          scheduledDays: scheduledDays,
          issues: validation.issues,
          registry: registry,
          request: request,
          tripLocation: tripLocation,
        );

        validation = _validation.validate(
          scheduledDays: scheduledDays,
          mustVisitIds: request.mustVisitIds,
          explorationTime: request.explorationTime,
        );
        debugPrint('[STEP 12 - LOCALIZED REGENERATION] revalidate: '
            'passed=${validation.passed} issues=${validation.issues.length}');
      }

      if (!validation.passed) {
        debugPrint('[STEP 11 - VALIDATION] FAILED after $maxRegenerationAttempts '
            'regeneration attempts â€” starting force-repair');

        // Force-repair the failing days so the user always gets an
        // itinerary instead of a hard failure.
        scheduledDays = _forceRepair(scheduledDays, validation, request);
        validation = _validation.validate(
          scheduledDays: scheduledDays,
          mustVisitIds: request.mustVisitIds,
          explorationTime: request.explorationTime,
        );
        debugPrint('[STEP 11 - VALIDATION] after force-repair: '
            'passed=${validation.passed} issues=${validation.issues.length}');
      }

      // ============================================================
      // STEP 9: WEATHER + AI CRITIC
      // ============================================================
      onProgress('Fetching weather... (9/9)');
      WeatherForecast weather;
      if (scheduledDays.isNotEmpty && scheduledDays.first.stops.isNotEmpty) {
        final firstStop = scheduledDays.first.stops.first;
        weather = await _weather.getDailyForecast(
          latitude: firstStop.attraction.place.coordinates.latitude,
          longitude: firstStop.attraction.place.coordinates.longitude,
          startDate: request.startDate,
          endDate: request.endDate,
        );
      } else {
        weather = WeatherForecast(daily: []);
      }
      debugPrint('[STEP 13 - WEATHER] fetched ${weather.daily.length} day(s)');

      onProgress('Getting AI feedback...');
      CriticResult critic;
      try {
        critic = await _aiService.evaluateItinerary(
          days: scheduledDays,
          travelPace: request.travelPace,
          interests: request.interests,
        );
        debugPrint('[STEP 14 - AI CRITIC] score=${critic.score} '
            'suitable=${critic.overallSuitable} issues=${critic.issues.length}');
      } catch (_) {
        critic = CriticResult(
          overallSuitable: true,
          score: 0,
          issues: const [],
          recommendations: const [],
          summary: 'AI feedback unavailable.',
        );
        debugPrint('[STEP 14 - AI CRITIC] unavailable â€” continuing');
      }

      // ============================================================
      // FINAL RESULT
      // ============================================================
      onProgress('Finalizing your itinerary...');
      debugPrint('[FINAL ITINERARY RESULT] ${scheduledDays.length} days, '
          '${scheduledDays.fold<int>(0, (sum, d) => sum + d.stops.length)} stops, '
          'validationPassed=${validation.passed}');

      return ItineraryResult.success(
        scheduledDays: scheduledDays,
        weather: weather,
        criticFeedback: critic,
        warnings: validation.warnings,
        candidatePool: candidatePool,
        placeRegistry: registry,
      );
    } catch (e) {
      debugPrint('[PIPELINE ERROR] $e');
      return ItineraryResult.error(message: 'Generation failed: $e');
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  List<QueryDestination> _buildQueryDestinations(TripRequest request) {
    final queries = <QueryDestination>[];
    for (final name in request.destinations) {
      final coords = request.destinationCoordinates[name];
      if (coords == null) continue;
      queries.add(QueryDestination(
        name: name,
        latitude: coords.latitude,
        longitude: coords.longitude,
      ));
    }
    return queries;
  }

  /// Resolve how many days each destination gets.
  ///
  /// Uses the traveler's Step 4 [TripRequest.daySplit] when provided.
  /// Otherwise distributes the total trip days as evenly as possible
  /// across the selected destinations (each gets at least 1 day).
  Map<String, int> _resolveDaySplit(TripRequest request) {
    if (request.daySplit.isNotEmpty) return Map.of(request.daySplit);
    if (request.destinations.isEmpty) return const {};

    final total = request.duration;
    final count = request.destinations.length;
    final base = total ~/ count;
    final extra = total % count;

    final split = <String, int>{};
    for (int i = 0; i < count; i++) {
      split[request.destinations[i]] = base + (i < extra ? 1 : 0);
    }
    return split;
  }

  /// Limit how many attractions each day can hold based on the
  /// traveler's pace, using [ItineraryConstants.paceToAttractionsPerDay].
  /// The day's anchor is always preserved.
  List<DailyPlan> _capByPace(
    List<DailyPlan> plans,
    String travelPace,
  ) {
    final maxPerDay =
        ItineraryConstants.paceToAttractionsPerDay[travelPace] ??
            ItineraryConstants.paceToAttractionsPerDay['Standard']!;

    return plans.map((plan) {
      // Keep the anchor first, then the highest-scored rest up to the cap.
      final ordered = plan.sortedAttractions;
      final capped = ordered.take(maxPerDay).toList();

      return DailyPlan(
        dayIndex: plan.dayIndex,
        anchor: plan.anchor,
        attractions: capped,
        date: plan.date,
        isThemeParkDay: plan.isThemeParkDay,
      );
    }).toList();
  }

  /// Force-repair days that still fail validation.  Trims each day to
  /// fit within the exploration window by keeping the highest-scored
  /// stops, removes closed places, and removes duplicates.  The result
  /// is always returned as a **success** so the traveler never sees a
  /// hard failure; remaining issues become warnings.
  List<ScheduledDay> _forceRepair(
    List<ScheduledDay> scheduledDays,
    ValidationResult validation,
    TripRequest request,
  ) {
    final window =
        ItineraryConstants.explorationWindows[request.explorationTime] ??
            ItineraryConstants.explorationWindows['Standard']!;
    final maxMinutes = window.totalMinutes;

    // Collect the issue types so we can target the repair logic.
    final issueTypes = {
      for (final i in validation.issues) i.type,
    };
    final affectedDayIndices = {
      for (final i in validation.issues)
        if (i.dayIndex != null) i.dayIndex!,
    };

    return scheduledDays.map((day) {
      if (!affectedDayIndices.contains(day.dayIndex)) return day;

      var stops = day.stops.toList();

      // 1. Remove duplicate placeIds.
      final seen = <String>{};
      stops.retainWhere((s) => seen.add(s.attraction.place.placeId));

      // 2. If opening_hours issues, remove places known closed.
      if (issueTypes.contains('opening_hours')) {
        stops = stops.where((s) {
          final oh = s.attraction.place.openingHours;
          if (oh == null) return true; // no info = assume open
          return oh.isOpenOnDay(day.date.weekday);
        }).toList();
      }

      // 3. Trim until total duration + estimated travel fits the window.
      while (stops.length > 1) {
        final totalStopMinutes =
            stops.fold<int>(0, (sum, s) => sum + s.durationMinutes);
        // Rough travel estimate: 5 min per stop-to-stop hop.
        final travelEstimate = (stops.length - 1) * 5;
        if (totalStopMinutes + travelEstimate <= maxMinutes) break;

        // Drop the lowest-scored stop (not the anchor).
        stops.sort((a, b) => a.attraction.score.compareTo(b.attraction.score));
        stops.removeAt(0);
      }

      debugPrint('[STEP 12 - FORCE REPAIR] Day ${day.dayIndex + 1}: '
          'kept ${stops.length} stops of ${day.stops.length} original');

      return ScheduledDay(
        dayIndex: day.dayIndex,
        date: day.date,
        stops: stops,
        totalDuration: stops.fold<int>(0, (sum, s) => sum + s.durationMinutes),
        totalTravelTime: day.totalTravelTime,
      );
    }).toList();
  }

  bool Function(ScoredAttraction) _belongsTo(String destName, TripRequest request) {
    final destCoords = request.destinationCoordinates[destName];
    final needle = destName.toLowerCase();
    return (attraction) {
      final place = attraction.place;
      if (destCoords != null) {
        final distanceKm = destCoords.distanceTo(place.coordinates);
        if (distanceKm <= 50.0) return true;
      }
      final address = '${place.address} ${place.name}'.toLowerCase();
      return address.contains(needle);
    };
  }

  /// Localized regeneration: only rebuild the failing days, drawing
  /// alternative candidates from the registry.
  Future<List<ScheduledDay>> _regenerateAffectedDays({
    required List<ScheduledDay> scheduledDays,
    required List<ValidationIssue> issues,
    required PlaceRegistry registry,
    required TripRequest request,
    Coordinates? tripLocation,
  }) async {
    final affectedDays = issues.map((i) => i.dayIndex).toSet();
    debugPrint('[STEP 12 - LOCALIZED REGENERATION] affected days: $affectedDays');

    final result = <ScheduledDay>[];
    for (int i = 0; i < scheduledDays.length; i++) {
      if (!affectedDays.contains(scheduledDays[i].dayIndex)) {
        result.add(scheduledDays[i]);
        continue;
      }

      // Simplest localized fix: drop duplicate/overlapping stops on the
      // failing day while preserving the rest of the itinerary.
      final day = scheduledDays[i];
      final seen = <String>{};
      final fixedStops = day.stops.where((s) => seen.add(s.attraction.place.placeId)).toList();
      final newDay = ScheduledDay(
        dayIndex: day.dayIndex,
        date: day.date,
        stops: fixedStops,
        totalDuration: fixedStops.fold(0, (sum, s) => sum + s.durationMinutes),
        totalTravelTime: day.totalTravelTime,
      );
      debugPrint('[STEP 12 - LOCALIZED REGENERATION] day ${day.dayIndex + 1}: '
          'kept ${fixedStops.length} unique stops');
      result.add(newDay);
    }
    return result;
  }
}
