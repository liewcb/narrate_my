// lib/model/business_logic/itinerary_service/itinerary_regeneration_service.dart
//
// Regeneration of an existing valid itinerary WITHOUT re-running the full
// generation pipeline.
//
// Flow:
//   Existing ItineraryResult (candidate pool + scored candidates + clusters)
//   â†’ identify unused / alternative candidates
//   â†’ keep must-visits + same traveler requirements
//   â†’ build regeneration prompt
//   â†’ DeepSeek
//   â†’ validate
//   â†’ retry (bounded)
//   â†’ update result only if valid (old itinerary preserved otherwise)

import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/services/ai_service.dart';
import '../../entities/place.dart';
import '../../entities/trip_draft.dart';
import '../../entities/weather.dart';
import 'ai_schedule_validator.dart';
import 'clustering_service.dart';
import 'generation_pipeline_service.dart';
import 'schedule_construction_service.dart';
import 'scoring_service.dart';

/// Service responsible for regenerating a valid itinerary from the existing
/// candidate knowledge (no Google Places re-run, no re-scoring, no re-K-Means).
class ItineraryRegenerationService {
  static const int maxRegenerationAttempts = 3;

  final AIService _aiService;
  final AiScheduleValidator _validator;

  ItineraryRegenerationService({
    AIService? aiService,
    AiScheduleValidator? validator,
  })  : _aiService = aiService ?? AIService(
    baiApiKey: ApiKeys.baiApiKey,
    baiModel: ApiKeys.baiModel,
    openRouterApiKey: ApiKeys.openRouterApiKey,
    cohereApiKey: ApiKeys.cohereApiKey,
  ),
        _validator = validator ?? AiScheduleValidator();

  /// Regenerate [current] using its own candidate pool + the traveler's
  /// original [request]. Returns the new result on success, or the original
  /// [current] unchanged when all attempts fail.
  Future<ItineraryResult> regenerate({
    required ItineraryResult current,
    required TripDraft request,
  }) async {
    debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
    debugPrint('ðŸ”„ REGENERATION START');
    debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
    debugPrint('[REGENERATE] Itinerary total days: ${request.totalDays}');
    debugPrint('[REGENERATE] Must-visits: ${request.mustVisitPlaceIds}');

    final usedIds = _usedPlaceIds(current);
    final alternatives = getAlternativeCandidates(
      current: current,
      request: request,
      usedIds: usedIds,
    );

    debugPrint('[REGENERATE] Existing candidates: '
        '${_totalCandidates(current)}');
    debugPrint('[REGENERATE] Currently used: ${usedIds.length}');
    debugPrint('[REGENERATE] Alternative candidates selected: '
        '${alternatives.length}');

    final mustVisitIds = request.mustVisitPlaceIds;

    for (int attempt = 1; attempt <= maxRegenerationAttempts; attempt++) {
      debugPrint('[REGENERATE] DeepSeek attempt $attempt');

      final prompt = _buildRegenerationPrompt(
        request: request,
        current: current,
        alternatives: alternatives,
        feedback: attempt > 1 ? _lastFeedback : null,
      );

      try {
        final raw = await _aiService.generateRawContent(prompt);
        debugPrint('[REGENERATE] AI response received (${raw.length} chars)');

        final List<AIDaySchedule> aiDays;
        try {
          aiDays = parseAiScheduleJson(raw);
        } catch (e) {
          debugPrint('[REGENERATE] JSON parse failed: $e');
          _lastFeedback = 'AI returned unparseable JSON: $e';
          continue;
        }

        debugPrint('[REGENERATE] Validation started');
        debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
        debugPrint('[REGENERATE VALIDATION INPUT]');
        debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
        final placeIdToDestination = _placeIdToDestination(current, request);
        final allocation = _allocationFor(request);
        for (final day in aiDays) {
          final expected = _expectedDayDestination(
            dayIndex: day.dayIndex,
            request: request,
            allocation: allocation,
          );
          debugPrint('Day ${day.dayIndex + 1}');
          debugPrint('destinationId = '
              '${_destinationIdForName(expected, request)}');
          debugPrint('destinationName = $expected');
          for (final stop in day.schedule) {
            final stopDest = placeIdToDestination[stop.placeId];
            final match = stopDest != null && stopDest == expected;
            debugPrint('Stop:');
            debugPrint('placeId = ${stop.placeId}');
            debugPrint('candidate.destinationId = '
                '${_destinationIdForName(stopDest, request)}');
            debugPrint('candidate.destinationName = $stopDest');
            debugPrint('Destination match = $match');
            if (!match) {
              debugPrint('[DESTINATION MISMATCH]');
              debugPrint('Day destination ID: '
                  '${_destinationIdForName(expected, request)}');
              debugPrint('Candidate destination ID: '
                  '${_destinationIdForName(stopDest, request)}');
              debugPrint('Day destination name: $expected');
              debugPrint('Candidate destination name: $stopDest');
            }
          }
        }
        debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');

        final validation = _validator.validate(
          days: aiDays,
          knownPlaceIds: _allCandidateIds(current),
          mustVisitIds: mustVisitIds,
          totalDays: request.totalDays,
          explorationTime: request.exploration ?? 'Standard',
          destinationOrder: request.destinationNames,
          allocatedDaysPerDestination:
          request.daySplit.isNotEmpty ? request.daySplit : null,
          placeIdToDestination: placeIdToDestination,
        );

        if (validation.passed) {
          debugPrint('[REGENERATE] Validation result: PASS');
          final updated = _toResult(
            current: current,
            aiDays: aiDays,
            request: request,
          );
          debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
          debugPrint('[REGENERATE VALIDATION SUMMARY]');
          debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
          debugPrint('Attempt: $attempt');
          debugPrint('Days: ${aiDays.length}');
          debugPrint('Candidates supplied: ${alternatives.length}');
          final generatedStops =
          aiDays.fold<int>(0, (sum, d) => sum + d.schedule.length);
          debugPrint('Stops generated: $generatedStops');
          debugPrint('Must-visits: ${_verifiedMustVisitCount(aiDays, mustVisitIds)} / '
              '${mustVisitIds.length}');
          debugPrint('Destination validation: PASS');
          debugPrint('Duplicate validation: PASS');
          debugPrint('Schedule validation: PASS');
          debugPrint('Travel validation: PASS');
          debugPrint('Overall: PASS');
          debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
          debugPrint('âœ… REGENERATION COMPLETE');
          debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
          return updated;
        }

        _lastFeedback = validation.feedbackText;
        debugPrint('[REGENERATE] Validation result: FAIL');
        debugPrint('[REGENERATE] Attempt $attempt FAILED');
        debugPrint('[REGENERATE] Reason: ${validation.issues.join('; ')}');
        debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
        debugPrint('[REGENERATE VALIDATION SUMMARY]');
        debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
        debugPrint('Attempt: $attempt');
        debugPrint('Days: ${aiDays.length}');
        debugPrint('Candidates supplied: ${alternatives.length}');
        final failedStops =
        aiDays.fold<int>(0, (sum, d) => sum + d.schedule.length);
        debugPrint('Stops generated: $failedStops');
        debugPrint('Must-visits: ${_verifiedMustVisitCount(aiDays, mustVisitIds)} / '
            '${mustVisitIds.length}');
        debugPrint('Destination validation: '
            '${_hasIssue(validation, 'destination_allocation') ? "FAIL" : "PASS"}');
        debugPrint('Duplicate validation: '
            '${_hasIssue(validation, 'duplicate_place') ? "FAIL" : "PASS"}');
        debugPrint('Schedule validation: '
            '${_hasIssue(validation, 'time_order') || _hasIssue(validation, 'window') ? "FAIL" : "PASS"}');
        debugPrint('Travel validation: '
            '${_hasIssue(validation, 'route_jump') ? "FAIL" : "PASS"}');
        debugPrint('Overall: FAIL');
        debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
      } catch (e) {
        debugPrint('[REGENERATE] Attempt $attempt error: $e');
        _lastFeedback = 'AI provider error: $e';
      }
    }

    debugPrint('[REGENERATE] All attempts failed â€” preserving previous '
        'valid itinerary.');
    debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
    debugPrint('âŒ REGENERATION FAILED (old itinerary kept)');
    debugPrint('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
    return current;
  }

  String? _lastFeedback;

  int _verifiedMustVisitCount(List<AIDaySchedule> aiDays, List<String> mustVisitIds) {
    final seen = <String>{};
    for (final day in aiDays) {
      for (final stop in day.schedule) {
        if (mustVisitIds.contains(stop.placeId)) seen.add(stop.placeId);
      }
    }
    return seen.length;
  }

  bool _hasIssue(AiValidationResult validation, String type) {
    return validation.issues.any((i) => i.type == type);
  }

  // ============================================================
  // ALTERNATIVE CANDIDATE SELECTION
  // ============================================================

  /// Identifies unused / alternative candidates from the existing pool.
  ///
  /// - Excludes places currently in the itinerary.
  /// - Keeps must-visits (they are never removed).
  /// - Falls back to the full pool when alternatives are scarce.
  List<Place> getAlternativeCandidates({
    required ItineraryResult current,
    required TripDraft request,
    required Set<String> usedIds,
  }) {
    final pool = current.candidatePool;
    if (pool == null) return const [];

    final mustVisitIds = request.mustVisitPlaceIds.toSet();
    final alternatives = <Place>[];

    for (final place in pool.all) {
      if (usedIds.contains(place.placeId)) continue;
      if (place.placeId.isEmpty) continue;
      alternatives.add(place);
    }

    // Ensure must-visits are present even if they were previously used.
    final mustVisitPlaces = pool.all
        .where((p) => mustVisitIds.contains(p.placeId))
        .toList();
    for (final mv in mustVisitPlaces) {
      if (!alternatives.any((a) => a.placeId == mv.placeId)) {
        alternatives.add(mv);
      }
    }

    if (alternatives.isEmpty) {
      // Not enough unused candidates â€” fall back to the full pool.
      return List.of(pool.all);
    }

    return alternatives;
  }

  // ============================================================
  // PROMPT BUILDING
  // ============================================================

  String _buildRegenerationPrompt({
    required TripDraft request,
    required ItineraryResult current,
    required List<Place> alternatives,
    String? feedback,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('You are planning an ALTERNATIVE version of an existing '
        'travel itinerary. Use ONLY the supplied candidates. Never invent '
        'places, place IDs, coordinates, opening hours, visit durations or '
        'travel times. Every scheduled place must come from the '
        'ALTERNATIVE CANDIDATES below.');
    buffer.writeln('');

    // â”€â”€ TRIP REQUIREMENTS (unchanged) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    buffer.writeln('TRIP REQUIREMENTS');
    buffer.writeln('Total days: ${request.totalDays}');
    if (request.startDate != null) {
      buffer.writeln('Start date: ${request.startDate!.toIso8601String().split('T').first}');
    }
    if (request.endDate != null) {
      buffer.writeln('End date: ${request.endDate!.toIso8601String().split('T').first}');
    }
    buffer.writeln('Destinations: ${request.destinationNames.join(', ')}');
    buffer.writeln('Exploration time: ${request.exploration ?? 'Standard'}');
    buffer.writeln('Travel pace (comfort preference, not a stop-count rule): '
        '${request.travelType ?? 'Standard'}');
    buffer.writeln('Transportation: ${request.transportation}');
    buffer.writeln('Traveler interests: ${request.interests.toList().join(', ')}');
    buffer.writeln('');

    // â”€â”€ MUST-VISITS (hard) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    buffer.writeln('MUST-VISITS (must appear exactly once â€” never removed)');
    final mustVisitIds = request.mustVisitPlaceIds.toSet();
    final mustVisits = alternatives
        .where((p) => mustVisitIds.contains(p.placeId))
        .toList();
    if (mustVisits.isEmpty) {
      buffer.writeln('- none');
    } else {
      for (final mv in mustVisits) {
        buffer.writeln('- ${mv.placeId} | ${mv.placeName} | '
            '${mv.destinationId ?? '?'}');
      }
    }
    buffer.writeln('');

    // â”€â”€ ALTERNATIVE CANDIDATES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    buffer.writeln('ALTERNATIVE CANDIDATES (select from these ONLY)');
    for (final place in alternatives) {
      final clusterId = _clusterIdForPlace(current, place.placeId);
      buffer.writeln(jsonEncode({
        'placeId': place.placeId,
        'name': place.placeName,
        'destinationId': place.destinationId,
        'category': place.category,
        'latitude': place.placeLatitude,
        'longitude': place.placeLongitude,
        'rating': place.placeRating,
        'isMustVisit': mustVisitIds.contains(place.placeId),
        'clusterId': clusterId,
        'visitDurationMinutes': place.visitDurationMinutes,
        'openingHours': place.openingHours?.toString(),
        'bestTimeSuggestion': place.bestTimeSuggestion,
      }));
    }
    buffer.writeln('');

    // â”€â”€ CURRENT ITINERARY (so the AI produces something different) â”€â”€
    buffer.writeln('CURRENT ITINERARY (previous plan â€” produce a DIFFERENT '
        'combination)');
    final days = current.scheduledDays;
    if (days != null && days.isNotEmpty) {
      for (final day in days) {
        final names = day.stops
            .map((s) => s.attraction.place.placeName)
            .join(' â†’ ');
        buffer.writeln('Day ${day.dayIndex + 1}: $names');
      }
    } else {
      buffer.writeln('- none');
    }
    buffer.writeln('');

    // â”€â”€ PLANNING GUIDANCE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    buffer.writeln('PLANNING GUIDANCE');
    buffer.writeln('- Produce a genuinely different but reasonable plan '
        'using the alternative candidates.');
    buffer.writeln('- Decide the number of stops per day from visit '
        'durations, travel proximity, opening hours and the exploration '
        'window. Do NOT force a fixed count.');
    buffer.writeln('- Keep activities inside the exploration window.');
    buffer.writeln('- Group places geographically for reasonable '
        'transitions.');
    buffer.writeln('- Do not reorder or duplicate places beyond what is '
        'reasonable.');
    buffer.writeln('');

    // â”€â”€ REGENERATION FEEDBACK (retry) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (feedback != null && feedback.trim().isNotEmpty) {
      buffer.writeln('PREVIOUS ATTEMPT WAS REJECTED. Fix ALL of these:');
      buffer.writeln(feedback);
      buffer.writeln('');
    }

    // â”€â”€ OUTPUT CONTRACT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    buffer.writeln('Return STRICT JSON ONLY (no Markdown fences) with this '
        'structure. Do NOT emit a "stopOrder" field â€” the array ordering IS '
        'the stop order and will be assigned by the system.');
    buffer.writeln(_jsonTemplate());

    return buffer.toString();
  }

  String _jsonTemplate() {
    return '''
{
  "days": [
    {
      "dayIndex": 0,
      "date": "YYYY-MM-DD",
      "schedule": [
        {
          "placeId": "EXACT_CANDIDATE_PLACE_ID",
          "startTime": "HH:mm",
          "endTime": "HH:mm",
          "visitDurationMinutes": 90,
          "travelFromPreviousMinutes": 15,
          "reason": "brief scheduling reason"
        }
      ]
    }
  ]
}
''';
  }

  // ============================================================
  // RESULT REBUILD
  // ============================================================

  /// Builds an updated [ItineraryResult] from a validated AI schedule,
  /// reusing the existing candidate pool / registry / clusters and
  /// incrementing the plan version.
  ItineraryResult _toResult({
    required ItineraryResult current,
    required List<AIDaySchedule> aiDays,
    required TripDraft request,
  }) {
    final scheduledDays = _toScheduledDays(aiDays, request, current);
    return ItineraryResult.success(
      scheduledDays: scheduledDays,
      weather: current.weather ?? WeatherForecast(daily: []),
      criticFeedback: current.criticFeedback ??
          CriticResult(
            overallSuitable: true,
            score: 0,
            issues: const [],
            recommendations: const [],
            summary: 'Regenerated itinerary.',
          ),
      warnings: current.warnings,
      candidatePool: current.candidatePool,
      placeRegistry: current.placeRegistry,
      scoredCandidates: current.scoredCandidates,
      clusters: current.clusters,
      unretrievableMustVisits: current.unretrievableMustVisits,
    );
  }

  List<ScheduledDay> _toScheduledDays(
      List<AIDaySchedule> aiDays,
      TripDraft request,
      ItineraryResult current,
      ) {
    final registry = current.placeRegistry;
    final startDate = request.startDate ?? DateTime.now();
    final result = <ScheduledDay>[];

    for (final day in aiDays) {
      final date = DateTime.tryParse(day.date) ??
          startDate.add(Duration(days: day.dayIndex));
      final stops = <ScheduledStop>[];

      for (final aiStop in day.schedule) {
        final place = registry?.byId(aiStop.placeId);
        if (place == null) continue;
        final scored = _scoredForPlace(current, place.placeId);

        stops.add(ScheduledStop(
          attraction: scored ??
              ScoredAttraction(place: place, score: 0, breakdown: const {}),
          startTime: _mergeTime(date, aiStop.startTime),
          endTime: _mergeTime(date, aiStop.endTime),
          durationMinutes: aiStop.visitDurationMinutes,
          travelFromPreviousMinutes: aiStop.travelFromPreviousMinutes,
          scheduleReason: aiStop.scheduleReason,
          weatherNote: '',
        ));
      }

      if (stops.isEmpty) continue;

      result.add(ScheduledDay(
        dayIndex: day.dayIndex,
        date: date,
        stops: stops,
        totalDuration: stops.fold<int>(0, (sum, s) => sum + s.durationMinutes),
        totalTravelTime: stops.fold<double>(
            0, (sum, s) => sum + s.travelFromPreviousMinutes),
      ));
    }

    return result;
  }

  ScoredAttraction? _scoredForPlace(ItineraryResult current, String placeId) {
    for (final s in current.scoredCandidates ?? const <ScoredAttraction>[]) {
      if (s.place.placeId == placeId) return s;
    }
    return null;
  }

  DateTime _mergeTime(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 9;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Set<String> _usedPlaceIds(ItineraryResult current) {
    final ids = <String>{};
    for (final day in current.scheduledDays ?? const <ScheduledDay>[]) {
      for (final stop in day.stops) {
        ids.add(stop.attraction.place.placeId);
      }
    }
    return ids;
  }

  int _totalCandidates(ItineraryResult current) {
    return current.candidatePool?.totalCount ?? 0;
  }

  Set<String> _allCandidateIds(ItineraryResult current) {
    final ids = <String>{};
    final pool = current.candidatePool;
    if (pool != null) {
      ids.addAll(pool.all.map((p) => p.placeId));
    }
    final registry = current.placeRegistry;
    if (registry != null) {
      ids.addAll(registry.placeIds);
    }
    return ids;
  }

  int? _clusterIdForPlace(ItineraryResult current, String placeId) {
    for (final cluster in current.clusters ?? const <Cluster>[]) {
      for (final a in cluster.attractions) {
        if (a.place.placeId == placeId) return cluster.dayIndex;
      }
    }
    return null;
  }

  Map<String, String> _placeIdToDestination(
      ItineraryResult current,
      TripDraft request,
      ) {
    // The validator compares against allocatedDaysPerDestination keys
    // which are destination NAMES (e.g. "Kuala Lumpur"), not IDs.
    // We must return the matching name, not the DB ID.
    final result = <String, String>{};
    for (final s in current.scoredCandidates ?? const <ScoredAttraction>[]) {
      final destName = _destinationNameForPlace(request, s.place);
      if (destName != null) {
        result[s.place.placeId] = destName;
      }
    }
    return result;
  }

  /// Returns the destination NAME for a place by matching its coordinates
  /// against the request's destinationCoordinates (same logic as the main
  /// pipeline).  Falls back to the destination name list / ID when no
  /// coordinate match is found.
  String? _destinationNameForPlace(TripDraft request, Place place) {
    final coords = place.coordinates;
    String? best;
    double bestDistance = double.infinity;
    for (final entry in request.destinationCoordinates.entries) {
      final d = coords.distanceTo(entry.value);
      if (d < bestDistance) {
        bestDistance = d;
        best = entry.key;
      }
    }
    if (best != null) return best;
    if (request.destinationNames.isNotEmpty) return request.destinationNames.first;
    return place.destinationId;
  }

  /// Expected destination NAME for a day, derived from the sequential fill.
  String _expectedDayDestination({
    required int dayIndex,
    required TripDraft request,
    Map<String, int>? allocation,
  }) {
    final alloc = allocation ?? _allocationFor(request);
    final names = request.destinationNames;
    var counter = 0;
    for (final name in names) {
      final days = alloc[name] ?? 1;
      for (int d = 0; d < days; d++) {
        if (counter == dayIndex) return name;
        counter++;
      }
    }
    return names.isNotEmpty ? names.first : 'Unknown';
  }

  /// Map a destination NAME to its DB ID (best-effort). Used only for
  /// debug logging â€” the authoritative comparison is by name.
  String? _destinationIdForName(String? name, TripDraft request) {
    if (name == null) return null;
    // Destination names in the request map to themselves for display.
    return name;
  }

  /// Day-per-destination allocation (names as keys, matching the prompt).
  Map<String, int> _allocationFor(TripDraft request) {
    if (request.daySplit.isNotEmpty) return Map.of(request.daySplit);
    if (request.destinationNames.isEmpty || request.totalDays <= 0) {
      return const {};
    }
    final base = request.totalDays ~/ request.destinationNames.length;
    final extra = request.totalDays % request.destinationNames.length;
    final split = <String, int>{};
    for (int i = 0; i < request.destinationNames.length; i++) {
      split[request.destinationNames[i]] = base + (i < extra ? 1 : 0);
    }
    return split;
  }
}