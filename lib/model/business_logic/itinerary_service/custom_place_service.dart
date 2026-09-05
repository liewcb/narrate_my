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

import 'dart:async';
import 'dart:convert';

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

/// One chained slot for a position (estimated travel times).
typedef _SlotRecord = ({
  Place place,
  DateTime startTime,
  DateTime endTime,
  int durationMinutes,
  int travelMinutes,
});

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

  /// 0-based index of the NEW stop within the proposed day (null on failure).
  final int? insertIndex;

  /// Whether the AI proposed the winning insertion position.
  final bool usedAi;

  const CustomPlacePlanResult({
    required this.success,
    this.message,
    this.proposedDay,
    this.validation,
    this.orderedAttractions,
    this.insertIndex,
    this.usedAi = false,
  });

  factory CustomPlacePlanResult.problem(String message) =>
      CustomPlacePlanResult(success: false, message: message);
}

/// Minimal schedule context for one existing stop of the day. The caller
/// (temporary editor state) supplies these Ã¢â‚¬â€ the service never reads the
/// database, so the preview stays temporary and fast.
class ExistingStopContext {
  final Place place;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int travelFromPrevMinutes;
  final bool isMustVisit;

  const ExistingStopContext({
    required this.place,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.travelFromPrevMinutes = 0,
    this.isMustVisit = false,
  });
}

/// Ordered schedule context for ONE day of the temporary itinerary.
class DayPlanContext {
  final List<ExistingStopContext> stops; // ordered by stopOrder
  final Set<String> usedPlaceIds; // whole itinerary, not just this day

  const DayPlanContext({required this.stops, required this.usedPlaceIds});
}

/// Callback the host screen provides so the VM can read any day's context
/// from the temporary itinerary state without touching the database.
typedef DayContextLoader = Future<DayPlanContext?> Function(int dayIndex);

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
  /// query is the primary input Ã¢â‚¬â€ the user is NOT required to type
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
  /// Distance is user information/warning only Ã¢â‚¬â€ it is NOT a rejection
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
      anchor = place.coordinates; // empty day Ã¢â€ â€™ distance 0
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
      // Duplicate Ã¢â‚¬â€ already used in the itinerary.
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
  /// `Previous Ã¢â€ â€™ Candidate Ã¢â€ â€™ Next` ranks higher.
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
  // 5. LEAN INSERTION PLANNING (pre-checks → AI position → Dart schedule)
  // ============================================================

  /// AI hard timeout for the insertion-position request (~6s) so the whole
  /// Add Custom Place planning operation finishes inside the ~8-10s
  /// responsiveness budget: pre-checks are milliseconds, retrieval is one
  /// Places call, and the deterministic fallback always has room to run.
  static const Duration aiTimeout = Duration(seconds: 6);

  /// Plans the insertion of [newPlace] into ONE day of the temporary
  /// itinerary.
  ///
  /// Pipeline (never regenerates the whole itinerary):
  ///   1. Fast deterministic pre-checks (reject before any AI/network).
  ///   2. ONE compact AI request: "insert after which stop?" (~6s cap).
  ///   3. Deterministic fallback scans every position with straight-line
  ///      travel estimates when the AI is unavailable or infeasible.
  ///   4. Real routed travel times are fetched ONLY for the winning
  ///      position's two affected legs (max 2 Google calls).
  ///   5. Dart validates the complete resulting day before returning.
  ///
  /// [existingStops] come from the caller's temporary state — the service
  /// never reads the database, so the preview stays temporary and fast.
  Future<CustomPlacePlanResult> planInsertion({
    required int dayIndex, // 0-based day index used by the pipeline
    required DateTime date,
    required List<ExistingStopContext> existingStops,
    required Place newPlace,
    required String explorationTime,
    required String transportMode,
    required String travelPace,
    required List<String> interests,
    Coordinates? tripLocation,
  }) async {
    // ── 1. Fast deterministic pre-checks (no AI, no network) ──
    if (newPlace.placeId.isEmpty) {
      return CustomPlacePlanResult.problem('Please select a valid place.');
    }
    if (newPlace.placeLatitude == 0 && newPlace.placeLongitude == 0) {
      return CustomPlacePlanResult.problem(
          'This place has no valid map location.');
    }
    // Duplicate rule — placeId identity, against the temporary day state.
    if (existingStops.any((s) => s.place.placeId == newPlace.placeId)) {
      return CustomPlacePlanResult.problem(
          'This place is already in your itinerary.');
    }
    // Destination area — actual coordinates, never the search text.
    if (tripLocation != null) {
      final distanceKm = tripLocation.distanceTo(newPlace.coordinates);
      if (distanceKm > ItineraryConstants.maxSearchRadiusKm) {
        return CustomPlacePlanResult.problem(
            'This place is outside your trip destination.');
      }
    }
    // Closed the whole day → reject before spending any AI budget.
    final window = ItineraryConstants.explorationWindowFor(explorationTime);
    final closedAllDay = _checkOpeningHours(
      place: newPlace,
      date: date,
      windowStartMinutes: window.startMinutes,
      windowEndMinutes: window.endMinutes,
    );
    if (closedAllDay != null) {
      return CustomPlacePlanResult.problem(closedAllDay);
    }

    // ── 2. Visit duration (existing value, Dart-clamped) ──
    final baseDuration = _resolveDuration(newPlace: newPlace, suggested: null);
    if (baseDuration > window.totalMinutes) {
      return CustomPlacePlanResult.problem(
          "There isn't enough time to add this place to your day.");
    }

    // ── 3. Deterministic fallback scan (estimates only, no network) ──
    final scan = _scanFeasiblePositions(
      existingStops: existingStops,
      newPlace: newPlace,
      newDuration: baseDuration,
      date: date,
      window: window,
      transportMode: transportMode,
    );

    if (scan.feasible.isEmpty) {
      return CustomPlacePlanResult.problem(scan.failureReason);
    }

    // ── 4. ONE compact AI request for the insertion position ──
    final aiPosition = await _aiInsertionPosition(
      existingStops: existingStops,
      newPlace: newPlace,
      durationMinutes: baseDuration,
      interests: interests,
      travelPace: travelPace,
      explorationTime: explorationTime,
      transportMode: transportMode,
    );

    // AI position feasible? Its clamped duration is re-checked.
    int? aiPick;
    if (aiPosition != null) {
      final aiDuration = _resolveDuration(
          newPlace: newPlace, suggested: aiPosition.visitMinutes);
      final aiFeasible = scan.feasible.any((f) =>
          f.position == aiPosition.insertIndex &&
          _estimateScanPosition(
            existingStops: existingStops,
            newPlace: newPlace,
            newDuration: aiDuration,
            position: aiPosition.insertIndex,
            window: window,
            transportMode: transportMode,
          ) !=
          null);
      if (aiFeasible) {
        aiPick = aiPosition.insertIndex;
      }
    }

    // ── 5. Candidate order: AI pick first, then lowest-detour fallback ──
    final candidates = <int>[
      if (aiPick != null) aiPick,
      ...scan.feasible
          .map((f) => f.position)
          .where((p) => p != aiPick)
          .toList(),
    ];

    // ── 6. Real routed travel for the winning position (max 3 attempts) ──
    String? lastFailure;
    var usedAi = false;
    for (var attempt = 0; attempt < candidates.length && attempt < 3; attempt++) {
      final position = candidates[attempt];
      final routed = await _buildRoutedSlot(
        position: position,
        existingStops: existingStops,
        newPlace: newPlace,
        newDuration:
            position == aiPick ? _resolveDuration(newPlace: newPlace, suggested: aiPosition?.visitMinutes) : baseDuration,
        date: date,
        window: window,
        transportMode: transportMode,
      );
      if (routed == null) {
        lastFailure = scan.failureReason;
        continue;
      }

      final proposedDay = _buildScheduledDay(
        dayIndex: dayIndex,
        date: date,
        slot: routed,
      );
      final validation = ValidationService().validate(
        scheduledDays: [proposedDay],
        mustVisitIds: const [],
        explorationTime: explorationTime,
      );
      if (!validation.passed) {
        lastFailure = validation.issues.isEmpty
            ? 'This place cannot fit into your current schedule.'
            : validation.issues.first.message;
        continue;
      }

      usedAi = aiPick != null && position == aiPick;
      return CustomPlacePlanResult(
        success: true,
        proposedDay: proposedDay,
        validation: validation,
        insertIndex: position,
        usedAi: usedAi,
      );
    }

    return CustomPlacePlanResult.problem(
      lastFailure ?? 'This place cannot fit into your current schedule.',
    );
  }

  // ── AI: compact insertion-position request ──────────────────

  /// Asks the AI ONLY "after which existing stop should this place go?".
  /// No clock times, no travel math, no invented places — Dart owns those.
  Future<({int insertIndex, int? visitMinutes})?> _aiInsertionPosition({
    required List<ExistingStopContext> existingStops,
    required Place newPlace,
    required int durationMinutes,
    required List<String> interests,
    required String travelPace,
    required String explorationTime,
    required String transportMode,
  }) async {
    final buf = StringBuffer()
      ..writeln('You insert one new stop into an existing day plan.')
      ..writeln()
      ..writeln('Traveler: interests='
          '${interests.isEmpty ? 'none' : interests.join('|')}'
          ', pace=$travelPace, exploration=$explorationTime, '
          'transport=$transportMode')
      ..writeln()
      ..writeln('NEW PLACE: placeId=${newPlace.placeId}, '
          'name=${newPlace.placeName}, '
          'category=${newPlace.placeCategory ?? 'unknown'}, '
          'visitMinutes=$durationMinutes')
      ..writeln()
      ..writeln('EXISTING DAY (in order):');
    for (var i = 0; i < existingStops.length; i++) {
      final s = existingStops[i];
      final hhmm = (int m) =>
          '${(m ~/ 60).toString().padLeft(2, '0')}:'
          '${(m % 60).toString().padLeft(2, '0')}';
      buf.writeln('$i: placeId=${s.place.placeId}, name=${s.place.placeName}, '
          'category=${s.place.placeCategory ?? 'unknown'}, '
          'lat=${s.place.placeLatitude.toStringAsFixed(3)}, '
          'lng=${s.place.placeLongitude.toStringAsFixed(3)}, '
          'time=${hhmm(s.startTime.hour * 60 + s.startTime.minute)}-'
          '${hhmm(s.endTime.hour * 60 + s.endTime.minute)}');
    }
    buf
      ..writeln()
      ..writeln('insertIndex = number of stops BEFORE the new stop '
          '(0 = start, ${existingStops.length} = end). Consider geography, '
          'category flow and day balance.')
      ..writeln('Respond with compact JSON ONLY, no markdown:')
      ..writeln('{"insertIndex":2,"visitMinutes":75}');

    try {
      final raw = await _aiService
          .generateRawContent(
            buf.toString(),
            timeout: aiTimeout,
            totalBudget: aiTimeout,
            requestName: 'CUSTOM_PLACE_INSERT',
          )
          .timeout(aiTimeout);
      return _parseAiInsertion(raw, existingStops.length);
    } catch (e) {
      debugPrint('[CustomPlace] AI position failed (fallback next): $e');
      return null;
    }
  }

  /// Parses the compact AI JSON. Only in-range indices are accepted.
  ({int insertIndex, int? visitMinutes})? _parseAiInsertion(
    String raw,
    int maxIndex,
  ) {
    try {
      final text = raw.trim().replaceAll('```', '');
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final data = jsonDecode(text.substring(start, end + 1));
      if (data is! Map<String, dynamic>) return null;
      final idx = (data['insertIndex'] as num?)?.toInt();
      if (idx == null || idx < 0 || idx > maxIndex) return null;
      return (
        insertIndex: idx,
        visitMinutes: (data['visitMinutes'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Deterministic fallback scan (pure Dart, no network) ─────

  /// Result of the deterministic fallback scan.
  ({List<({int position, double detourMinutes})> feasible,
      String failureReason}) _scanFeasiblePositions({
    required List<ExistingStopContext> existingStops,
    required Place newPlace,
    required int newDuration,
    required DateTime date,
    required ExplorationWindow window,
    required String transportMode,
  }) {
    final feasible = <({int position, double detourMinutes})>[];
    String? failure;

    for (var position = 0; position <= existingStops.length; position++) {
      final slots = _estimateScanPosition(
        existingStops: existingStops,
        newPlace: newPlace,
        newDuration: newDuration,
        position: position,
        window: window,
        transportMode: transportMode,
      );
      if (slots == null) {
        failure ??= 'This place cannot fit into your current schedule.';
        continue;
      }
      // Detour = added estimated travel vs the original day.
      final detour = slots.fold<double>(0, (s, x) => s + x.travelMinutes) -
          existingStops.fold<double>(0, (s, x) => s + x.travelFromPrevMinutes);
      feasible.add((position: position, detourMinutes: detour.clamp(0, double.infinity)));
    }

    if (feasible.isEmpty) {
      failure ??= 'This place cannot fit into your current schedule.';
    }
    feasible.sort((a, b) => a.detourMinutes.compareTo(b.detourMinutes));
    return (feasible: feasible, failureReason: failure ?? '');
  }

  /// Chains the day schedule for ONE position using straight-line travel
  /// estimates and hard-validates every stop. Returns null when a hard
  /// constraint fails. Preserves each existing stop's persisted clock time
  /// by anchoring the chain at the original first stop's start.
  List<_SlotRecord>? _estimateScanPosition({
    required List<ExistingStopContext> existingStops,
    required Place newPlace,
    required int newDuration,
    required int position,
    required ExplorationWindow window,
    required String transportMode,
  }) {
    final date = existingStops.isEmpty
        ? DateTime.now()
        : DateTime(existingStops.first.startTime.year,
            existingStops.first.startTime.month,
            existingStops.first.startTime.day);

    // Anchor: the original first stop's start time (day preserved as-is);
    // empty day → exploration window opening.
    final dayBase = DateTime(date.year, date.month, date.day);
    final anchorMinutes = existingStops.isEmpty
        ? window.startMinutes
        : existingStops.first.startTime.hour * 60 +
            existingStops.first.startTime.minute;

    final ordered = <Place>[
      ...existingStops.map((s) => s.place),
      newPlace,
    ];
    // Rebuild with the new place at [position].
    final orderedNew = <Place>[
      ...ordered.sublist(0, position),
      newPlace,
      ...ordered.sublist(position, ordered.length - 1),
    ];
    final durations = <int>[
      ...existingStops.map((s) => s.durationMinutes),
      newDuration,
    ];
    final durationsNew = <int>[
      ...durations.sublist(0, position),
      newDuration,
      ...durations.sublist(position, durations.length - 1),
    ];

    final slots = <_SlotRecord>[];
    var cursor = dayBase.add(Duration(minutes: anchorMinutes));

    for (var i = 0; i < orderedNew.length; i++) {
      final place = orderedNew[i];
      final duration = durationsNew[i];

      int travel = 0;
      if (i > 0) {
        final prevPlace = orderedNew[i - 1];
        travel = _estimateTravelMinutes(
                prevPlace.coordinates.distanceTo(place.coordinates),
                transportMode)
            .ceil()
            .clamp(1, ItineraryConstants.hardMaxTravelMinutes);
      }

      final start = i == 0 ? cursor : cursor.add(Duration(minutes: travel));
      final end = start.add(Duration(minutes: duration));

      // Hard: exploration window bounds.
      final startMin = start.hour * 60 + start.minute;
      final endMin = end.hour * 60 + end.minute;
      if (startMin < window.startMinutes || endMin > window.endMinutes) {
        return null;
      }

      // Hard: opening hours of EVERY stop for its visit interval.
      final openIssue = _checkOpeningHours(
        place: place,
        date: date,
        windowStartMinutes: window.startMinutes,
        windowEndMinutes: window.endMinutes,
        visitStartMinutes: startMin,
        visitEndMinutes: endMin,
      );
      if (openIssue != null) return null;

      slots.add((
        place: place,
        startTime: start,
        endTime: end,
        durationMinutes: duration,
        travelMinutes: travel,
      ));
      cursor = end;
    }
    return slots;
  }

  // ── Routed slot for the winning position (max 2 Google calls) ──

  /// Rebuilds the day for the chosen position with REAL routed travel times
  /// for the two legs touching the new place; all other legs keep the
  /// estimated values (identical to the original day's estimator).
  Future<List<_SlotRecord>?> _buildRoutedSlot({
    required int position,
    required List<ExistingStopContext> existingStops,
    required Place newPlace,
    required int newDuration,
    required DateTime date,
    required ExplorationWindow window,
    required String transportMode,
  }) async {
    // Fast path: chain with estimates first (no network), then swap in the
    // two routed legs and re-chain. If the routed times break the window or
    // opening hours, the position is rejected.
    final estimated = _estimateScanPosition(
      existingStops: existingStops,
      newPlace: newPlace,
      newDuration: newDuration,
      position: position,
      window: window,
      transportMode: transportMode,
    );
    if (estimated == null) return null;

    // Route only the affected legs (indexes position and position+1).
    final ordered = <Place>[
      ...existingStops.map((s) => s.place),
    ];
    final orderedNew = <Place>[
      ...ordered.sublist(0, position),
      newPlace,
      ...ordered.sublist(position),
    ];
    final durationsNew = <int>[
      ...existingStops.map((s) => s.durationMinutes),
    ];
    final durationsFixed = <int>[
      ...durationsNew.sublist(0, position),
      newDuration,
      ...durationsNew.sublist(position),
    ];

    final routedTravel = <int?>[for (var i = 0; i < orderedNew.length; i++) null];
    for (final i in [position, position + 1]) {
      if (i <= 0 || i >= orderedNew.length) continue;
      try {
        final info = await _mapsService.getTravelTime(
          origin: orderedNew[i - 1].coordinates,
          destination: orderedNew[i].coordinates,
          mode: transportMode,
        );
        routedTravel[i] = info.durationMinutes.ceil();
      } catch (e) {
        debugPrint('[CustomPlace] Routed leg $i failed (estimate kept): $e');
      }
    }

    // Re-chain with routed values where available.
    final dayBase = DateTime(date.year, date.month, date.day);
    final anchorMinutes = existingStops.isEmpty
        ? window.startMinutes
        : existingStops.first.startTime.hour * 60 +
            existingStops.first.startTime.minute;
    final slots = <_SlotRecord>[];
    var cursor = dayBase.add(Duration(minutes: anchorMinutes));

    for (var i = 0; i < orderedNew.length; i++) {
      final place = orderedNew[i];
      final duration = durationsFixed[i];

      int travel = 0;
      if (i > 0) {
        travel = routedTravel[i] ??
            _estimateTravelMinutes(
                    orderedNew[i - 1].coordinates
                        .distanceTo(place.coordinates),
                    transportMode)
                .ceil()
                .clamp(1, ItineraryConstants.hardMaxTravelMinutes);
      }

      final start = i == 0 ? cursor : cursor.add(Duration(minutes: travel));
      final end = start.add(Duration(minutes: duration));
      final startMin = start.hour * 60 + start.minute;
      final endMin = end.hour * 60 + end.minute;

      if (startMin < window.startMinutes || endMin > window.endMinutes) {
        return null;
      }
      final openIssue = _checkOpeningHours(
        place: place,
        date: date,
        windowStartMinutes: window.startMinutes,
        windowEndMinutes: window.endMinutes,
        visitStartMinutes: startMin,
        visitEndMinutes: endMin,
      );
      if (openIssue != null) return null;

      slots.add((
        place: place,
        startTime: start,
        endTime: end,
        durationMinutes: duration,
        travelMinutes: travel,
      ));
      cursor = end;
    }
    return slots;
  }

  /// Converts a chained slot list into the pipeline's [ScheduledDay].
  ScheduledDay _buildScheduledDay({
    required int dayIndex,
    required DateTime date,
    required List<_SlotRecord> slot,
  }) {
    final stops = slot
        .map((s) => ScheduledStop(
              attraction: ScoredAttraction(
                place: s.place,
                score: 0,
                breakdown: const {},
              ),
              startTime: s.startTime,
              endTime: s.endTime,
              durationMinutes: s.durationMinutes,
              travelFromPreviousMinutes: s.travelMinutes,
              scheduleReason: '',
              weatherNote: '',
            ))
        .toList();
    return ScheduledDay(
      dayIndex: dayIndex,
      date: date,
      stops: stops,
      totalDuration: stops.fold<int>(0, (sum, x) => sum + x.durationMinutes),
      totalTravelTime:
          stops.fold<double>(0, (sum, x) => sum + x.travelFromPreviousMinutes),
    );
  }

  // ── Hard-constraint helpers ─────────────────────────────────

  /// Opening-hours hard check. Two modes:
  ///   • visit window omitted → "is the place open at some point today?"
  ///   • visit window given   → "is it open for the whole visit?"
  String? _checkOpeningHours({
    required Place place,
    required DateTime date,
    required int windowStartMinutes,
    required int windowEndMinutes,
    int? visitStartMinutes,
    int? visitEndMinutes,
  }) {
    final hours = place.openingHours;
    if (hours == null || hours.periods.isEmpty) return null; // unknown = OK

    final weekday = date.weekday % 7; // OpeningHours: 0 = Sunday
    final dayPeriods =
        hours.periods.where((p) => p.open.day == weekday).toList();
    if (dayPeriods.isEmpty) {
      return "This place isn't open during the available time.";
    }
    if (visitStartMinutes == null || visitEndMinutes == null) {
      return null; // open at some point — finer checks happen per stop
    }

    for (final period in dayPeriods) {
      final openMin = _hhmmToMinutes(period.open.time);
      var closeMin = _hhmmToMinutes(period.close.time);
      var start = visitStartMinutes;
      var end = visitEndMinutes;
      if (closeMin <= openMin) {
        // Overnight period (e.g. 22:00 → 02:00).
        closeMin += 1440;
        if (start < openMin) {
          start += 1440;
          end += 1440;
        }
      }
      if (start >= openMin && end <= closeMin) return null;
    }
    return "This place isn't open during the available time.";
  }

  int _hhmmToMinutes(String time) {
    final h = int.tryParse(time.substring(0, 2)) ?? 0;
    final m = time.length > 2 ? (int.tryParse(time.substring(2, 4)) ?? 0) : 0;
    return h * 60 + m;
  }

  /// Visit duration: existing value → clamped AI suggestion → category
  /// default. Always clamped to the project's hard duration rules.
  int _resolveDuration({
    required Place newPlace,
    required int? suggested,
  }) {
    var base = newPlace.visitDurationMinutes ??
        ItineraryConstants.baseDurationForCategory(
            newPlace.placeCategory, ItineraryConstants.defaultDurationMinutes);
    if (suggested != null && suggested > 0) {
      base = suggested;
    }
    return base.clamp(
      ItineraryConstants.minimumVisitDurationMinutes,
      ItineraryConstants.maximumVisitDurationMinutes,
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
