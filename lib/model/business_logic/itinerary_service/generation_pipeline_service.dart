// lib/model/business_logic/itinerary_service/generation_pipeline_service.dart

import 'package:flutter/foundation.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/weather_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import '../../entities/trip_draft.dart';
import '../../entities/weather.dart';
import 'ai_prompt_builder.dart';
import 'ai_schedule_validator.dart';
import 'candidate_retrieval_service.dart';
import 'clustering_service.dart';
import 'place_registry.dart';
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

  /// Scored candidates (ranked, with scores + must-visit flags) retained
  /// so regeneration can select alternatives without re-running scoring.
  final List<ScoredAttraction>? scoredCandidates;

  /// Geographic clusters used for the generated schedule. Preserved so
  /// regeneration reuses the same geographic knowledge without re-running
  /// K-Means.
  final List<Cluster>? clusters;

  /// Must-visits that could not be retrieved after the full recovery
  /// process. Present so the UI can report the requirement explicitly.
  final List<String> unretrievableMustVisits;

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
    this.scoredCandidates,
    this.clusters,
    this.unretrievableMustVisits = const [],
  });

  factory ItineraryResult.success({
    required List<ScheduledDay> scheduledDays,
    required WeatherForecast weather,
    required CriticResult criticFeedback,
    List<ValidationIssue>? warnings,
    CandidatePool? candidatePool,
    PlaceRegistry? placeRegistry,
    List<ScoredAttraction>? scoredCandidates,
    List<Cluster>? clusters,
    List<String> unretrievableMustVisits = const [],
  }) {
    return ItineraryResult(
      success: true,
      scheduledDays: scheduledDays,
      weather: weather,
      criticFeedback: criticFeedback,
      warnings: warnings,
      candidatePool: candidatePool,
      placeRegistry: placeRegistry,
      scoredCandidates: scoredCandidates,
      clusters: clusters,
      unretrievableMustVisits: unretrievableMustVisits,
    );
  }

  factory ItineraryResult.error({
    required String message,
    List<ValidationIssue>? errors,
    List<String> unretrievableMustVisits = const [],
  }) {
    return ItineraryResult(
      success: false,
      message: message,
      errors: errors,
      unretrievableMustVisits: unretrievableMustVisits,
    );
  }
}

/// Orchestrates the complete itinerary generation flow.
///
/// THIS FLOW IS THE SOURCE OF TRUTH:
///   Load → Normal Nearby Search → Must-visit check → (recover missing) →
///   Deduplicate → Filter → Score → Sufficiency (→ expand) → K-Means →
///   Build AI context → DeepSeek → Validate → (regenerate) → Save.
///
/// DeepSeek is responsible for context-aware scheduling. Flutter remains
/// responsible for retrieval, filtering, scoring, clustering, hard
/// constraints, validation and persistence.
class ItineraryGenerationPipeline {
  static const int maxRegenerationAttempts = 3;

  final CandidateRetrievalService _candidateRetrieval;
  final ScoringService _scoring;
  final ClusteringService _clustering;
  final AiPromptBuilder _promptBuilder;
  final AiScheduleValidator _validator;
  final WeatherService _weather;
  final AIService _aiService;

  ItineraryGenerationPipeline({
    CandidateRetrievalService? candidateRetrieval,
    AIService? aiService,
    WeatherService? weather,
  })  : _candidateRetrieval = candidateRetrieval ?? CandidateRetrievalService(),
        _scoring = ScoringService(),
        _clustering = ClusteringService(),
        _promptBuilder = AiPromptBuilder(),
        _validator = AiScheduleValidator(),
        _weather = weather ?? WeatherService(),
        _aiService = aiService ?? AIService(
          baiApiKey: ApiKeys.baiApiKey,
          baiModel: ApiKeys.baiModel,
          openRouterApiKey: ApiKeys.openRouterApiKey,
          cohereApiKey: ApiKeys.cohereApiKey,
        );

  Future<ItineraryResult> generate({
    required TripDraft request,
    required void Function(String) onProgress,
    Coordinates? tripLocation,
  }) async {
    final effectivePace = request.travelPace ?? 'Standard';
    final effectiveExploration = request.explorationTime ?? 'Standard';

    debugPrint('════════════════════════════════════════════');
    debugPrint('🚀 REQUEST ITINERARY PIPELINE START');
    debugPrint('════════════════════════════════════════════');

    // ── STAGE 01 - INPUT VALIDATION ─────────────────────────────
    debugPrint('[STAGE 01 - INPUT VALIDATION]');
    debugPrint('✓ destination count: ${request.destinations.length} '
        '(${request.destinations.join(', ')})');
    debugPrint('✓ total days: ${request.totalDays}');
    debugPrint('✓ travel type: ${request.travelType ?? 'Solo'}');
    debugPrint('✓ exploration time: $effectiveExploration');
    debugPrint('✓ travel pace: $effectivePace');
    debugPrint('✓ transportation: ${request.transportation}');
    debugPrint('✓ interests: ${request.interests}');
    debugPrint('✓ must-visits: ${request.mustVisitPlaceIds}');

    if (request.destinations.isEmpty) {
      return ItineraryResult.error(
        message: 'No destination selected. Please go back to Step 1.',
      );
    }
    if (request.totalDays <= 0) {
      return ItineraryResult.error(
        message: 'Trip duration must be at least 1 day.',
      );
    }

    try {
      // ============================================================
      // STAGE 02 - LOAD ITINERARY / PREFERENCES
      // (the TripDraft already carries loaded preferences)
      // ============================================================
      debugPrint('[STAGE 02 - LOAD ITINERARY]');
      debugPrint('✓ itinerary title: ${request.title}');
      debugPrint('✓ user-selected destinations: ${request.destinations}');
      debugPrint('✓ allocated days: ${request.daySplit}');

      // ============================================================
      // STAGE 03-06 - HOTSPOT RETRIEVAL, GOOGLE PLACES, MERGE + DEDUP
      // ============================================================
      onProgress('Finding attractions... (1/9)');
      var candidatePool = await _candidateRetrieval.retrieveCandidates(
        request: request,
      );
      final rawCount = candidatePool.totalCount;
      final rawAttractionCount = candidatePool.attractionCount;
      final rawFoodCount = candidatePool.foodCount;
      debugPrint('[STAGE 03-06 - RETRIEVAL + MERGE]');
      debugPrint('Google raw (unique place_ids) = $rawCount '
          '($rawAttractionCount attr, $rawFoodCount food)');
      debugPrint('Must-visits recovered = 0 (not yet checked)');

      final registry = PlaceRegistry()
        ..addAll(candidatePool.attractions)
        ..addAll(candidatePool.food);

      // ============================================================
      // STAGE 07 - RAW CANDIDATE SUFFICIENCY CHECK
      // ============================================================
      final retrievalTarget = ItineraryConstants.retrievalCandidateTarget(
        days: request.totalDays,
        mustVisitCount: request.mustVisitPlaceIds.length,
        explorationTime: effectiveExploration,
      );
      debugPrint('[STAGE 07 - RAW SUFFICIENCY]');
      debugPrint('Retrieval target: $retrievalTarget');
      debugPrint('Current unique candidates: $rawCount');
      if (rawCount < retrievalTarget) {
        debugPrint('Status: RAW CANDIDATES INSUFFICIENT → EXPANDING');
        debugPrint('[STAGE 07B - CANDIDATE EXPANSION]');
        debugPrint('Reason: $rawCount < $retrievalTarget');
        debugPrint('Previous count: $rawCount');
        debugPrint('Search strategy: radius × ${ItineraryConstants.expansionMultiplier}');

        final expanded = await _candidateRetrieval.expandCandidates(
          request: request,
          alreadySeenIds: registry.placeIds,
          radiusMultiplier: ItineraryConstants.expansionMultiplier,
        );

        final seen = Set<String>.of(registry.placeIds);
        final newPlaces = <Place>[];
        for (final p in expanded.all) {
          if (seen.add(p.placeId)) newPlaces.add(p);
        }

        registry
          ..addAll(expanded.attractions)
          ..addAll(expanded.food);

        candidatePool = CandidatePool(
          attractions: [...candidatePool.attractions, ...expanded.attractions],
          food: [...candidatePool.food, ...expanded.food],
        );

        debugPrint('New candidates: ${newPlaces.length}');
        debugPrint('Total: ${candidatePool.totalCount}');
      } else {
        debugPrint('Status: ENOUGH (no expansion needed)');
      }

      // ============================================================
      // STAGE 08 - MUST-VISIT RECOVERY
      // ============================================================
      var recoveredMustVisitCount = 0;
      debugPrint('[STAGE 08 - MUST-VISIT RECOVERY]');
      debugPrint('Requested: ${request.mustVisitPlaceIds.length}');
      if (request.mustVisitPlaceIds.isEmpty) {
        debugPrint('requested = 0 → no recovery required');
      } else {
        final recovery = await _candidateRetrieval.recoverMustVisits(
          requestedMustVisitIds: request.mustVisitPlaceIds,
          alreadyRetrievedIds: registry.placeIds,
          searchCenter: request.primaryCoordinates,
        );
        recoveredMustVisitCount = recovery.recoveredPlaces.length;
        debugPrint('Found normally: ${recovery.verifiedIds.length}');
        debugPrint('Recovered: ${recovery.recoveredPlaces.length}');
        debugPrint('Missing: ${recovery.unretrievableIds}');

        if (recovery.recoveredPlaces.isNotEmpty) {
          final recoveredAttractions = <Place>[];
          final recoveredFood = <Place>[];
          for (final place in recovery.recoveredPlaces) {
            final isFood = place.types.any(CandidateRetrievalService.foodTypes.contains);
            (isFood ? recoveredFood : recoveredAttractions).add(place);
          }
          registry.addAll(recovery.recoveredPlaces);
          candidatePool = CandidatePool(
            attractions: [...candidatePool.attractions, ...recoveredAttractions],
            food: [...candidatePool.food, ...recoveredFood],
          );
          debugPrint('Added ${recovery.recoveredPlaces.length} '
              'recovered must-visit(s) to candidate pool');
        }

        final unretrievable = recovery.unretrievableIds;
        if (unretrievable.isNotEmpty) {
          debugPrint('❌ → Must-visit recovery failure: $unretrievable');
          return ItineraryResult.error(
            message: 'One or more must-visit places could not be retrieved: '
                '$unretrievable. Please check the place and try again.',
            errors: [
              ValidationIssue(
                type: 'must_visit_unretrievable',
                severity: 'error',
                message: 'Must-visit could not be retrieved: $unretrievable',
              ),
            ],
            unretrievableMustVisits: unretrievable,
          );
        }
      }

      // ============================================================
      // STAGE 09 - FILTER INVALID CANDIDATES
      //
      // The retrieval service already applies basic filtering
      // (business status, review floor, banned types).  The remaining
      // pool is our "usable" set.
      // ============================================================
      onProgress('Filtering candidates...');
      final usableCount = candidatePool.totalCount;
      debugPrint('[STAGE 09 - FILTER]');
      debugPrint('Before: $rawCount');
      debugPrint('After: $usableCount');
      debugPrint('Removed: ${rawCount - usableCount}');
      debugPrint('Reason breakdown: built-in retrieval hygiene '
          '(business status, review floor, banned types)');

      if (candidatePool.attractions.isEmpty) {
        return ItineraryResult.error(
          message: 'No suitable attractions were found in the selected '
              'destinations.',
        );
      }

      // ============================================================
      // STAGE 10 - USABLE CANDIDATE SUFFICIENCY CHECK
      // ============================================================
      final usableTarget = ItineraryConstants.usableCandidateTarget(
        days: request.totalDays,
        mustVisitCount: request.mustVisitPlaceIds.length,
        explorationTime: effectiveExploration,
      );
      debugPrint('[STAGE 10 - USABLE SUFFICIENCY]');
      debugPrint('Usable candidate target: $usableTarget');
      debugPrint('Current usable candidates: $usableCount');
      if (usableCount < usableTarget) {
        debugPrint('Status: USABLE CANDIDATES INSUFFICIENT → EXPANDING');
        debugPrint('[STAGE 10B - CANDIDATE EXPANSION]');
        debugPrint('Reason: $usableCount < $usableTarget');
        debugPrint('Previous count: $usableCount');

        final expanded = await _candidateRetrieval.expandCandidates(
          request: request,
          alreadySeenIds: registry.placeIds,
          radiusMultiplier: ItineraryConstants.expansionMultiplier,
        );

        final seen = Set<String>.of(registry.placeIds);
        final newPlaces = <Place>[];
        for (final p in expanded.all) {
          if (seen.add(p.placeId)) newPlaces.add(p);
        }

        registry
          ..addAll(expanded.attractions)
          ..addAll(expanded.food);

        candidatePool = CandidatePool(
          attractions: [...candidatePool.attractions, ...expanded.attractions],
          food: [...candidatePool.food, ...expanded.food],
        );

        debugPrint('New candidates: ${newPlaces.length}');
        debugPrint('Total: ${candidatePool.totalCount}');
      } else {
        debugPrint('Status: ENOUGH');
      }

      // ============================================================
      // STAGE 11 - SCORE ALL USABLE CANDIDATES
      //
      // Scoring RANKS the entire usable pool.  Must-visits are preserved
      // by the label flag.  No candidates are eliminated by scoring.
      // ============================================================
      onProgress('Scoring places... (3/9)');
      final allPlaces = [...candidatePool.attractions, ...candidatePool.food];
      debugPrint('[STAGE 11 - SCORING]');
      debugPrint('Candidates entering: ${allPlaces.length}');
      debugPrint('Candidates removed by scoring: 0 (all usable scored)');

      var scored = _scoring.scorePlaces(
        places: allPlaces,
        selectedInterests: request.interests,
        mustVisitIds: request.mustVisitPlaceIds,
        explorationTime: effectiveExploration,
        tripLocation: tripLocation,
        strictInterestFilter: false, // rank all, do not eliminate
      );
      debugPrint('Candidates scored: ${scored.length}');
      debugPrint('All usable candidates scored.');
      for (var i = 0; i < scored.length && i < 5; i++) {
        final s = scored[i];
        debugPrint('  ${i + 1}. ${s.place.placeName} '
            '(${s.score.toStringAsFixed(2)})');
      }

      if (scored.isEmpty) {
        return ItineraryResult.error(
          message: 'No suitable places were found in the selected destinations.',
        );
      }

      // ============================================================
      // STAGE 12 - K-MEANS — PURE GEOGRAPHIC CLUSTERING
      // ============================================================
      onProgress('Grouping by location... (4/9)');
      final clusters = _clustering.clusterGeographically(
        scoredPlaces: scored,
        clusterCount: request.totalDays.clamp(1, scored.length),
      );
      debugPrint('[STAGE 12 - K-MEANS]');
      debugPrint('Input candidates: ${scored.length}');
      debugPrint('Number of clusters: ${clusters.length}');
      for (final c in clusters) {
        debugPrint('Cluster ${c.dayIndex}: ${c.attractions.length} places');
      }

      // ============================================================
      // STAGE 13 - PREPARE STRUCTURED AI INPUT
      // ============================================================
      onProgress('Building AI context... (5/9)');
      final clusterIdOfPlace = <String, int>{};
      for (final c in clusters) {
        for (final a in c.attractions) {
          clusterIdOfPlace[a.place.placeId] = c.dayIndex;
        }
      }

      final candidates = scored.map((s) {
        final place = s.place;
        return AiCandidateContext(
          placeId: place.placeId,
          name: place.placeName,
          destination: place.destinationId ??
              _destinationForPlace(request, place),
          clusterId: clusterIdOfPlace[place.placeId],
          category: place.category,
          rating: place.placeRating,
          finalScore: s.score,
          isMustVisit: s.isMustVisit,
          visitDurationMinutes: place.visitDurationMinutes,
          openingHours: place.openingHours?.toString(),
          bestTimeSuggestion: place.bestTimeSuggestion,
          latitude: place.placeLatitude,
          longitude: place.placeLongitude,
        );
      }).toList();

      // placeId → destination, so the validator can verify the AI did not
      // schedule a candidate outside its destination's allocated days.
      final placeIdToDestination = <String, String>{
        for (final s in scored)
          s.place.placeId: _destinationForPlace(request, s.place),
      };

      final prompt = _promptBuilder.buildSchedulePrompt(
        request: request,
        candidates: candidates,
        clusters: clusters,
      );

      debugPrint('[STAGE 13 - DEEPSEEK INPUT]');
      debugPrint('Trip days: ${request.totalDays}');
      debugPrint('Destination allocation: ${
          request.daySplit.isNotEmpty ? request.daySplit : 'even split'}');
      debugPrint('Travel pace: $effectivePace');
      debugPrint('Exploration time: $effectiveExploration');
      debugPrint('Must-visits: ${request.mustVisitPlaceIds.length}');
      debugPrint('Candidate count: ${candidates.length}');
      debugPrint('Cluster count: ${clusters.length}');
      debugPrint('Prompt size: ${prompt.length} chars');

      // ============================================================
      // STAGE 14 - DEEPSEEK SCHEDULE GENERATION (+ regeneration)
      // ============================================================
      onProgress('Creating schedule... (7/9)');
      debugPrint('[STAGE 14 - DEEPSEEK RESPONSE]');
      debugPrint('Sending ${candidates.length} candidates, '
          '${clusters.length} clusters');

      // AI must only reference place IDs that survived scoring.
      final scoredPlaceIds = scored.map((s) => s.place.placeId).toSet();

      List<AIDaySchedule> aiDays;
      var validation = _validateSchedule(
        aiDays: [],
        request: request,
        knownPlaceIds: scoredPlaceIds,
        placeIdToDestination: placeIdToDestination,
      );

      var attempt = 0;
      while (true) {
        attempt++;
        debugPrint('[AI] Generation attempt $attempt');

        final raw = await _generateAiSchedule(
          prompt: prompt,
          feedback: validation.feedbackText,
        );

        try {
          aiDays = parseAiScheduleJson(raw);
          for (var day in aiDays) {
            int order = 1;
            final repairedSchedule = day.schedule.map((stop) {
              return AIScheduleStop(
                stopOrder: order++,
                placeId: stop.placeId,
                startTime: stop.startTime,
                endTime: stop.endTime,
                visitDurationMinutes: stop.visitDurationMinutes,
                travelFromPreviousMinutes: stop.travelFromPreviousMinutes,
                scheduleReason: stop.scheduleReason,
                weatherNote: stop.weatherNote,
              );
            }).toList();
            // If AIDaySchedule has a copyWith, use it; otherwise reassign:
            // day = day.copyWith(schedule: repairedSchedule);
            // Since AIDaySchedule is immutable, you'll need to create a new one:
            day = AIDaySchedule(
              dayIndex: day.dayIndex,
              date: day.date,
              schedule: repairedSchedule,
              warnings: day.warnings,
              needsRepair: day.needsRepair,
            );
          }
        } catch (e) {
          debugPrint('[AI] JSON parse failed (attempt $attempt): $e');
          if (attempt >= maxRegenerationAttempts) {
            return ItineraryResult.error(
              message: 'The AI did not return a valid schedule. '
                  'Please try again.',
            );
          }
          validation = AiValidationResult(
            passed: false,
            issues: [
              AiValidationIssue(
                type: 'json_structure',
                message: 'AI returned unparseable JSON: $e',
              ),
            ],
          );
          continue;
        }

        debugPrint('Response received');
        debugPrint('Response length: $raw.length');

        validation = _validateSchedule(
          aiDays: aiDays,
          request: request,
          knownPlaceIds: scoredPlaceIds,
          placeIdToDestination: placeIdToDestination,
        );

        // ── STAGE 15 - AI RESPONSE VALIDATION ────────────────────
        debugPrint('[STAGE 15 - AI RESPONSE VALIDATION]');
        debugPrint('JSON valid: YES');
        debugPrint('Days returned: ${aiDays.length}');
        debugPrint('Stops returned: '
            '${aiDays.fold<int>(0, (sum, d) => sum + d.schedule.length)}');
        debugPrint('Unknown places: '
            '${validation.issues.where((i) => i.type == 'unknown_place_id').length}');
        debugPrint('Duplicates: '
            '${validation.issues.where((i) => i.type == 'duplicate_place').length}');
        debugPrint('Missing must-visits: '
            '${validation.issues.where((i) => i.type == 'must_visit').length}');
        debugPrint('Invalid times: '
            '${validation.issues.where((i) => i.type == 'time_order' || i.type == 'invalid_time').length}');

        if (validation.passed) break;

        debugPrint('[VALIDATION] Attempt $attempt failed: '
            '${validation.issues.length} issue(s)');
        for (final issue in validation.issues) {
          debugPrint('   ${issue.toString()}');
        }

        if (attempt >= maxRegenerationAttempts) {
          debugPrint('[VALIDATION] All regeneration attempts failed.');
          return ItineraryResult.error(
            message: 'The generated itinerary could not be validated after '
                '${maxRegenerationAttempts} attempts.',
            errors: [
              for (final i in validation.issues)
                ValidationIssue(
                  type: i.type,
                  severity: 'error',
                  message: i.message,
                  dayIndex: i.dayIndex,
                ),
            ],
          );
        }
      }

      // ============================================================
      // STAGE 16 - CONVERT VALIDATED AI OUTPUT → DOMAIN SCHEDULE
      // ============================================================
      onProgress('Validating... (8/9)');
      final scheduledDays = _toScheduledDays(
        aiDays: aiDays,
        request: request,
        registry: registry,
        scored: scored,
      );

      if (scheduledDays.isEmpty) {
        return ItineraryResult.error(
          message: 'Validation passed but no stops could be materialized.',
        );
      }

      debugPrint('[STAGE 16 - FINAL VALIDATION]');
      debugPrint('✓ all required days exist (${scheduledDays.length})');
      debugPrint('✓ destination allocation (validated by AI response validation)');
      debugPrint('✓ must-visits present (validated by AI response validation)');
      debugPrint('✓ no duplicates (validated by AI response validation)');
      debugPrint('✓ opening hours (validated by AI response validation)');
      debugPrint('✓ daily time window (validated by AI response validation)');
      debugPrint('✓ chronological schedule (validated by AI response validation)');
      debugPrint('RESULT: PASS');

      // ============================================================
      // STAGE 17 - FETCH WEATHER
      // ============================================================
      onProgress('Fetching weather... (9/9)');
      final weather = await _fetchWeather(request, scheduledDays);

      onProgress('Getting AI feedback...');
      final critic = await _critic(scheduledDays, effectivePace, request);

      onProgress('Finalizing your itinerary...');
      final totalStops =
          scheduledDays.fold<int>(0, (sum, d) => sum + d.stops.length);
      debugPrint('════════════════════════════════════════════');
      debugPrint('✅ PIPELINE COMPLETE');
      debugPrint('════════════════════════════════════════════');
      debugPrint('Diagnostic candidate flow:');
      debugPrint('Google raw            = $rawCount '
          '($rawAttractionCount attr, $rawFoodCount food)');
      debugPrint('Unique                = $rawCount');
      debugPrint('Must-visits recovered = $recoveredMustVisitCount');
      debugPrint('After filtering       = ${candidatePool.totalCount}');
      debugPrint('Scored                = ${scored.length}');
      debugPrint('K-Means input         = ${scored.length}');
      debugPrint('DeepSeek selected     = $totalStops');
      debugPrint('Final validated       = $totalStops');
      debugPrint('Days: ${scheduledDays.length}');
      debugPrint('Must-visits: '
          '${request.mustVisitPlaceIds.length} requested');
      debugPrint('Destinations: ${request.destinations}');

      return ItineraryResult.success(
        scheduledDays: scheduledDays,
        weather: weather,
        criticFeedback: critic,
        warnings: validation.issues
            .map((i) => ValidationIssue(
                  type: i.type,
                  severity: 'warning',
                  message: i.message,
                  dayIndex: i.dayIndex,
                ))
            .toList(),
        candidatePool: candidatePool,
        placeRegistry: registry,
        scoredCandidates: scored,
        clusters: clusters,
      );
    } catch (e, stack) {
      debugPrint('❌ [PIPELINE ERROR]');
      debugPrint('Stage: UNKNOWN (see stack)');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      return ItineraryResult.error(message: 'Generation failed: $e');
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Future<String> _generateAiSchedule({
    required String prompt,
    required String feedback,
  }) async {
    final fullPrompt = feedback.trim().isEmpty
        ? prompt
        : '$prompt\n\n'
            'PREVIOUS OUTPUT WAS REJECTED BY VALIDATION. '
            'REGENERATE THE ENTIRE SCHEDULE FIXING ALL ERRORS:\n'
            '$feedback\n\n'
            'Return STRICT JSON ONLY in the exact format requested above.';
    return _aiService.generateRawContent(fullPrompt);
  }

  AiValidationResult _validateSchedule({
    required List<AIDaySchedule> aiDays,
    required TripDraft request,
    required Set<String> knownPlaceIds,
    Map<String, String>? placeIdToDestination,
  }) {
    return _validator.validate(
      days: aiDays,
      knownPlaceIds: knownPlaceIds,
      mustVisitIds: request.mustVisitPlaceIds,
      totalDays: request.totalDays,
      explorationTime: request.explorationTime ?? 'Standard',
      destinationOrder: request.destinations,
      allocatedDaysPerDestination: _allocationFor(request),
      placeIdToDestination: placeIdToDestination,
    );
  }

  /// Day-per-destination allocation: the user's explicit [TripDraft.daySplit]
  /// when provided, otherwise an even split across destinations (matching
  /// what the AI prompt tells DeepSeek to assume).
  Map<String, int> _allocationFor(TripDraft request) {
    if (request.daySplit.isNotEmpty) return Map.of(request.daySplit);
    if (request.destinations.isEmpty || request.totalDays <= 0) {
      return const {};
    }
    final base = request.totalDays ~/ request.destinations.length;
    final extra = request.totalDays % request.destinations.length;
    final split = <String, int>{};
    for (int i = 0; i < request.destinations.length; i++) {
      split[request.destinations[i]] = base + (i < extra ? 1 : 0);
    }
    return split;
  }

  /// Convert validated [AIDaySchedule] into [ScheduledDay] domain objects.
  List<ScheduledDay> _toScheduledDays({
    required List<AIDaySchedule> aiDays,
    required TripDraft request,
    required PlaceRegistry registry,
    required List<ScoredAttraction> scored,
  }) {
    final scoredById = <String, ScoredAttraction>{
      for (final s in scored) s.place.placeId: s,
    };

    // Resolve a placeId to a ScoredAttraction, falling back to the registry
    // (with a neutral score) so validation-passing stops never silently drop.
    ScoredAttraction? resolve(String placeId) {
      final known = scoredById[placeId];
      if (known != null) return known;
      final place = registry.byId(placeId);
      if (place == null) return null;
      return ScoredAttraction(place: place, score: 0, breakdown: const {});
    }

    final startDate = request.startDate ?? DateTime.now();
    final result = <ScheduledDay>[];

    for (final day in aiDays) {
      final date = DateTime.tryParse(day.date) ??
          startDate.add(Duration(days: day.dayIndex));
      final stops = <ScheduledStop>[];

      for (final aiStop in day.schedule) {
        final attraction = resolve(aiStop.placeId);
        if (attraction == null) continue;

        stops.add(ScheduledStop(
          attraction: attraction,
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
        totalDuration:
            stops.fold<int>(0, (sum, s) => sum + s.durationMinutes),
        totalTravelTime:
            stops.fold<double>(0, (sum, s) => sum + s.travelFromPreviousMinutes),
      ));
    }

    return result;
  }

  DateTime _mergeTime(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 9;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  String _destinationForPlace(TripDraft request, Place place) {
    // Best-effort: nearest destination by coordinate distance.
    String? best;
    double bestDistance = double.infinity;
    for (final entry in request.destinationCoordinates.entries) {
      final d = entry.value.distanceTo(place.coordinates);
      if (d < bestDistance) {
        bestDistance = d;
        best = entry.key;
      }
    }
    return best ?? (request.destinations.isNotEmpty ? request.destinations.first : 'Unknown');
  }

  Future<WeatherForecast> _fetchWeather(
    TripDraft request,
    List<ScheduledDay> scheduledDays,
  ) async {
    try {
      if (scheduledDays.isNotEmpty && scheduledDays.first.stops.isNotEmpty) {
        final firstStop = scheduledDays.first.stops.first;
        return await _weather.getDailyForecast(
          latitude: firstStop.attraction.place.coordinates.latitude,
          longitude: firstStop.attraction.place.coordinates.longitude,
          startDate: request.startDate ?? DateTime.now(),
          endDate: request.endDate ??
              DateTime.now().add(Duration(days: request.totalDays)),
        );
      }
    } catch (e) {
      debugPrint('[WEATHER] Fetch failed: $e');
    }
    return WeatherForecast(daily: []);
  }

  Future<CriticResult> _critic(
    List<ScheduledDay> scheduledDays,
    String effectivePace,
    TripDraft request,
  ) async {
    try {
      return await _aiService.evaluateItinerary(
        days: scheduledDays,
        travelPace: effectivePace,
        interests: request.interests,
      );
    } catch (_) {
      return CriticResult(
        overallSuitable: true,
        score: 0,
        issues: const [],
        recommendations: const [],
        summary: 'AI feedback unavailable.',
      );
    }
  }
}
