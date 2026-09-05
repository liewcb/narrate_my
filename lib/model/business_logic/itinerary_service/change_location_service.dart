// lib/model/business_logic/itinerary_service/change_location_service.dart
//
// "Change Location" business workflow for a single itinerary stop.
//
// Change Location is a REPLACEMENT, not an addition: the original stop is
// untouched until the traveler explicitly confirms via "Use This Place".
//
// Responsibility split:
//   Dart/business logic decides — editability (date AND time), candidate
//   retrieval + hard filtering, duplicate checks, opening hours, travel
//   feasibility, schedule conflicts, final schedule recalculation and
//   validation, persistence.
//   AI decides — which of the already-filtered candidates best replace the
//   original stop (preference match, similarity to the original purpose,
//   ranking, short reason). AI never modifies the schedule.
//
// The complete recommendation operation (retrieval + filter + AI + ranking)
// is bounded by a hard 10-second deadline; the AI call itself is capped at
// ~6.5s inside that budget. If AI fails, deterministic ranking is used.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/database_manager.dart';
import '../../../core/services/google_maps_service.dart';
import '../../entities/itinerary.dart';
import '../../entities/itinerary_stop.dart';
import '../../entities/place.dart';
import '../../repositories/adapters/itinerary_repository_adapter.dart';
import '../../repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../repositories/adapters/place_repository_adapter.dart';
import '../../../view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';
import 'itinerary_validator.dart';
import 'scoring_service.dart';

// ============================================================
// RESULT TYPES
// ============================================================

/// Outcome of a Change Location operation.
enum ChangeLocationOutcome { success, fallbackSuccess, problem }

/// A single replacement recommendation.
class ChangeLocationRecommendation {
  final Place place;
  final int aiScore; // 0..100
  final String reason; // short traveler-facing reason
  final String distanceText; // e.g. "1.2 km • 5 min"

  const ChangeLocationRecommendation({
    required this.place,
    required this.aiScore,
    required this.reason,
    required this.distanceText,
  });
}

/// Result of [ChangeLocationService.getReplacementRecommendations].
class ChangeLocationRecommendationResult {
  final ChangeLocationOutcome outcome;
  final String message; // traveler-facing, never technical
  final List<ChangeLocationRecommendation> recommendations;

  const ChangeLocationRecommendationResult({
    required this.outcome,
    required this.message,
    this.recommendations = const [],
  });

  bool get isSuccessful =>
      outcome != ChangeLocationOutcome.problem;

  factory ChangeLocationRecommendationResult.problem(String message) =>
      ChangeLocationRecommendationResult(
        outcome: ChangeLocationOutcome.problem,
        message: message,
      );
}

/// Result of [ChangeLocationService.replaceItineraryStop].
class ChangeLocationResult {
  final ChangeLocationOutcome outcome;
  final String message; // traveler-facing, never technical
  final ItineraryStop? updatedStop;

  const ChangeLocationResult({
    required this.outcome,
    required this.message,
    this.updatedStop,
  });

  bool get isSuccessful => outcome != ChangeLocationOutcome.problem;

  factory ChangeLocationResult.problem(String message) =>
      ChangeLocationResult(
        outcome: ChangeLocationOutcome.problem,
        message: message,
      );
}

// ============================================================
// SERVICE
// ============================================================

class ChangeLocationService {
  static const int maxAiCandidates = 15;
  static const Duration overallBudget = Duration(seconds: 10);
  static const Duration aiTimeout = Duration(seconds: 7);

  final ItineraryRepositoryImpl _itineraryRepo =
      DatabaseManager().itineraryRepository;
  final ItineraryStopRepositoryImpl _stopRepo =
      DatabaseManager().itineraryStopRepository;
  final PlaceRepositoryAdapter _placeRepo =
      DatabaseManager().placeRepository;
  final GoogleMapsService _maps = GoogleMapsService();
  final ItineraryValidator _validator = ItineraryValidator();
  final ScoringService _scoring = ScoringService();
  final AIService _ai = AIService();

  // ─── Editability (date AND time aware) ──────────────────────

  /// Validates that the itinerary can still be modified on its dates.
  /// Past → no. Upcoming → yes. Ongoing → only future portions.
  bool validateItineraryModificationDate(Itinerary itinerary) {
    return ItineraryStatusResolver.resolve(
      startDate: itinerary.startDate,
      endDate: itinerary.endDate,
    ).isEditable;
  }

  /// Whether a single stop is editable considering the current date AND
  /// time: completed stops and stops whose scheduled time has fully passed
  /// are locked; future days/stops and the remaining part of the current
  /// day are editable.
  bool isStopEditable(Itinerary itinerary, ItineraryStop stop) {
    if (!validateItineraryModificationDate(itinerary)) return false;
    if (stop.stopStatus == EditStopStatuses.completed) return false;
    if (stop.stopStatus == EditStopStatuses.skipped) return false;

    final now = DateTime.now();
    final endOfDay = _dayDate(itinerary, stop.dayIndex)
        .add(const Duration(days: 1));
    // Days that have fully elapsed are locked.
    if (!now.isBefore(endOfDay)) return false;

    // Today's stops: locked once the scheduled end time has fully passed.
    final scheduledEnd = _stopDateTime(itinerary, stop);
    return now.isBefore(scheduledEnd);
  }

  /// Day indices (1-based) that are still editable.
  List<int> getEditableDays(Itinerary itinerary) {
    final editable = <int>[];
    for (var d = 1; d <= itinerary.totalDays; d++) {
      final endOfDay = _dayDate(itinerary, d).add(const Duration(days: 1));
      if (DateTime.now().isBefore(endOfDay)) editable.add(d);
    }
    return editable;
  }

  // ─── Recommendations ────────────────────────────────────────

  /// Full Change Location recommendation workflow:
  /// editability → candidates → hard filter → AI ranking → result.
  Future<ChangeLocationRecommendationResult> getReplacementRecommendations({
    required String itineraryId,
    required int stopId,
  }) async {
    final deadline = DateTime.now().add(overallBudget);
    try {
      final itinerary = await _itineraryRepo.getItinerary(itineraryId);
      final stop = await _findStop(itineraryId, stopId);
      if (stop == null) {
        return ChangeLocationRecommendationResult.problem(
          'Unable to load this itinerary. Please try again.',
        );
      }

      // 1. Editability check (never call the AI for a locked stop).
      if (!validateItineraryModificationDate(itinerary)) {
        return ChangeLocationRecommendationResult.problem(
          'This itinerary has ended and can no longer be modified.',
        );
      }
      if (!isStopEditable(itinerary, stop)) {
        return ChangeLocationRecommendationResult.problem(
          'This stop can no longer be changed.',
        );
      }
      if (stop.place == null) {
        return ChangeLocationRecommendationResult.problem(
          'Unable to load this stop. Please try again.',
        );
      }

      // 2. Retrieve + hard-filter candidates (existing services).
      final filtered = await _getFilteredCandidates(
        itinerary: itinerary,
        stop: stop,
        deadline: deadline,
      );
      if (filtered.isEmpty) {
        return ChangeLocationRecommendationResult.problem(
          'No suitable replacement can fit into your remaining schedule. '
          'Try the manual search instead.',
        );
      }

      // 3. AI ranking within the remaining budget.
      final scored = await _aiRankCandidates(
        currentStop: stop,
        itinerary: itinerary,
        candidates: filtered,
        deadline: deadline,
      );

      final outcome = scored.usedAi
          ? ChangeLocationOutcome.success
          : ChangeLocationOutcome.fallbackSuccess;
      return ChangeLocationRecommendationResult(
        outcome: outcome,
        message: scored.usedAi
            ? 'Recommendations generated.'
            : 'Showing nearby options (AI is temporarily unavailable).',
        recommendations: scored.recommendations,
      );
    } catch (e, stack) {
      debugPrint('[ChangeLocation] Recommendation failed: $e\n$stack');
      return ChangeLocationRecommendationResult.problem(
        'Unable to load recommendations right now. Please try again.',
      );
    }
  }

  // ─── Preview-editing (EditItineraryScreen) API ──────────────

  /// Recommendation workflow for the PREVIEW editor (EditItineraryScreen).
  ///
  /// The temporary preview itinerary has no database rows, so candidates
  /// are filtered against the in-memory scheduled place IDs supplied by the
  /// editor instead of the repository. Same editability rules, same hard
  /// filters, same AI ranking and 10-second budget as the saved-itinerary
  /// flow — one business workflow, one validation engine.
  Future<ChangeLocationRecommendationResult> getPreviewReplacementRecommendations({
    required Place currentPlace,
    required DateTime tripDate,
    required int visitDurationMinutes,
    required Set<String> scheduledPlaceIds,
    List<String> interests = const [],
    String explorationTime = 'Standard',
  }) async {
    final deadline = DateTime.now().add(overallBudget);
    try {
      if (currentPlace.placeLatitude == 0 && currentPlace.placeLongitude == 0) {
        return ChangeLocationRecommendationResult.problem(
          'Unable to load this stop. Please try again.',
        );
      }

      // Retrieve + hard-filter candidates (same rules as the saved flow).
      final filtered = await _getFilteredCandidatesForPreview(
        currentPlace: currentPlace,
        tripDate: tripDate,
        visitDurationMinutes: visitDurationMinutes,
        scheduledPlaceIds: scheduledPlaceIds,
        interests: interests,
        explorationTime: explorationTime,
        deadline: deadline,
      );
      if (filtered.isEmpty) {
        return ChangeLocationRecommendationResult.problem(
          'No suitable replacement can fit into your remaining schedule. '
          'Try the manual search instead.',
        );
      }

      // AI ranking within the remaining budget (AI never schedules).
      final scored = await _aiRankCandidatesForPreview(
        currentPlace: currentPlace,
        visitDurationMinutes: visitDurationMinutes,
        tripDate: tripDate,
        interests: interests,
        explorationTime: explorationTime,
        candidates: filtered,
        deadline: deadline,
      );

      final outcome = scored.usedAi
          ? ChangeLocationOutcome.success
          : ChangeLocationOutcome.fallbackSuccess;
      return ChangeLocationRecommendationResult(
        outcome: outcome,
        message: scored.usedAi
            ? 'Recommendations generated.'
            : 'Showing nearby options (AI is temporarily unavailable).',
        recommendations: scored.recommendations,
      );
    } catch (e, stack) {
      debugPrint('[ChangeLocation] Preview recommendation failed: $e\n$stack');
      return ChangeLocationRecommendationResult.problem(
        'Unable to load recommendations right now. Please try again.',
      );
    }
  }

  /// Retrieves nearby candidates and hard-filters them BEFORE the AI sees
  /// them (preview variant — in-memory scheduled IDs, no repository reads).
  Future<List<Place>> _getFilteredCandidatesForPreview({
    required Place currentPlace,
    required DateTime tripDate,
    required int visitDurationMinutes,
    required Set<String> scheduledPlaceIds,
    required List<String> interests,
    required String explorationTime,
    required DateTime deadline,
  }) async {
    final maxVisitMinutes = visitDurationMinutes.clamp(
        ItineraryConstants.minimumVisitDurationMinutes,
        ItineraryConstants.maximumVisitDurationMinutes);

    try {
      final raw = await _maps
          .searchNearbyPlaces(
            latitude: currentPlace.placeLatitude,
            longitude: currentPlace.placeLongitude,
            radius: 2000,
            types: const ['tourist_attraction', 'museum', 'park', 'zoo',
              'art_gallery', 'church', 'shopping_mall', 'restaurant'],
          )
          .timeout(_remaining(deadline));
      if (raw.isEmpty) return const [];

      final candidates = <Place>[];
      for (final p in raw) {
        if (p.placeId == currentPlace.placeId) continue; // same as current
        if (scheduledPlaceIds.contains(p.placeId)) continue; // already in itinerary
        if (p.placeLatitude == 0 && p.placeLongitude == 0) continue; // invalid coords
        final duration = p.visitDurationMinutes ?? 90;
        if (duration > maxVisitMinutes) continue; // cannot fit the slot
        if (!_isOpenOnDate(p, tripDate)) continue; // unavailable on date
        final distanceKm = currentPlace.coordinates.distanceTo(p.coordinates);
        if (distanceKm > 5) continue; // impossible travel
        candidates.add(p);
        if (candidates.length >= maxAiCandidates) break;
      }

      // Compact pool: top N by existing scoring service order.
      if (candidates.length > maxAiCandidates) {
        final scored = _scoring.scorePlaces(
          places: candidates,
          selectedInterests: interests,
          mustVisitIds: const [],
          explorationTime: explorationTime,
          tripLocation: currentPlace.coordinates,
          strictInterestFilter: false,
        );
        return scored.take(maxAiCandidates).map((s) => s.place).toList();
      }
      return candidates;
    } on TimeoutException {
      debugPrint('[ChangeLocation] Preview candidate retrieval timed out');
      return const [];
    } catch (e) {
      debugPrint('[ChangeLocation] Preview candidate retrieval failed: $e');
      return const [];
    }
  }

  /// AI ranking for the preview flow (AI only selects/ranks; Dart decides
  /// feasibility). Shares the 10-second overall budget and ~6-7s AI window.
  Future<({List<ChangeLocationRecommendation> recommendations, bool usedAi})>
      _aiRankCandidatesForPreview({
    required Place currentPlace,
    required int visitDurationMinutes,
    required DateTime tripDate,
    required List<String> interests,
    required String explorationTime,
    required List<Place> candidates,
    required DateTime deadline,
  }) {
    final deterministicFallback = () {
      return (
        recommendations: _deterministicRanking(currentPlace, candidates),
        usedAi: false,
      );
    };

    final remaining = _remaining(deadline);
    final aiBudget = remaining < aiTimeout ? remaining : aiTimeout;
    if (candidates.isEmpty || aiBudget <= const Duration(seconds: 2)) {
      return Future.value(deterministicFallback());
    }

    final prompt = _buildPreviewPrompt(
      currentPlace: currentPlace,
      visitDurationMinutes: visitDurationMinutes,
      tripDate: tripDate,
      interests: interests,
      explorationTime: explorationTime,
      candidates: candidates,
    );

    return _ai
        .generateRawContent(
          prompt,
          timeout: aiBudget,
          totalBudget: aiBudget,
          requestName: 'CHANGE_LOCATION_PREVIEW',
        )
        .timeout(aiBudget)
        .then((raw) {
      final byId = {for (final p in candidates) p.placeId: p};
      final picks = _parseRecommendations(raw, byId);
      if (picks.isEmpty) return deterministicFallback();
      return (
        recommendations: picks
            .map((r) => ChangeLocationRecommendation(
                  place: byId[r.placeId]!,
                  aiScore: r.score,
                  reason: r.reason,
                  distanceText: _distanceText(
                    currentPlace.coordinates
                        .distanceTo(byId[r.placeId]!.coordinates),
                  ),
                ))
            .toList(),
        usedAi: true,
      );
    }).catchError((Object e) {
      debugPrint('[ChangeLocation] Preview AI failed: $e');
      return deterministicFallback();
    });
  }

  String _buildPreviewPrompt({
    required Place currentPlace,
    required int visitDurationMinutes,
    required DateTime tripDate,
    required List<String> interests,
    required String explorationTime,
    required List<Place> candidates,
  }) {
    final buf = StringBuffer()
      ..writeln('You are a travel replacement advisor.')
      ..writeln()
      ..writeln('CURRENT STOP being replaced:')
      ..writeln('- placeId: ${currentPlace.placeId}')
      ..writeln('- name: ${currentPlace.placeName}')
      ..writeln('- category: ${currentPlace.placeCategory ?? 'unknown'}')
      ..writeln('- visit minutes: $visitDurationMinutes')
      ..writeln()
      ..writeln('TRAVELER:')
      ..writeln('- interests: ${interests.isEmpty ? 'none' : interests.join(', ')}')
      ..writeln('- exploration: $explorationTime')
      ..writeln()
      ..writeln('ITINERARY:')
      ..writeln('- travel date: ${DateFormat('yyyy-MM-dd').format(tripDate)}')
      ..writeln()
      ..writeln('CANDIDATES (use ONLY these placeIds, all pre-filtered as feasible):');
    for (final p in candidates) {
      buf.writeln(
        '- placeId: ${p.placeId} | name: ${p.placeName} | '
        'category: ${p.placeCategory ?? 'unknown'} | '
        'rating: ${p.placeRating.toStringAsFixed(1)} | '
        'visit: ${p.visitDurationMinutes ?? 90} min | '
        'distance km: ${currentPlace.coordinates.distanceTo(p.coordinates).toStringAsFixed(1)}',
      );
    }
    buf
      ..writeln()
      ..writeln('TASK: Rank the 5 best replacements. Balance the original '
          'stop purpose (prefer similar categories softly, never force it), '
          'traveler interests, distance and visit duration fit. Never '
          'invent places; use only supplied placeIds. Do NOT schedule, do '
          'NOT compute times.')
      ..writeln()
      ..writeln('Respond with compact JSON ONLY (no markdown, no extra '
          'text), max 5 items, best first:')
      ..writeln('{"recommendations":[{"placeId":"...","score":94,'
          '"reason":"max 12 words"}]}');
    return buf.toString();
  }

  // ─── Replacement (final validation + persistence) ───────────

  /// Replaces an existing stop with [newPlaceId] after full deterministic
  /// validation. The original itinerary is never modified unless every
  /// check passes.
  Future<ChangeLocationResult> replaceItineraryStop({
    required String itineraryId,
    required int stopId,
    required String newPlaceId,
  }) async {
    try {
      final itinerary = await _itineraryRepo.getItinerary(itineraryId);
      final stop = await _findStop(itineraryId, stopId);
      if (stop == null) {
        return ChangeLocationResult.problem(
          'Unable to load this itinerary. Please try again.',
        );
      }

      // Re-validate EVERYTHING at confirmation time — the recommendation
      // being valid minutes ago does not matter.
      if (!validateItineraryModificationDate(itinerary)) {
        return ChangeLocationResult.problem(
          'This itinerary has ended and can no longer be modified.',
        );
      }
      if (!isStopEditable(itinerary, stop)) {
        return ChangeLocationResult.problem(
          'This stop can no longer be changed.',
        );
      }

      final newPlace = await _loadPlace(newPlaceId);
      if (newPlace == null) {
        return ChangeLocationResult.problem(
          'Unable to load the selected place. Please try again.',
        );
      }
      if (newPlace.placeId == stop.placeId) {
        return ChangeLocationResult.problem(
          'This place is already scheduled for this stop.',
        );
      }
      final scheduledIds = await _scheduledPlaceIds(itineraryId);
      if (isPlaceAlreadyScheduled(
        newPlaceId,
        scheduledIds,
        excludeStopId: stopId,
      )) {
        return ChangeLocationResult.problem(
          'This place is already in your itinerary.',
        );
      }

      // Build the resulting day: replace the place, keep the stop slot and
      // scheduled time where feasible.
      final dayStops = await _loadDayStops(itineraryId, stop.dayIndex);
      final updatedStop = _buildUpdatedStop(stop, newPlace);
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == stopId) updatedStop else s,
      ];
      final index = resulting.indexWhere((s) => s.stopId == stopId);

      // Recalculate the affected schedule: re-route the inbound leg, shift
      // subsequent stops only if the replacement overruns its slot.
      final recalculated =
          await _recalculateAffectedSchedule(itinerary, resulting, index);
      if (recalculated == null) {
        return ChangeLocationResult.problem(
          'No feasible replacement schedule could be built for this place. '
          'The original stop is unchanged.',
        );
      }

      // Full deterministic validation of the resulting day (opening hours,
      // travel, window, conflicts, duplicates, completed stops).
      final reroute = <int>{
        if (index > 0) index,
        if (index < recalculated.length - 1) index + 1,
      };
      final validation = await _validator.validateResultingDay(
        dayStops: recalculated,
        dayDate: _dayDate(itinerary, stop.dayIndex),
        window: ItineraryConstants.explorationWindowFor(
            itinerary.explorationTime),
        transportMode: itinerary.transportationMode,
        rerouteLegIndices: reroute,
        focusStop: stop,
        candidatePlace: newPlace,
        travelPace: itinerary.travelPace,
      );
      if (!validation.isValid) {
        return ChangeLocationResult.problem(
          validation.issues.first.message,
        );
      }

      // Persist: save the place row (joins need it), update the replaced
      // stop with its freshly routed inbound travel, then persist any
      // shifted subsequent stops. Completed/past stops are never touched.
      try {
        await _placeRepo.savePlace(newPlace);
      } catch (e) {
        debugPrint('[ChangeLocation] Place save failed: $e');
      }

      var toSave = recalculated[index];
      if (index > 0) {
        final prevPlace = recalculated[index - 1].place;
        if (prevPlace != null) {
          final routed = await _validator.travelMinutesBetween(
            prevPlace.coordinates,
            newPlace.coordinates,
            itinerary.transportationMode,
          );
          if (routed != null) {
            toSave = toSave.copyWith(travelFromPrevMinutes: routed);
          }
        }
      } else {
        toSave = toSave.copyWith(travelFromPrevMinutes: 0);
      }

      final savedStop = await _stopRepo.updateStop(toSave);
      for (var i = index + 1; i < recalculated.length; i++) {
        final original =
            dayStops.firstWhere((s) => s.stopId == recalculated[i].stopId);
        if (original.startTime != recalculated[i].startTime ||
            original.endTime != recalculated[i].endTime) {
          await _stopRepo.updateStop(recalculated[i]);
        }
      }
      debugPrint('[ChangeLocation] Replaced stop $stopId place with '
          '${newPlace.placeId}');

      return ChangeLocationResult(
        outcome: ChangeLocationOutcome.success,
        message: 'Location updated successfully.',
        updatedStop: savedStop.copyWith(place: newPlace),
      );
    } catch (e, stack) {
      debugPrint('[ChangeLocation] Replace failed: $e\n$stack');
      return ChangeLocationResult.problem(
        'Unable to change this stop right now. Please try again.',
      );
    }
  }

  // ============================================================
  // CANDIDATES
  // ============================================================

  /// Retrieves nearby candidates via the existing Google Places service and
  /// hard-filters them deterministically BEFORE the AI sees them.
  Future<List<Place>> _getFilteredCandidates({
    required Itinerary itinerary,
    required ItineraryStop stop,
    required DateTime deadline,
  }) async {
    final currentPlace = stop.place!;
    final slotMinutes = stop.endTime.difference(stop.startTime).inMinutes;
    // Available exploration time for the replacement visit.
    final maxVisitMinutes = slotMinutes.clamp(
        ItineraryConstants.minimumVisitDurationMinutes,
        ItineraryConstants.maximumVisitDurationMinutes);

    try {
      final raw = await _maps
          .searchNearbyPlaces(
            latitude: currentPlace.placeLatitude,
            longitude: currentPlace.placeLongitude,
            radius: 2000,
            types: const ['tourist_attraction', 'museum', 'park', 'zoo',
              'art_gallery', 'church', 'shopping_mall', 'restaurant'],
          )
          .timeout(_remaining(deadline));
      if (raw.isEmpty) return const [];

      // Hard filter — remove anything violating a hard constraint.
      final scheduledIds = await _scheduledPlaceIds(itinerary.itineraryId);
      final existingIds = scheduledIds
          .where((id) => id != stop.placeId)
          .toSet();

      final candidates = <Place>[];
      for (final p in raw) {
        if (p.placeId == currentPlace.placeId) continue;
        if (existingIds.contains(p.placeId)) continue;
        if (p.placeLatitude == 0 && p.placeLongitude == 0) continue;
        final duration = p.visitDurationMinutes ?? 90;
        if (duration > maxVisitMinutes) continue;
        if (!_isOpenOnDate(p, _dayDate(itinerary, stop.dayIndex))) continue;
        final distanceKm = currentPlace.coordinates.distanceTo(p.coordinates);
        if (distanceKm > 5) continue;
        candidates.add(p);
        if (candidates.length >= maxAiCandidates) break;
      }

      // Compact pool: top 15 by score order.
      if (candidates.length > maxAiCandidates) {
        final scored = _scoring.scorePlaces(
          places: candidates,
          selectedInterests: itinerary.interests,
          mustVisitIds: const [],
          explorationTime: itinerary.explorationTime,
          tripLocation: currentPlace.coordinates,
          strictInterestFilter: false,
        );
        return scored.take(maxAiCandidates).map((s) => s.place).toList();
      }
      return candidates;
    } on TimeoutException {
      debugPrint('[ChangeLocation] Candidate retrieval timed out');
      return const [];
    } catch (e) {
      debugPrint('[ChangeLocation] Candidate retrieval failed: $e');
      return const [];
    }
  }

  /// Whether the place has opening hours that include [date]'s weekday.
  bool _isOpenOnDate(Place place, DateTime date) {
    final hours = place.openingHours;
    if (hours == null || hours.periods.isEmpty) return true; // unknown = OK
    return hours.isOpenOnDay(date.weekday);
  }

  Future<Set<String>> _scheduledPlaceIds(String itineraryId) async {
    final all = await _stopRepo.getStopsForItinerary(itineraryId);
    return all.map((s) => s.placeId).toSet();
  }

  /// Whether [placeId] already exists on the itinerary (excluding the stop
  /// being replaced itself).
  bool isPlaceAlreadyScheduled(
    String placeId,
    Set<String> scheduledIds, {
    required int excludeStopId,
  }) {
    return scheduledIds.contains(placeId);
  }

  // ============================================================
  // AI RECOMMENDATION
  // ============================================================

  /// Ranks candidates with the AI within the remaining budget; falls back
  /// to deterministic ranking when the AI is unavailable, slow, or returns
  /// unusable output. The AI only selects/ranks — it never schedules.
  Future<({List<ChangeLocationRecommendation> recommendations, bool usedAi})>
      _aiRankCandidates({
    required ItineraryStop currentStop,
    required Itinerary itinerary,
    required List<Place> candidates,
    required DateTime deadline,
  }) {
    final currentPlace = currentStop.place!;
    final deterministicFallback = () {
      return (
        recommendations: _deterministicRanking(currentPlace, candidates),
        usedAi: false,
      );
    };

    final remaining = _remaining(deadline);
    final aiBudget = remaining < aiTimeout ? remaining : aiTimeout;
    if (candidates.isEmpty || aiBudget <= const Duration(seconds: 2)) {
      return Future.value(deterministicFallback());
    }

    final prompt = _buildRecommendationPrompt(
      currentStop: currentStop,
      itinerary: itinerary,
      candidates: candidates,
    );

    return _ai
        .generateRawContent(
          prompt,
          timeout: aiBudget,
          totalBudget: aiBudget,
          requestName: 'CHANGE_LOCATION',
        )
        .timeout(aiBudget)
        .then((raw) {
      final byId = {for (final p in candidates) p.placeId: p};
      final picks = _parseRecommendations(raw, byId);
      if (picks.isEmpty) return deterministicFallback();
      return (
        recommendations: picks
            .map((r) => ChangeLocationRecommendation(
                  place: byId[r.placeId]!,
                  aiScore: r.score,
                  reason: r.reason,
                  distanceText: _distanceText(
                    currentPlace.coordinates
                        .distanceTo(byId[r.placeId]!.coordinates),
                  ),
                ))
            .toList(),
        usedAi: true,
      );
    }).catchError((Object e) {
      debugPrint('[ChangeLocation] AI recommendation failed: $e');
      return deterministicFallback();
    });
  }

  /// Parses the compact AI JSON. Only placeIds present in the supplied
  /// candidate pool are accepted — invented places are dropped.
  List<({String placeId, int score, String reason})> _parseRecommendations(
    String raw,
    Map<String, Place> byId,
  ) {
    try {
      var text = raw.trim();
      final fenceStart = text.indexOf('```');
      if (fenceStart >= 0) {
        text = text.replaceAll('```', '').trim();
      }
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return const [];
      final data = jsonDecode(text.substring(start, end + 1));
      if (data is! Map<String, dynamic>) return const [];
      final list = data['recommendations'];
      if (list is! List) return const [];

      final picks = <({String placeId, int score, String reason})>[];
      final seen = <String>{};
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['placeId']?.toString().trim();
        if (id == null || !byId.containsKey(id) || !seen.add(id)) continue;
        final score = (item['score'] as num?)?.toInt() ?? 0;
        final reason = (item['reason']?.toString() ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        picks.add((
          placeId: id,
          score: score.clamp(0, 100),
          reason: reason.isEmpty ? 'Recommended for your trip.' : reason,
        ));
        if (picks.length >= 5) break;
      }
      // Keep the AI's ranking order (already best-first).
      picks.sort((a, b) => b.score.compareTo(a.score));
      return picks;
    } catch (e) {
      debugPrint('[ChangeLocation] AI response parse failed: $e');
      return const [];
    }
  }

  String _buildRecommendationPrompt({
    required ItineraryStop currentStop,
    required Itinerary itinerary,
    required List<Place> candidates,
  }) {
    final currentPlace = currentStop.place!;
    final buf = StringBuffer()
      ..writeln('You are a travel replacement advisor.')
      ..writeln()
      ..writeln('CURRENT STOP being replaced:')
      ..writeln('- placeId: ${currentPlace.placeId}')
      ..writeln('- name: ${currentPlace.placeName}')
      ..writeln('- category: ${currentPlace.placeCategory ?? 'unknown'}')
      ..writeln('- visit minutes: ${currentStop.durationMinutes}')
      ..writeln()
      ..writeln('TRAVELER:')
      ..writeln('- interests: ${itinerary.interests.join(', ')}')
      ..writeln('- travel pace: ${itinerary.travelPace}')
      ..writeln('- exploration: ${itinerary.explorationTime}')
      ..writeln('- transport: ${itinerary.transportationMode}')
      ..writeln()
      ..writeln('CANDIDATES (use ONLY these placeIds):');
    for (final p in candidates) {
      buf.writeln(
        '- placeId: ${p.placeId} | name: ${p.placeName} | '
        'category: ${p.placeCategory ?? 'unknown'} | '
        'rating: ${p.placeRating.toStringAsFixed(1)} | '
        'visit: ${p.visitDurationMinutes ?? 90} min | '
        'distance km: ${currentPlace.coordinates.distanceTo(p.coordinates).toStringAsFixed(1)}',
      );
    }
    buf
      ..writeln()
      ..writeln('TASK: Rank the 5 best replacements. Balance the original '
          'stop purpose (prefer similar categories softly, never force it), '
          'traveler interests, distance and visit duration fit. Never '
          'invent places; use only supplied placeIds.')
      ..writeln()
      ..writeln('Respond with compact JSON ONLY (no markdown, no extra '
          'text), max 5 items, best first:')
      ..writeln('{"recommendations":[{"placeId":"...","score":94,'
          '"reason":"max 12 words"}]}');
    return buf.toString();
  }

  /// Deterministic ranking fallback (no AI): prefer same category, higher
  /// rating, shorter distance.
  List<ChangeLocationRecommendation> _deterministicRanking(
    Place currentPlace,
    List<Place> candidates,
  ) {
    double score(Place p) {
      var s = 0.0;
      final curCat = currentPlace.placeCategory?.toLowerCase();
      final cat = p.placeCategory?.toLowerCase();
      if (curCat != null && cat != null && curCat == cat) s += 40;
      s += (p.placeRating / 5.0) * 40;
      final km = currentPlace.coordinates.distanceTo(p.coordinates);
      s += (1.0 - (km / 5).clamp(0.0, 1.0)) * 20;
      return s;
    }

    final sorted = List<Place>.from(candidates)..sort((a, b) => score(b).compareTo(score(a)));
    return sorted.take(5).map((p) {
      final km = currentPlace.coordinates.distanceTo(p.coordinates);
      return ChangeLocationRecommendation(
        place: p,
        aiScore: score(p).round().clamp(0, 100),
        reason: catReason(p, currentPlace),
        distanceText: _distanceText(km),
      );
    }).toList();
  }

  static String catReason(Place p, Place current) {
    final curCat = current.placeCategory?.toLowerCase() ?? '';
    final cat = p.placeCategory?.toLowerCase() ?? '';
    if (curCat.isNotEmpty && cat == curCat) {
      return 'Similar to ${current.placeName} and highly rated.';
    }
    return 'Well rated and close to your current stop.';
  }

  static String _distanceText(double km) {
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  // ============================================================
  // SCHEDULE RECALCULATION
  // ============================================================

  /// Keeps every stop's slot; only shifts subsequent stops when the
  /// replacement overruns. Completed stops are never rearranged — if a
  /// shift would touch one, no feasible schedule exists. Returns null
  /// when no feasible schedule can be constructed.
  Future<List<ItineraryStop>?> _recalculateAffectedSchedule(
    Itinerary itinerary,
    List<ItineraryStop> resulting,
    int replacedIndex,
  ) async {
    final stops = List<ItineraryStop>.from(resulting)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

    var cursorEnd = stops[replacedIndex].endTime;
    for (var i = replacedIndex + 1; i < stops.length; i++) {
      final next = stops[i];
      if (next.stopStatus == EditStopStatuses.completed) {
        // A completed stop's schedule is immutable; it may only remain in
        // place if the replacement did not push into it.
        final travel = next.travelFromPrevMinutes ?? 0;
        if (next.startTime.isBefore(cursorEnd.add(Duration(minutes: travel)))) {
          return null;
        }
        cursorEnd = next.endTime;
        continue;
      }

      final travel = next.travelFromPrevMinutes ?? 0;
      final earliest = cursorEnd.add(Duration(minutes: travel));
      if (next.startTime.isBefore(earliest)) {
        final shiftedStart = earliest;
        final shiftedEnd = shiftedStart.add(
            Duration(minutes: next.durationMinutes));
        stops[i] = _copyWithTimes(next, shiftedStart, shiftedEnd);
        cursorEnd = shiftedEnd;
      } else {
        cursorEnd = next.endTime;
      }
    }
    return stops;
  }

  ItineraryStop _copyWithTimes(ItineraryStop stop, DateTime start, DateTime end) {
    return ItineraryStop(
      stopId: stop.stopId,
      itineraryId: stop.itineraryId,
      placeId: stop.placeId,
      destinationId: stop.destinationId,
      dayIndex: stop.dayIndex,
      stopOrder: stop.stopOrder,
      startTime: start,
      endTime: end,
      durationMinutes: stop.durationMinutes,
      travelFromPrevMinutes: stop.travelFromPrevMinutes,
      stopStatus: stop.stopStatus,
      skipReason: stop.skipReason,
      weatherNote: stop.weatherNote,
      place: stop.place,
      createdAt: stop.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Builds the replacement stop: identical stop identity (stopId,
  /// itineraryId, dayIndex, stopOrder) and preserved schedule position
  /// (same start/end/duration) with the new place.
  ItineraryStop _buildUpdatedStop(ItineraryStop stop, Place newPlace) {
    return ItineraryStop(
      stopId: stop.stopId,
      itineraryId: stop.itineraryId,
      placeId: newPlace.placeId,
      destinationId: stop.destinationId,
      dayIndex: stop.dayIndex,
      stopOrder: stop.stopOrder,
      startTime: stop.startTime,
      endTime: stop.endTime,
      durationMinutes: stop.durationMinutes,
      travelFromPrevMinutes: stop.travelFromPrevMinutes,
      stopStatus: stop.stopStatus,
      skipReason: stop.skipReason,
      weatherNote: stop.weatherNote,
      place: newPlace,
      createdAt: stop.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Small helpers
  // ============================================================

  Future<ItineraryStop?> _findStop(String itineraryId, int stopId) async {
    final all = await _stopRepo.getStopsForItinerary(itineraryId);
    final match = all.where((s) => s.stopId == stopId).toList();
    if (match.isEmpty) return null;
    final stop = match.first;
    Place? place = stop.place;
    place ??= await _placeRepo.getPlace(stop.placeId);
    return stop.copyWith(place: place);
  }

  Future<Place?> _loadPlace(String placeId) async {
    try {
      return await _placeRepo.getPlace(placeId);
    } catch (e) {
      debugPrint('[ChangeLocation] Place load failed: $e');
      return null;
    }
  }

  Future<List<ItineraryStop>> _loadDayStops(
      String itineraryId, int dayIndex) async {
    final all = await _stopRepo.getStopsForItinerary(itineraryId);
    return all
        .where((s) => s.dayIndex == dayIndex)
        .toList()
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
  }

  DateTime _dayDate(Itinerary itinerary, int dayIndex) =>
      itinerary.startDate.add(Duration(days: dayIndex - 1));

  DateTime _stopDateTime(Itinerary itinerary, ItineraryStop stop) {
    final dayDate = _dayDate(itinerary, stop.dayIndex);
    return DateTime(dayDate.year, dayDate.month, dayDate.day,
        stop.endTime.hour, stop.endTime.minute);
  }

  Duration _remaining(DateTime deadline) {
    final r = deadline.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }
}

/// Status string constants shared with the existing stop model.
class EditStopStatuses {
  static const String planned = 'PLANNED';
  static const String completed = 'COMPLETED';
  static const String skipped = 'SKIPPED';
}
