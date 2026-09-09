import 'package:narrate_my/model/repositories/interfaces/itinerary/place_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/itinerary_stop_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/itinerary_repository.dart';
// lib/model/business_logic/itinerary_service/change_location_service.dart
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
import '../../../view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';
import './itinerary_validator.dart';
import './scoring_service.dart';

// ============================================================
// RESULT TYPES
// ============================================================

enum ChangeLocationOutcome { success, fallbackSuccess, problem }

class ChangeLocationRecommendation {
  final Place place;
  final int aiScore;
  final String reason;
  final String distanceText;
  final bool isBookmarked;
  final int suggestedDuration; // ✅ NEW FIELD

  const ChangeLocationRecommendation({
    required this.place,
    required this.aiScore,
    required this.reason,
    required this.distanceText,
    this.isBookmarked = false,
    required this.suggestedDuration, // ✅ REQUIRED
  });
}

class ChangeLocationRecommendationResult {
  final ChangeLocationOutcome outcome;
  final String message;
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

class ChangeLocationResult {
  final ChangeLocationOutcome outcome;
  final String message;
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

  final ItineraryRepository _itineraryRepo =
      DatabaseManager().itineraryRepository;
  final ItineraryStopRepository _stopRepo =
      DatabaseManager().itineraryStopRepository;
  final PlaceRepository _placeRepo =
      DatabaseManager().placeRepository;
  final GoogleMapsService _maps = GoogleMapsService();
  final ItineraryValidator _validator = ItineraryValidator();
  final ScoringService _scoring = ScoringService();
  final AIService _ai = AIService();

  bool validateItineraryModificationDate(Itinerary itinerary) {
    return ItineraryStatusResolver.resolve(
      startDate: itinerary.startDate,
      endDate: itinerary.endDate,
    ).isEditable;
  }

  bool isStopEditable(Itinerary itinerary, ItineraryStop stop) {
    if (!validateItineraryModificationDate(itinerary)) return false;
    if (stop.stopStatus == EditStopStatuses.completed) return false;
    if (stop.stopStatus == EditStopStatuses.skipped) return false;

    final now = DateTime.now();
    final endOfDay = _dayDate(itinerary, stop.dayIndex)
        .add(const Duration(days: 1));
    if (!now.isBefore(endOfDay)) return false;

    final scheduledEnd = _stopDateTime(itinerary, stop);
    return now.isBefore(scheduledEnd);
  }

  List<int> getEditableDays(Itinerary itinerary) {
    final editable = <int>[];
    for (var d = 1; d <= itinerary.totalDays; d++) {
      final endOfDay = _dayDate(itinerary, d).add(const Duration(days: 1));
      if (DateTime.now().isBefore(endOfDay)) editable.add(d);
    }
    return editable;
  }

  Future<ChangeLocationRecommendationResult> getReplacementRecommendations({
    required String itineraryId,
    required int stopId,
    List<Place> bookmarkedPlaces = const [],
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

      final currentPlace = stop.place!;
      final scheduledIds = await _scheduledPlaceIds(itineraryId);
      final tripDate = _dayDate(itinerary, stop.dayIndex);
      final slotMinutes = stop.endTime.difference(stop.startTime).inMinutes;

      final validBookmarks = _filterValidCandidates(
        candidates: bookmarkedPlaces,
        currentPlace: currentPlace,
        scheduledIds: scheduledIds,
        excludeStopId: stopId,
        tripDate: tripDate,
        slotMinutes: slotMinutes,
      );

      List<Place> nearbyCandidates = [];
      if (validBookmarks.length < maxAiCandidates) {
        nearbyCandidates = await _getFilteredCandidates(
          itinerary: itinerary,
          stop: stop,
          deadline: deadline,
        );
      }

      final bookmarkedIds = validBookmarks.map((p) => p.placeId).toSet();
      final combinedMap = <String, Place>{};
      for (final p in validBookmarks) {
        combinedMap[p.placeId] = p;
      }
      for (final p in nearbyCandidates) {
        if (!combinedMap.containsKey(p.placeId)) {
          combinedMap[p.placeId] = p;
        }
      }

      final combinedList = combinedMap.values.take(maxAiCandidates).toList();
      if (combinedList.isEmpty) {
        return ChangeLocationRecommendationResult.problem(
          'No suitable replacement can fit into your remaining schedule. '
              'Try the manual search instead.',
        );
      }

      final scored = await _aiRankCandidates(
        currentStop: stop,
        itinerary: itinerary,
        candidates: combinedList,
        bookmarkedIds: bookmarkedIds,
        deadline: deadline,
      );

      final outcome = scored.usedAi
          ? ChangeLocationOutcome.success
          : ChangeLocationOutcome.fallbackSuccess;
      return ChangeLocationRecommendationResult(
        outcome: outcome,
        message: scored.usedAi
            ? 'Recommendations generated.'
            : 'Showing saved and nearby options.',
        recommendations: scored.recommendations,
      );
    } catch (e, stack) {
      debugPrint('[ChangeLocation] Recommendation failed: $e\n$stack');
      return ChangeLocationRecommendationResult.problem(
        'Unable to load recommendations right now. Please try again.',
      );
    }
  }

  Future<ChangeLocationRecommendationResult> getPreviewReplacementRecommendations({
    required Place currentPlace,
    required DateTime tripDate,
    required int visitDurationMinutes,
    required Set<String> scheduledPlaceIds,
    List<Place> bookmarkedPlaces = const [],
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

      final validBookmarks = _filterValidCandidates(
        candidates: bookmarkedPlaces,
        currentPlace: currentPlace,
        scheduledIds: scheduledPlaceIds,
        excludeStopId: -1,
        tripDate: tripDate,
        slotMinutes: visitDurationMinutes,
      );

      List<Place> nearbyCandidates = [];
      if (validBookmarks.length < maxAiCandidates) {
        nearbyCandidates = await _getFilteredCandidatesForPreview(
          currentPlace: currentPlace,
          tripDate: tripDate,
          visitDurationMinutes: visitDurationMinutes,
          scheduledPlaceIds: scheduledPlaceIds,
          interests: interests,
          explorationTime: explorationTime,
          deadline: deadline,
        );
      }

      final bookmarkedIds = validBookmarks.map((p) => p.placeId).toSet();
      final combinedMap = <String, Place>{};
      for (final p in validBookmarks) {
        combinedMap[p.placeId] = p;
      }
      for (final p in nearbyCandidates) {
        if (!combinedMap.containsKey(p.placeId)) {
          combinedMap[p.placeId] = p;
        }
      }

      final combinedList = combinedMap.values.take(maxAiCandidates).toList();
      if (combinedList.isEmpty) {
        return ChangeLocationRecommendationResult.problem(
          'No suitable replacement can fit into your remaining schedule. '
              'Try the manual search instead.',
        );
      }

      final scored = await _aiRankCandidatesForPreview(
        currentPlace: currentPlace,
        visitDurationMinutes: visitDurationMinutes,
        tripDate: tripDate,
        interests: interests,
        explorationTime: explorationTime,
        candidates: combinedList,
        bookmarkedIds: bookmarkedIds,
        deadline: deadline,
      );

      final outcome = scored.usedAi
          ? ChangeLocationOutcome.success
          : ChangeLocationOutcome.fallbackSuccess;
      return ChangeLocationRecommendationResult(
        outcome: outcome,
        message: scored.usedAi
            ? 'Recommendations generated.'
            : 'Showing saved and nearby options.',
        recommendations: scored.recommendations,
      );
    } catch (e, stack) {
      debugPrint('[ChangeLocation] Preview recommendation failed: $e\n$stack');
      return ChangeLocationRecommendationResult.problem(
        'Unable to load recommendations right now. Please try again.',
      );
    }
  }

  List<Place> _filterValidCandidates({
    required List<Place> candidates,
    required Place currentPlace,
    required Set<String> scheduledIds,
    required int excludeStopId,
    required DateTime tripDate,
    required int slotMinutes,
  }) {
    final existingIds = scheduledIds.where((id) => id != currentPlace.placeId).toSet();

    return candidates.where((p) {
      if (p.placeId == currentPlace.placeId) return false;
      if (existingIds.contains(p.placeId)) return false;
      if (p.placeLatitude == 0 && p.placeLongitude == 0) return false;
      // ✅ Removed the static duration filter
      if (!_isOpenOnDate(p, tripDate)) return false;
      final distanceKm = currentPlace.coordinates.distanceTo(p.coordinates);
      if (distanceKm > 5) return false;
      return true;
    }).toList();
  }

  Future<List<Place>> _getFilteredCandidatesForPreview({
    required Place currentPlace,
    required DateTime tripDate,
    required int visitDurationMinutes,
    required Set<String> scheduledPlaceIds,
    required List<String> interests,
    required String explorationTime,
    required DateTime deadline,
  }) async {
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
        if (p.placeId == currentPlace.placeId) continue;
        if (scheduledPlaceIds.contains(p.placeId)) continue;
        if (p.placeLatitude == 0 && p.placeLongitude == 0) continue;
        // ✅ Removed the static duration filter
        if (!_isOpenOnDate(p, tripDate)) continue;
        final distanceKm = currentPlace.coordinates.distanceTo(p.coordinates);
        if (distanceKm > 5) continue;
        candidates.add(p);
        if (candidates.length >= maxAiCandidates) break;
      }

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

  Future<({List<ChangeLocationRecommendation> recommendations, bool usedAi})>
  _aiRankCandidatesForPreview({
    required Place currentPlace,
    required int visitDurationMinutes,
    required DateTime tripDate,
    required List<String> interests,
    required String explorationTime,
    required List<Place> candidates,
    required Set<String> bookmarkedIds,
    required DateTime deadline,
  }) {
    final deterministicFallback = () {
      return (
      recommendations: _deterministicRanking(currentPlace, candidates, bookmarkedIds),
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
      bookmarkedIds: bookmarkedIds,
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
        reason: bookmarkedIds.contains(r.placeId)
            ? 'From your bookmarks. ${r.reason}'
            : r.reason,
        distanceText: _distanceText(
          currentPlace.coordinates
              .distanceTo(byId[r.placeId]!.coordinates),
        ),
        isBookmarked: bookmarkedIds.contains(r.placeId),
        suggestedDuration: r.duration, // ✅ ADDED DURATION
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
    required Set<String> bookmarkedIds,
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
      final isSaved = bookmarkedIds.contains(p.placeId) ? ' [BOOKMARKED BY USER]' : '';
      buf.writeln(
        '- placeId: ${p.placeId} | name: ${p.placeName}$isSaved | '
            'category: ${p.placeCategory ?? 'unknown'} | '
            'rating: ${p.placeRating.toStringAsFixed(1)} | '
            'distance km: ${currentPlace.coordinates.distanceTo(p.coordinates).toStringAsFixed(1)}',
      );
    }
    buf
      ..writeln()
      ..writeln('TASK: Rank the 5 best replacements and suggest an optimal visit duration for each. Give strong consideration to places '
          'marked [BOOKMARKED BY USER] if they fit the purpose. Balance purpose, distance, '
          'and ratings. Never invent places; use only supplied placeIds.')
      ..writeln()
      ..writeln('Respond with compact JSON ONLY (no markdown, no extra '
          'text), max 5 items, best first:')
    // ✅ ASK FOR DURATION IN OUTPUT
      ..writeln('{"recommendations":[{"placeId":"...","score":94,'
          '"reason":"max 12 words","duration":60}]}');
    return buf.toString();
  }

  // ✅ UPDATED: Requires new duration
  Future<ChangeLocationResult> replaceItineraryStop({
    required String itineraryId,
    required int stopId,
    required Place newPlace, // ⬅️ CHANGED THIS LINE
    required int newDurationMinutes,
  }) async {
    try {
      final itinerary = await _itineraryRepo.getItinerary(itineraryId);
      final stop = await _findStop(itineraryId, stopId);
      if (stop == null) {
        return ChangeLocationResult.problem(
          'Unable to load this itinerary. Please try again.',
        );
      }

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

      if (newPlace.placeId == stop.placeId) {
        return ChangeLocationResult.problem(
          'This place is already scheduled for this stop.',
        );
      }

      final scheduledIds = await _scheduledPlaceIds(itineraryId);
      if (isPlaceAlreadyScheduled(
        newPlace.placeId, // ⬅️ CHANGED THIS LINE
        scheduledIds,
        excludeStopId: stopId,
      )) {
        return ChangeLocationResult.problem(
          'This place is already in your itinerary.',
        );
      }

      final dayStops = await _loadDayStops(itineraryId, stop.dayIndex);

      // ✅ PASS NEW DURATION
      final updatedStop = _buildUpdatedStop(stop, newPlace, newDurationMinutes);
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == stopId) updatedStop else s,
      ];
      final index = resulting.indexWhere((s) => s.stopId == stopId);

      final recalculated =
      await _recalculateAffectedSchedule(itinerary, resulting, index);
      if (recalculated == null) {
        return ChangeLocationResult.problem(
          'No feasible replacement schedule could be built for this place. '
              'The original stop is unchanged.',
        );
      }

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

  Future<List<Place>> _getFilteredCandidates({
    required Itinerary itinerary,
    required ItineraryStop stop,
    required DateTime deadline,
  }) async {
    final currentPlace = stop.place!;

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

      final scheduledIds = await _scheduledPlaceIds(itinerary.itineraryId);
      final existingIds = scheduledIds
          .where((id) => id != stop.placeId)
          .toSet();

      final candidates = <Place>[];
      for (final p in raw) {
        if (p.placeId == currentPlace.placeId) continue;
        if (existingIds.contains(p.placeId)) continue;
        if (p.placeLatitude == 0 && p.placeLongitude == 0) continue;
        // ✅ Removed the static duration filter
        if (!_isOpenOnDate(p, _dayDate(itinerary, stop.dayIndex))) continue;
        final distanceKm = currentPlace.coordinates.distanceTo(p.coordinates);
        if (distanceKm > 5) continue;
        candidates.add(p);
        if (candidates.length >= maxAiCandidates) break;
      }

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

  bool _isOpenOnDate(Place place, DateTime date) {
    final hours = place.openingHours;
    if (hours == null || hours.periods.isEmpty) return true;
    return hours.isOpenOnDay(date.weekday);
  }

  Future<Set<String>> _scheduledPlaceIds(String itineraryId) async {
    final all = await _stopRepo.getStopsForItinerary(itineraryId);
    return all.map((s) => s.placeId).toSet();
  }

  bool isPlaceAlreadyScheduled(
      String placeId,
      Set<String> scheduledIds, {
        required int excludeStopId,
      }) {
    return scheduledIds.contains(placeId);
  }

  Future<({List<ChangeLocationRecommendation> recommendations, bool usedAi})>
  _aiRankCandidates({
    required ItineraryStop currentStop,
    required Itinerary itinerary,
    required List<Place> candidates,
    required Set<String> bookmarkedIds,
    required DateTime deadline,
  }) {
    final currentPlace = currentStop.place!;
    final deterministicFallback = () {
      return (
      recommendations: _deterministicRanking(currentPlace, candidates, bookmarkedIds),
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
      bookmarkedIds: bookmarkedIds,
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
        reason: bookmarkedIds.contains(r.placeId)
            ? 'From your bookmarks. ${r.reason}'
            : r.reason,
        distanceText: _distanceText(
          currentPlace.coordinates
              .distanceTo(byId[r.placeId]!.coordinates),
        ),
        isBookmarked: bookmarkedIds.contains(r.placeId),
        suggestedDuration: r.duration, // ✅ ADDED DURATION
      ))
          .toList(),
      usedAi: true,
      );
    }).catchError((Object e) {
      debugPrint('[ChangeLocation] AI recommendation failed: $e');
      return deterministicFallback();
    });
  }

  // ✅ UPDATED TUPLE TO RETURN DURATION
  List<({String placeId, int score, String reason, int duration})> _parseRecommendations(
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

      final picks = <({String placeId, int score, String reason, int duration})>[];
      final seen = <String>{};
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['placeId']?.toString().trim();
        if (id == null || !byId.containsKey(id) || !seen.add(id)) continue;
        final score = (item['score'] as num?)?.toInt() ?? 0;
        final reason = (item['reason']?.toString() ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        // ✅ PARSE DURATION
        final duration = (item['duration'] as num?)?.toInt() ?? 90;
        picks.add((
        placeId: id,
        score: score.clamp(0, 100),
        reason: reason.isEmpty ? 'Recommended for your trip.' : reason,
        duration: duration,
        ));
        if (picks.length >= 5) break;
      }
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
    required Set<String> bookmarkedIds,
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
      final isSaved = bookmarkedIds.contains(p.placeId) ? ' [BOOKMARKED BY USER]' : '';
      buf.writeln(
        '- placeId: ${p.placeId} | name: ${p.placeName}$isSaved | '
            'category: ${p.placeCategory ?? 'unknown'} | '
            'rating: ${p.placeRating.toStringAsFixed(1)} | '
            'distance km: ${currentPlace.coordinates.distanceTo(p.coordinates).toStringAsFixed(1)}',
      );
    }
    buf
      ..writeln()
      ..writeln('TASK: Rank the 5 best replacements and suggest an optimal visit duration for each. Give strong consideration to places '
          'marked [BOOKMARKED BY USER] if they fit the purpose. Balance purpose, distance, '
          'and ratings. Never invent places; use only supplied placeIds.')
      ..writeln()
      ..writeln('Respond with compact JSON ONLY (no markdown, no extra '
          'text), max 5 items, best first:')
    // ✅ ASK FOR DURATION IN OUTPUT
      ..writeln('{"recommendations":[{"placeId":"...","score":94,'
          '"reason":"max 12 words","duration":60}]}');
    return buf.toString();
  }

  List<ChangeLocationRecommendation> _deterministicRanking(
      Place currentPlace,
      List<Place> candidates,
      Set<String> bookmarkedIds,
      ) {
    double score(Place p) {
      var s = 0.0;
      if (bookmarkedIds.contains(p.placeId)) s += 30;
      final curCat = currentPlace.placeCategory?.toLowerCase();
      final cat = p.placeCategory?.toLowerCase();
      if (curCat != null && cat != null && curCat == cat) s += 30;
      s += (p.placeRating / 5.0) * 30;
      final km = currentPlace.coordinates.distanceTo(p.coordinates);
      s += (1.0 - (km / 5).clamp(0.0, 1.0)) * 10;
      return s;
    }

    final sorted = List<Place>.from(candidates)..sort((a, b) => score(b).compareTo(score(a)));
    return sorted.take(5).map((p) {
      final km = currentPlace.coordinates.distanceTo(p.coordinates);
      final isBookmarked = bookmarkedIds.contains(p.placeId);
      return ChangeLocationRecommendation(
        place: p,
        aiScore: score(p).round().clamp(0, 100),
        reason: isBookmarked
            ? 'Saved in your bookmarks.'
            : catReason(p, currentPlace),
        distanceText: _distanceText(km),
        isBookmarked: isBookmarked,
        suggestedDuration: p.visitDurationMinutes ?? 90, // ✅ FALLBACK DURATION
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

  Future<List<ItineraryStop>?> _recalculateAffectedSchedule(
      Itinerary itinerary,
      List<ItineraryStop> resulting,
      int replacedIndex,
      ) async {
    final stops = List<ItineraryStop>.from(resulting)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

    // 1. If replaced stop has a predecessor, ensure it starts after predecessor ends + travel time
    if (replacedIndex > 0) {
      final prev = stops[replacedIndex - 1];
      final curr = stops[replacedIndex];
      int travel = curr.travelFromPrevMinutes ?? 15;
      if (prev.place != null && curr.place != null) {
        final routed = await _validator.travelMinutesBetween(
          prev.place!.coordinates,
          curr.place!.coordinates,
          itinerary.transportationMode,
        );
        if (routed != null) travel = routed;
      }

      final earliestStart = prev.endTime.add(Duration(minutes: travel));
      if (curr.startTime.isBefore(earliestStart)) {
        final newStart = earliestStart;
        final newEnd = newStart.add(Duration(minutes: curr.durationMinutes));
        stops[replacedIndex] = _copyWithTimes(curr, newStart, newEnd)
            .copyWith(travelFromPrevMinutes: travel);
      } else {
        stops[replacedIndex] = curr.copyWith(travelFromPrevMinutes: travel);
      }
    }

    var cursorEnd = stops[replacedIndex].endTime;
    for (var i = replacedIndex + 1; i < stops.length; i++) {
      final next = stops[i];
      int travel = next.travelFromPrevMinutes ?? 15;
      if (stops[i - 1].place != null && next.place != null) {
        final routed = await _validator.travelMinutesBetween(
          stops[i - 1].place!.coordinates,
          next.place!.coordinates,
          itinerary.transportationMode,
        );
        if (routed != null) travel = routed;
      }

      if (next.stopStatus == EditStopStatuses.completed) {
        if (next.startTime.isBefore(cursorEnd.add(Duration(minutes: travel)))) {
          return null;
        }
        cursorEnd = next.endTime;
        continue;
      }

      final earliest = cursorEnd.add(Duration(minutes: travel));
      if (next.startTime.isBefore(earliest)) {
        final shiftedStart = earliest;
        final shiftedEnd = shiftedStart.add(
            Duration(minutes: next.durationMinutes));
        stops[i] = _copyWithTimes(next, shiftedStart, shiftedEnd)
            .copyWith(travelFromPrevMinutes: travel);
        cursorEnd = shiftedEnd;
      } else {
        stops[i] = next.copyWith(travelFromPrevMinutes: travel);
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

  // ✅ UPDATED: Auto-calculates endTime and durationMinutes
  ItineraryStop _buildUpdatedStop(ItineraryStop stop, Place newPlace, int newDuration) {
    return ItineraryStop(
      stopId: stop.stopId,
      itineraryId: stop.itineraryId,
      placeId: newPlace.placeId,
      destinationId: stop.destinationId,
      dayIndex: stop.dayIndex,
      stopOrder: stop.stopOrder,
      startTime: stop.startTime,
      endTime: stop.startTime.add(Duration(minutes: newDuration)), // ✅ UPDATE END TIME
      durationMinutes: newDuration, // ✅ UPDATE DURATION
      travelFromPrevMinutes: stop.travelFromPrevMinutes,
      stopStatus: stop.stopStatus,
      skipReason: stop.skipReason,
      weatherNote: stop.weatherNote,
      place: newPlace,
      createdAt: stop.createdAt,
      updatedAt: DateTime.now(),
    );
  }


  Future<ItineraryStop?> _findStop(String itineraryId, int stopId) async {
    final all = await _stopRepo.getStopsForItinerary(itineraryId);
    final match = all.where((s) => s.stopId == stopId).toList();
    if (match.isEmpty) return null;
    final stop = match.first;
    Place? place = stop.place;
    place ??= await _placeRepo.getPlace(stop.placeId);
    return stop.copyWith(place: place);
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

class EditStopStatuses {
  static const String planned = 'PLANNED';
  static const String completed = 'COMPLETED';
  static const String skipped = 'SKIPPED';
}