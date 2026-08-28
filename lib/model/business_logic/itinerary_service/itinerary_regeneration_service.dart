// lib/model/business_logic/itinerary_service/itinerary_regeneration_service.dart
//
// Regeneration of an existing valid itinerary WITHOUT re-running the full
// generation pipeline.
//
// Flow:
//   Existing ItineraryResult (candidate pool + scored candidates + clusters)
//   → identify unused / alternative candidates
//   → keep must-visits + same traveler requirements
//   → build regeneration prompt
//   → DeepSeek
//   → validate
//   → retry (bounded)
//   → update result only if valid (old itinerary preserved otherwise)

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
    debugPrint('════════════════════════════════════');
    debugPrint('🔄 REGENERATION START');
    debugPrint('════════════════════════════════════');
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
    final scored = current.scoredCandidates ?? const [];

    for (int attempt = 1; attempt <= maxRegenerationAttempts; attempt++) {
      debugPrint('[REGENERATE] DeepSeek attempt $attempt');

      final prompt = _buildRegenerationPrompt(
        request: request,
        current: current,
        alternatives: alternatives,
        scored: scored,
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
        final validation = _validator.validate(
          days: aiDays,
          knownPlaceIds: _allCandidateIds(current),
          mustVisitIds: mustVisitIds,
          totalDays: request.totalDays,
          explorationTime: request.explorationTime ?? 'Standard',
          destinationOrder: request.destinations,
          allocatedDaysPerDestination:
              request.daySplit.isNotEmpty ? request.daySplit : null,
          placeIdToDestination: _placeIdToDestination(current),
        );

        if (validation.passed) {
          debugPrint('[REGENERATE] Validation result: PASS');
          final updated = _toResult(
            current: current,
            aiDays: aiDays,
            request: request,
          );
          debugPrint('[REGENERATE] State updated (version +1)');
          debugPrint('════════════════════════════════════');
          debugPrint('✅ REGENERATION COMPLETE');
          debugPrint('════════════════════════════════════');
          return updated;
        }

        _lastFeedback = validation.feedbackText;
        debugPrint('[REGENERATE] Validation result: FAIL');
        debugPrint('[REGENERATE] Attempt $attempt FAILED');
        debugPrint('[REGENERATE] Reason: ${validation.issues.join('; ')}');
      } catch (e) {
        debugPrint('[REGENERATE] Attempt $attempt error: $e');
        _lastFeedback = 'AI provider error: $e';
      }
    }

    debugPrint('[REGENERATE] All attempts failed — preserving previous '
        'valid itinerary.');
    debugPrint('════════════════════════════════════');
    debugPrint('❌ REGENERATION FAILED (old itinerary kept)');
    debugPrint('════════════════════════════════════');
    return current;
  }

  String? _lastFeedback;

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
      // Not enough unused candidates — fall back to the full pool.
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
    required List<ScoredAttraction> scored,
    String? feedback,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('You are planning an ALTERNATIVE version of an existing '
        'travel itinerary. Use ONLY the supplied candidates. Never invent '
        'places, place IDs, coordinates, opening hours, visit durations or '
        'travel times. Every scheduled place must come from the '
        'ALTERNATIVE CANDIDATES below.');
    buffer.writeln('');

    // ── TRIP REQUIREMENTS (unchanged) ───────────────────────────
    buffer.writeln('TRIP REQUIREMENTS');
    buffer.writeln('Total days: ${request.totalDays}');
    if (request.startDate != null) {
      buffer.writeln('Start date: ${request.startDate!.toIso8601String().split('T').first}');
    }
    if (request.endDate != null) {
      buffer.writeln('End date: ${request.endDate!.toIso8601String().split('T').first}');
    }
    buffer.writeln('Destinations: ${request.destinations.join(', ')}');
    buffer.writeln('Exploration time: ${request.explorationTime ?? 'Standard'}');
    buffer.writeln('Travel pace (comfort preference, not a stop-count rule): '
        '${request.travelPace ?? 'Standard'}');
    buffer.writeln('Transportation: ${request.transportation}');
    buffer.writeln('Traveler interests: ${request.interests.join(', ')}');
    buffer.writeln('');

    // ── MUST-VISITS (hard) ──────────────────────────────────────
    buffer.writeln('MUST-VISITS (must appear exactly once — never removed)');
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

    // ── ALTERNATIVE CANDIDATES ─────────────────────────────────
    buffer.writeln('ALTERNATIVE CANDIDATES (select from these ONLY)');
    final scoredById = <String, ScoredAttraction>{
      for (final s in scored) s.place.placeId: s,
    };
    for (final place in alternatives) {
      final s = scoredById[place.placeId];
      final clusterId = _clusterIdForPlace(current, place.placeId);
      buffer.writeln(jsonEncode({
        'placeId': place.placeId,
        'name': place.placeName,
        'destinationId': place.destinationId,
        'category': place.category,
        'types': place.placeTypes,
        'latitude': place.placeLatitude,
        'longitude': place.placeLongitude,
        'rating': place.placeRating,
        'finalScore': s?.score,
        'interestScore': s?.breakdown['interest'],
        'isMustVisit': mustVisitIds.contains(place.placeId),
        'clusterId': clusterId,
        'visitDurationMinutes': place.visitDurationMinutes,
        'openingHours': place.openingHours?.toString(),
        'bestTimeSuggestion': place.bestTimeSuggestion,
      }));
    }
    buffer.writeln('');

    // ── CURRENT ITINERARY (so the AI produces something different) ──
    buffer.writeln('CURRENT ITINERARY (previous plan — produce a DIFFERENT '
        'combination)');
    final days = current.scheduledDays;
    if (days != null && days.isNotEmpty) {
      for (final day in days) {
        final names = day.stops
            .map((s) => s.attraction.place.placeName)
            .join(' → ');
        buffer.writeln('Day ${day.dayIndex + 1}: $names');
      }
    } else {
      buffer.writeln('- none');
    }
    buffer.writeln('');

    // ── PLANNING GUIDANCE ───────────────────────────────────────
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

    // ── REGENERATION FEEDBACK (retry) ───────────────────────────
    if (feedback != null && feedback.trim().isNotEmpty) {
      buffer.writeln('PREVIOUS ATTEMPT WAS REJECTED. Fix ALL of these:');
      buffer.writeln(feedback);
      buffer.writeln('');
    }

    // ── OUTPUT CONTRACT ─────────────────────────────────────────
    buffer.writeln('Return STRICT JSON ONLY (no Markdown fences) with this '
        'structure:');
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
          "stopOrder": 1,
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

  Map<String, String> _placeIdToDestination(ItineraryResult current) {
    final result = <String, String>{};
    for (final s in current.scoredCandidates ?? const <ScoredAttraction>[]) {
      final destId = s.place.destinationId;
      if (destId != null && destId.isNotEmpty) {
        result[s.place.placeId] = destId;
      }
    }
    return result;
  }
}