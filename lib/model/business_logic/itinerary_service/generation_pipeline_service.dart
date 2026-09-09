import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/config/api_keys.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/weather_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import '../../entities/trip_draft.dart';
import '../../entities/weather.dart';
import './ai_prompt_builder.dart';
import './ai_schedule_validator.dart';
import './candidate_retrieval_service.dart';
import './clustering_service.dart';
import './itinerary_generation_status.dart';
import './place_registry.dart';
import './schedule_construction_service.dart';
import './scoring_service.dart';
import './validation_service.dart';

/// Result of the generation pipeline.
class ItineraryResult {
  final bool success;

  /// Structured, traveler-facing classification of the outcome. Always
  /// present on new results; null on legacy-constructed results.
  final ItineraryGenerationStatus? status;

  /// Traveler-facing message. For classified results this is the exact
  /// message mapped from [status] — never a raw exception string.
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
    this.status,
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
    ItineraryGenerationStatus status = ItineraryGenerationStatus.success,
    List<ValidationIssue>? warnings,
    CandidatePool? candidatePool,
    PlaceRegistry? placeRegistry,
    List<ScoredAttraction>? scoredCandidates,
    List<Cluster>? clusters,
    List<String> unretrievableMustVisits = const [],
  }) {
    return ItineraryResult(
      success: true,
      status: status,
      message: status.message,
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

  /// Traveler-safe failure. When [status] is provided the traveler message is
  /// derived from it (exact mapping); infrastructure failures without a
  /// matching status pass an already traveler-safe [travelerMessage] instead.
  /// Technical exception details must never reach either field — log them
  /// with debugPrint instead.
  factory ItineraryResult.error({
    ItineraryGenerationStatus? status,
    String? travelerMessage,
    List<ValidationIssue>? errors,
    List<String> unretrievableMustVisits = const [],
  }) {
    assert(
      status != null || travelerMessage != null,
      'Either a status or a traveler-safe message is required.',
    );
    return ItineraryResult(
      success: false,
      status: status,
      message: status?.message ?? travelerMessage,
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

  // ── Compact AI candidate pool ─────────────────────────────────
  /// Dynamic maximum for the number of candidates sent to GLM-5.3-Flash,
  /// sized by trip length via [targetCandidateCount]. The selection below
  /// guarantees must-visits, per-destination coverage, food options and
  /// cluster diversity are all preserved. The larger retrieval/scoring/
  /// clustering pipeline is unaffected — this only bounds the AI-facing pool.
  /// Target candidate count handed to the AI, sized by trip length:
  /// `(days * 7 + 8)` clamped to the [15..90] range.
  static const int maxAiCandidatePool = 90;
  static const int minAiCandidatePool = 15;

  static int targetCandidateCount(int tripDays) =>
      (tripDays * 7 + 8).clamp(minAiCandidatePool, maxAiCandidatePool);

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
    final effectivePace = request.pace ?? 'Standard';
    final effectiveExploration = request.exploration ?? 'Standard';

    // Lightweight end-to-end timing (debug only) so the <=25s target can be
    // verified per stage without enabling heavy production logging.
    final pipelineStopwatch = Stopwatch()..start();

    // ── FINAL TIMING ARCHITECTURE ───────────────────────────────
    //   0s ────────── 8s ────────── 26s ────────── 30s
    //   | Dart preproc | GLM ≤ 18s    | final Dart ops |
    //   | ≤ 8s         |              | + safety margin|
    //
    // ONE hard 30-second global deadline covers the whole operation. Dart
    // preprocessing (retrieval → reduction) is capped at 8s so the AI stage
    // always starts inside its window. GLM gets a maximum 18-second window
    // of its own. The remaining time is NOT a separate processing stage — it
    // is simply the safety margin within which the (fast) schedule
    // construction, validation, conversion and UI handoff must finish.
    final generationStart = DateTime.now();
    final globalDeadline = generationStart.add(
        Duration(seconds: request.totalDays >= 7 ? 35 : 20));
    final preprocessingDeadline =
        generationStart.add(const Duration(seconds: 8));

    Duration remainingPreprocessing() =>
        _remainingTime(preprocessingDeadline);

    debugPrint('[GENERATION] started');
    debugPrint('[GENERATION] budgets: preprocessing<=8000ms, glm<=18000ms, '
        'global<=30000ms');

    debugPrint('════════════════════════════════════════════');
    debugPrint('🚀 REQUEST ITINERARY PIPELINE START');
    debugPrint('════════════════════════════════════════════');

    // ── STAGE 01 - INPUT VALIDATION ─────────────────────────────
    debugPrint('[STAGE 01 - INPUT VALIDATION]');
    debugPrint('✓ destination count: ${request.destinationNames.length} '
        '(${request.destinationNames.join(', ')})');
    debugPrint('✓ total days: ${request.totalDays}');
    debugPrint('✓ travel type: ${request.travelType ?? 'Solo'}');
    debugPrint('✓ exploration time: $effectiveExploration');
    debugPrint('✓ travel pace: $effectivePace');
    debugPrint('✓ transportation: ${request.transportation}');
    debugPrint('✓ interests: ${request.interests}');
    debugPrint('✓ must-visits: ${request.mustVisitPlaceIds}');

    if (request.destinationNames.isEmpty) {
      return ItineraryResult.error(
        travelerMessage: 'No destination selected. Please go back to Step 1.',
      );
    }
    if (request.totalDays <= 0) {
      return ItineraryResult.error(
        travelerMessage: 'Trip duration must be at least 1 day.',
      );
    }

    try {
      // ============================================================
      // STAGE 02 - LOAD ITINERARY / PREFERENCES
      // (the TripDraft already carries loaded preferences)
      // ============================================================
      debugPrint('[STAGE 02 - LOAD ITINERARY]');
      debugPrint('✓ itinerary title: ${request..tripName}');
      debugPrint('✓ user-selected destinations: ${request.destinationNames}');
      debugPrint('✓ allocated days: ${request.daySplit}');

      // ============================================================
      // STAGE 03-06 - HOTSPOT RETRIEVAL, GOOGLE PLACES, MERGE + DEDUP
      // ============================================================
      onProgress('Finding attractions... (0/9)');
      final retrievalSw = Stopwatch()..start();
      CandidatePool candidatePool;
      try {
        // Retrieval is the slow part of preprocessing (Google Places
        // network calls) — it is bounded by the 8s preprocessing deadline so
        // a slow network can never push the AI stage out of its window.
        candidatePool = await _candidateRetrieval
            .retrieveCandidates(request: request)
            .timeout(remainingPreprocessing());
      } on TimeoutException {
        debugPrint('[DART PREPROCESSING] status=TIMEOUT (retrieval)');
        return ItineraryResult.error(
          travelerMessage: 'Finding places took too long. Please check your '
              'connection and try again.',
        );
      }
      debugPrint('[TIMING] Candidate retrieval: '
          '${retrievalSw.elapsedMilliseconds} ms');
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
      if (rawCount < retrievalTarget &&
          remainingPreprocessing() > const Duration(seconds: 2)) {
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
      // Resolved must-visit IDs = the actual Google place_ids that must be
      // included. request.mustVisitPlaceIds may contain NAMES (from the
      // wizard), so we resolve them to real place_ids after recovery.
      final resolvedMustVisitIds = <String>{};
      debugPrint('[STAGE 08 - MUST-VISIT RECOVERY]');
      debugPrint('Requested: ${request.mustVisitPlaceIds.length}');
      if (request.mustVisitPlaceIds.isEmpty) {
        debugPrint('requested = 0 → no recovery required');
      } else if (remainingPreprocessing() <= Duration.zero) {
        // Hard 8s preprocessing budget: must-visit recovery needs network
        // time that no longer exists. Cannot satisfy the hard must-visit
        // requirement → fail fast with a clear message (never silently
        // continue without the must-visits).
        debugPrint('[DART PREPROCESSING] status=TIMEOUT '
            '(before must-visit recovery)');
        return ItineraryResult.error(
          travelerMessage: 'Preparing your trip took too long. Please try again.',
        );
      } else {

        final recovery = await _candidateRetrieval.recoverMustVisits(
          requestedMustVisitIds: request.mustVisitPlaceIds,
          alreadyRetrievedIds: registry.placeIds,
          mustVisitNames: request.mustVisitPlaceIds, // ids may be names
          searchCenter: request.primaryCoordinates,
          destinationName: request.destinationNames.isNotEmpty
              ? request.destinationNames.first
              : null,
        ).timeout(remainingPreprocessing());
        recoveredMustVisitCount = recovery.recoveredPlaces.length;
        debugPrint('Found normally: ${recovery.verifiedIds.length}');
        debugPrint('Recovered: ${recovery.recoveredPlaces.length}');
        debugPrint('Missing: ${recovery.unretrievableIds}');

        // Build the set of resolved (real) must-visit place_ids.
        resolvedMustVisitIds.addAll(recovery.verifiedIds);

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
          debugPrint('❌ [MUST-VISIT] Recovery exhausted — missing: '
              '$unretrievable');
          debugPrint('❌ [MUST-VISIT] Generation BLOCKED because a hard '
              'requirement is unsatisfied (no silent continue).');
          return ItineraryResult.error(
            status: ItineraryGenerationStatus.mustVisitUnavailable,
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

        // A recovered must-visit must belong to the planned travel area.
        // Recovery searches broadly, so a far-away match means the user
        // selected a place outside the planned destination — never schedule
        // it silently.
        for (final place in recovery.recoveredPlaces) {
          if (_isOutsideTravelArea(request, place)) {
            debugPrint('❌ [MUST-VISIT] "${place.placeName}" is outside the '
                'planned destination area — generation blocked.');
            return ItineraryResult.error(
              status: ItineraryGenerationStatus.mustVisitOutsideDestination,
              errors: [
                ValidationIssue(
                  type: 'must_visit_outside_destination',
                  severity: 'error',
                  message: 'Must-visit "${place.placeName}" is outside the '
                      'planned destination area.',
                ),
              ],
            );
          }
        }
      }

      // Downstream code needs real place_ids for the must-visits so scoring
      // and the validator can match them against candidate placeIds. If the
      // user supplied real place_ids (not names), keep them as-is.
      final effectiveMustVisitIds = resolvedMustVisitIds.isNotEmpty
          ? resolvedMustVisitIds.toList()
          : request.mustVisitPlaceIds;

      // ============================================================
      // STAGE 09 - FILTER INVALID CANDIDATES
      //
      // The retrieval service already applies basic filtering
      // (business status, review floor, banned types).  The remaining
      // pool is our "usable" set.
      // ============================================================
      onProgress('Filtering candidates... (1/9)');
      final usableCount = candidatePool.totalCount;
      debugPrint('[STAGE 09 - FILTER]');
      debugPrint('Before: $rawCount');
      debugPrint('After: $usableCount');
      debugPrint('Removed: ${rawCount - usableCount}');
      debugPrint('Reason breakdown: built-in retrieval hygiene '
          '(business status, review floor, banned types)');

      if (candidatePool.attractions.isEmpty) {
        debugPrint('[STAGE 09] No attractions survived — noSuitablePlaces');
        return ItineraryResult.error(
          status: ItineraryGenerationStatus.noSuitablePlaces,
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
      if (usableCount < usableTarget &&
          remainingPreprocessing() > const Duration(seconds: 2)) {
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
      onProgress('Scoring places... (2/9)');
      final allPlaces = [...candidatePool.attractions, ...candidatePool.food];
      debugPrint('[STAGE 11 - SCORING]');
      debugPrint('Candidates entering: ${allPlaces.length}');
      debugPrint('Candidates removed by scoring: 0 (all usable scored)');

      final scoringSw = Stopwatch()..start();
      var scored = _scoring.scorePlaces(
        places: allPlaces,
        selectedInterests: request.interests.toList(),
        mustVisitIds: effectiveMustVisitIds,
        explorationTime: effectiveExploration,
        tripLocation: tripLocation,
        travelerType: request.travelType ?? 'Solo',
        transportMode: request.transportation,
        strictInterestFilter: false, // rank all, do not eliminate
      );
      debugPrint('[TIMING] Scoring: ${scoringSw.elapsedMilliseconds} ms');
      debugPrint('Candidates scored: ${scored.length}');
      debugPrint('All usable candidates scored.');
      for (var i = 0; i < scored.length && i < 5; i++) {
        final s = scored[i];
        debugPrint('  ${i + 1}. ${s.place.placeName} '
            '(${s.score.toStringAsFixed(2)})');
      }

      if (scored.isEmpty) {
        debugPrint('[STAGE 11] Scoring produced no candidates — '
            'noSuitablePlaces');
        return ItineraryResult.error(
          status: ItineraryGenerationStatus.noSuitablePlaces,
        );
      }

      // ============================================================
      // STAGE 12 - K-MEANS — PURE GEOGRAPHIC CLUSTERING
      // ============================================================
      onProgress('Grouping by location... (3/9)');
      final clusteringSw = Stopwatch()..start();
      final clusters = _clustering.clusterGeographically(
        scoredPlaces: scored,
        clusterCount: request.totalDays.clamp(1, scored.length),
      );
      debugPrint('[TIMING] Clustering: ${clusteringSw.elapsedMilliseconds} ms');
      debugPrint('[STAGE 12 - K-MEANS]');
      debugPrint('Input candidates: ${scored.length}');
      debugPrint('Number of clusters: ${clusters.length}');
      for (final c in clusters) {
        debugPrint('Cluster ${c.dayIndex}: ${c.attractions.length} places');
      }

      // ============================================================
      // STAGE 13 - PREPARE STRUCTURED AI INPUT
      // ============================================================
      onProgress('Grouping by location... (3/9)');
      final clusterIdOfPlace = <String, int>{};
      for (final c in clusters) {
        for (final a in c.attractions) {
          clusterIdOfPlace[a.place.placeId] = c.dayIndex;
        }
      }

      // ── STAGE 13A - COMPACT AI CANDIDATE POOL ─────────────────
      // Dart has already filtered, scored, ranked and clustered the full
      // candidate pool. We hand the AI a SMALLER, high-quality subset so the
      // prompt stays compact (faster planning) while guaranteeing:
      //   • every must-visit is ALWAYS retained (hard requirement),
      //   • every destination keeps enough candidates for its allocated days,
      //   • every geographic cluster stays represented,
      //   • enough food options remain for meals.
      final aiCandidateIds = _selectAICandidates(
        scored: scored,
        request: request,
        clusters: clusters,
      ).map((s) => s.place.placeId).toSet();
      final aiCandidates = scored
          .where((s) => aiCandidateIds.contains(s.place.placeId))
          .toList();
      debugPrint('[CANDIDATE REDUCTION] Full pool: ${scored.length} → '
          'AI pool: ${aiCandidates.length}');

      // Clusters shown to the AI only list retained candidates so the AI
      // never sees a place name that is not available in CANDIDATES.
      final aiClusters = clusters.map((c) => Cluster(
        dayIndex: c.dayIndex,
        center: c.center,
        attractions: c.attractions
            .where((a) => aiCandidateIds.contains(a.place.placeId))
            .toList(),
      )).where((c) => c.attractions.isNotEmpty).toList();

      final candidates = aiCandidates.map((s) {
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

      // Pre-fetch weather forecast so AI prompt can adapt recommendations to
      // sunny vs rainy days.
      Coordinates? tripCoord;
      if (request.destinationCoordinates.isNotEmpty) {
        tripCoord = request.destinationCoordinates.values.first;
      } else if (candidates.isNotEmpty) {
        tripCoord = Coordinates(
          latitude: candidates.first.latitude,
          longitude: candidates.first.longitude,
        );
      }
      final startDate = request.startDate ?? DateTime.now();
      final endDate = request.endDate ??
          startDate.add(Duration(days: request.totalDays));
      final weather = await _fetchWeatherForTrip(
        tripCoord,
        startDate,
        endDate,
      );

      final prompt = _promptBuilder.buildCompactPlanPrompt(
        request: request,
        candidates: candidates,
        clusters: aiClusters,
        mustVisitIds: effectiveMustVisitIds,
        weatherForecast: weather,
      );

      debugPrint('[STAGE 13 - DEEPSEEK INPUT]');
      debugPrint('Trip days: ${request.totalDays}');
      debugPrint('Destination allocation: ${request.daySplit.isNotEmpty ? request.daySplit : 'even split'}');
      debugPrint('Travel pace: $effectivePace');
      debugPrint('Exploration time: $effectiveExploration');
      debugPrint('Must-visits: ${request.mustVisitPlaceIds.length}');
      debugPrint('Candidate count: ${candidates.length}');
      debugPrint('Cluster count: ${clusters.length}');
      debugPrint('Prompt size: ${prompt.length} chars');

      // ============================================================
      // STAGE 14-15 - ONE COMPACT AI REQUEST + DART SCHEDULING
      // ============================================================
      //
      // OPTIMIZED RESPONSIBILITY SPLIT:
      //   AI  → returns ONLY { dayIndex, placeIds[], reason } (selection,
      //         grouping, ordering, short explanation).
      //   DART → computes stopOrder, startTime, endTime, visitDuration and
      //         travel time, then validates.
      //
      // There is exactly ONE global 24s deadline for the whole AI planning
      // operation (safety margin below the 25s requirement). It is never
      // reset: a timeout or invalid response goes straight to the
      // deterministic planner — NO second AI request.
      onProgress('Creating schedule... (4/9)');
      final plannerSw = Stopwatch()..start();

      // ── [DART PREPROCESSING] summary ────────────────────────────
      final preprocessingMs = plannerSw.elapsedMilliseconds;
      final preprocessingStatus =
      remainingPreprocessing() <= Duration.zero ? 'TIMEOUT' : 'SUCCESS';
      debugPrint('[DART PREPROCESSING]');
      debugPrint('retrieved=$rawCount');
      debugPrint('scored=${scored.length}');
      debugPrint('clusters=${clusters.length}');
      debugPrint('reduced=${candidates.length}');
      debugPrint('elapsedMs=$preprocessingMs');
      debugPrint('status=$preprocessingStatus');

      // ── GLM window: preferred 12.5s from AI invocation, hard-capped by
      //    the 18-second global pipeline deadline. ─────────────────────
      const postProcessingBuffer = Duration(seconds: 1);
      final remainingToGlobal = globalDeadline.difference(DateTime.now());

      // Ensure we don't go negative; if the remaining time is less than the buffer,
      // fall back to a minimal safe duration (5 seconds).
      Duration aiDuration;
      if (remainingToGlobal <= postProcessingBuffer) {
        aiDuration = const Duration(seconds: 5);
      } else {
        aiDuration = remainingToGlobal - postProcessingBuffer;
      }

      // Clamp to sensible bounds: minimum 5s, maximum 28s for long trips
      const minAiDuration = Duration(seconds: 5);
      final maxAiDurationLimit = Duration(seconds: request.totalDays >= 7 ? 28 : 15);
      if (aiDuration < minAiDuration) {
        aiDuration = minAiDuration;
      } else if (aiDuration > maxAiDurationLimit) {
        aiDuration = maxAiDurationLimit;
      }

      final aiDeadline = DateTime.now().add(aiDuration);

      debugPrint('[AI PLANNER] AI deadline: ${aiDuration.inMilliseconds} ms from now');

      debugPrint('[AI PLANNER] PROVIDER: Google Gemini');
      debugPrint('[AI PLANNER] MODEL: ${_aiService.geminiModel}');
      debugPrint('[AI PLANNER] START');
      debugPrint('[AI PLANNER] Candidates: ${candidates.length}');
      debugPrint('[AI PLANNER] Prompt: ${prompt.length} chars');
      debugPrint('[AI PLANNER] Max tokens: ${AIService.plannerMaxTokens}');
      debugPrint('[AI PLANNER] AI deadline: '
          '${aiDeadline.difference(DateTime.now()).inMilliseconds} ms from now');

      // AI must only reference place IDs that survived scoring.
      final scoredPlaceIds = scored.map((s) => s.place.placeId).toSet();

      // 1. ONE parallel AI recommendation attempt within the global deadline.
      final aiAttempt = await _tryAiPlan(
        prompt: prompt,
        deadline: aiDeadline,
      );
      final aiAttempts = aiAttempt.attempts;
      debugPrint('[AI RESPONSE: ITINERARY_PLANNER] Elapsed: '
          '${plannerSw.elapsedMilliseconds} ms');

      // 2. Granular Dart repair of the compact AI plan (preserves AI's
      //    intelligent grouping where possible — avoids full fallback).
      String aiStatus = aiAttempt.status;
      final plan = aiAttempt.plan != null
          ? _repairPlan(
        plan: aiAttempt.plan!,
        request: request,
        knownIds: scoredPlaceIds,
        mustVisitIds: effectiveMustVisitIds,
        placeIdToDestination: placeIdToDestination,
        scored: scored,
      )
          : null;

      if (plan == null && aiStatus == 'AI_SUCCESS') {
        // The AI returned JSON but it could not be repaired into a valid plan.
        aiStatus = 'AI_INVALID_RESPONSE';
        debugPrint('[AI FALLBACK] AI plan unrecoverable '
            '($aiStatus) — deterministic planner');
      } else if (plan == null) {
        debugPrint('[AI FALLBACK] AI plan unavailable '
            '($aiStatus) — deterministic planner');
      }

      // 3. Dart constructs the full schedule (times/durations/travel).
      List<AIDaySchedule> aiDays;
      AiValidationResult validation;
      int aiSelectedCount = 0;
      int fallbackSelectedCount = 0;

      if (plan != null) {
        aiDays = _constructAiDaysFromPlan(
          mustVisitIds: effectiveMustVisitIds,
          plan: plan,
          request: request,
          scored: scored,
        );
        aiSelectedCount = aiDays.fold<int>(0, (s, d) => s + d.schedule.length);
        debugPrint('[SCHEDULE] Elapsed: ${plannerSw.elapsedMilliseconds} ms');
        validation = _validateSchedule(
          aiDays: aiDays,
          request: request,
          knownPlaceIds: scoredPlaceIds,
          mustVisitIds: effectiveMustVisitIds,
          placeIdToDestination: placeIdToDestination,
        );
        debugPrint('[VALIDATION] Elapsed: ${plannerSw.elapsedMilliseconds} ms');
      } else {
        aiDays = const [];
        validation = const AiValidationResult(passed: false, issues: []);
      }

      // 4. If validation failed, rebuild deterministically (no second AI).
      //    The ORIGINAL AI failure reason is preserved so the result can be
      //    classified honestly (aiUnavailable vs aiResponseInvalid).
      String aiFailureReason = '';
      if (!validation.passed) {
        if (aiStatus == 'AI_SUCCESS') {
          // The AI produced a plan but it violated a hard constraint that
          // repair could not fix.
          aiStatus = 'AI_VALIDATION_FAILED';
        }
        debugPrint('[AI FALLBACK] Validation failed '
            '($aiStatus) — deterministic planner');
        aiFailureReason = aiStatus;
        final fallbackPlan = _buildDeterministicPlan(
          request: request,
          scored: scored,
          mustVisitIds: effectiveMustVisitIds,
        );
        aiDays = _constructAiDaysFromPlan(
          mustVisitIds: effectiveMustVisitIds,
          plan: fallbackPlan,
          request: request,
          scored: scored,
        );
        fallbackSelectedCount = aiDays.fold<int>(0, (s, d) => s + d.schedule.length);
        validation = _validateSchedule(
          aiDays: aiDays,
          request: request,
          knownPlaceIds: scoredPlaceIds,
          mustVisitIds: effectiveMustVisitIds,
          placeIdToDestination: placeIdToDestination,
        );
        aiStatus = validation.passed ? 'FALLBACK_SUCCESS' : 'FALLBACK_FAILED';
        debugPrint('[AI PLANNER] FALLBACK COMPLETE: '
            '${plannerSw.elapsedMilliseconds} ms');
      }

      debugPrint('[AI PLANNER] TOTAL: ${plannerSw.elapsedMilliseconds} ms');
      debugPrint('[AI PLANNER] RESULT: $aiStatus');
      debugPrint('[AI PLAN] days=${aiDays.length} '
          'stops=${aiDays.fold<int>(0, (s, d) => s + d.schedule.length)}');

      if (!validation.passed) {
        debugPrint('❌ [VALIDATION FAILED ISSUES]:');
        for (final i in validation.issues) {
          debugPrint('   → [${i.type}] ${i.message}');
        }
        // Classify the hard failure from the constraint issues that remain.
        final failureStatus = mostSevereStatus([
          for (final i in validation.issues)
            _constraintIssueStatus(i, effectiveMustVisitIds.toSet()),
        ]);
        return ItineraryResult.error(
          status: failureStatus ??
              ItineraryGenerationStatus.scheduleTooFull,
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

      // ============================================================
      // STAGE 16 - CONVERT VALIDATED AI OUTPUT → DOMAIN SCHEDULE
      // ============================================================
      onProgress('Validating... (5/9)');
      final scheduledDays = _toScheduledDays(
        aiDays: aiDays,
        request: request,
        registry: registry,
        scored: scored,
      );

// ============================================================
      // FINAL ITINERARY DEBUG OUTPUT (DATABASE RECORD FORMAT)
      // ============================================================
      debugPrint('════════════════════════════════════════════');
      debugPrint('📋 FINAL ITINERARY - DATABASE RECORD FORMAT');
      debugPrint('════════════════════════════════════════════');

      for (final day in scheduledDays) {
        debugPrint('{');
        debugPrint('  "day_index": ${day.dayIndex},');
        debugPrint('  "date": "${day.date.toIso8601String().split('T').first}",');
        debugPrint('  "total_duration_minutes": ${day.totalDuration},');
        debugPrint('  "total_travel_minutes": ${day.totalTravelTime},');
        debugPrint('  "stops": [');

        if (day.stops.isEmpty) {
          debugPrint('    // ⚠ No stops scheduled');
        } else {
          for (int i = 0; i < day.stops.length; i++) {
            final stop = day.stops[i];

            // Format DateTime objects to strict HH:mm:ss for DB timestamp standards
            final start = '${stop.startTime.hour.toString().padLeft(2, '0')}:${stop.startTime.minute.toString().padLeft(2, '0')}:00';
            final end = '${stop.endTime.hour.toString().padLeft(2, '0')}:${stop.endTime.minute.toString().padLeft(2, '0')}:00';

            final isLast = i == day.stops.length - 1;

            debugPrint('    {');
            debugPrint('      "stop_order": ${i + 1},');
            debugPrint('      "place_id": "${stop.attraction.place.placeId}",');
            debugPrint('      "place_name": "${stop.attraction.place.placeName.replaceAll('"', '\\"')}",');
            debugPrint('      "start_time": "$start",');
            debugPrint('      "end_time": "$end",');
            debugPrint('      "duration_minutes": ${stop.durationMinutes},');
            debugPrint('      "travel_time_minutes": ${stop.travelFromPreviousMinutes}');
            debugPrint('    }${isLast ? '' : ','}');
          }
        }

        debugPrint('  ]');
        debugPrint('}');
        debugPrint('');
      }

      debugPrint('════════════════════════════════════════════');
      debugPrint('📋 END FINAL ITINERARY');
      debugPrint('════════════════════════════════════════════');

      if (scheduledDays.isEmpty) {
        return ItineraryResult.error(
          travelerMessage: 'Could not complete your itinerary. '
              'Please try again.',
        );
      }

      // ============================================================
      // STAGE 17 - WEATHER (NO secondary AI call)
      onProgress('Fetching weather... (6/9)');
      // ============================================================
      //
      // The travel plan is complete at this point. Weather is fetched from
      // Open-Meteo (a free, fast API). There is deliberately NO AI critic
      // call here: another LLM request would keep running asynchronously
      // after PIPELINE COMPLETE, wasting ~15–35s of background work and
      // misleading the timing logs. All validation (duplicates, windows,
      // chronology, must-visits, place IDs, travel/duration) is performed
      // deterministically by Dart already.

      // Reuse pre-fetched weather or attempt fallback with first scheduled stop
      var finalWeather = weather;
      if (finalWeather.daily.isEmpty) {
        Coordinates? firstCoord;
        if (scheduledDays.isNotEmpty && scheduledDays.first.stops.isNotEmpty) {
          firstCoord = scheduledDays.first.stops.first.attraction.place.coordinates;
        }
        finalWeather = await _fetchWeatherForTrip(
          firstCoord,
          startDate,
          endDate,
        );
      }

      // Enrich scheduledDays with weather forecast if available
      var finalScheduledDays = scheduledDays;
      if (finalWeather.daily.isNotEmpty) {
        final weatherMap = {
          for (final w in weather.daily)
            '${w.date.year}-${w.date.month}-${w.date.day}': w,
        };
        final enrichedDays = <ScheduledDay>[];
        for (final day in scheduledDays) {
          final key = '${day.date.year}-${day.date.month}-${day.date.day}';
          final dw = weatherMap[key];
          if (dw != null) {
            final note = '${dw.condition} · ${dw.minTemperature.round()}°C - ${dw.maxTemperature.round()}°C';
            final enrichedStops = day.stops.map((stop) {
              return ScheduledStop(
                attraction: stop.attraction,
                startTime: stop.startTime,
                endTime: stop.endTime,
                durationMinutes: stop.durationMinutes,
                travelFromPreviousMinutes: stop.travelFromPreviousMinutes,
                scheduleReason: stop.scheduleReason,
                weatherNote: note,
              );
            }).toList();
            enrichedDays.add(ScheduledDay(
              dayIndex: day.dayIndex,
              date: day.date,
              stops: enrichedStops,
              totalDuration: day.totalDuration,
              totalTravelTime: day.totalTravelTime,
            ));
          } else {
            enrichedDays.add(day);
          }
        }
        finalScheduledDays = enrichedDays;
      }

      final List<String> unretrievable = const [];
      final critic = const CriticResult(
        overallSuitable: true,
        score: 0,
        issues: [],
        recommendations: [],
        summary: 'AI feedback unavailable.',
      );

      // 5. DIAGNOSTIC SUMMARY
      onProgress('Checking results... (7/9)');
      final totalStops =
      scheduledDays.fold<int>(0, (sum, d) => sum + d.stops.length);
      debugPrint('════════════════════════════════════════════');
      debugPrint('✅ PIPELINE COMPLETE');
      debugPrint('════════════════════════════════════════════');
      debugPrint('[FINAL]');
      debugPrint('validation=${validation.passed ? "PASS" : "FAIL"}');
      debugPrint('days=${scheduledDays.length}');
      debugPrint('stops=$totalStops');
      debugPrint('totalElapsedMs=${pipelineStopwatch.elapsedMilliseconds}');
      debugPrint('[AI RESULT]');
      for (final a in aiAttempts) {
        debugPrint('provider=${a.provider} status=${a.status} '
            'elapsedMs=${a.elapsedMs} finish=${a.finishReason ?? 'n/a'}');
      }
      debugPrint('classification=$aiStatus');
      debugPrint('aiSelected=$aiSelectedCount '
          'fallbackSelected=$fallbackSelectedCount');
      debugPrint('mustVisits=${request.mustVisitPlaceIds.length} '
          'recovered=$recoveredMustVisitCount');

      // ── FINAL RESULT CLASSIFICATION ─────────────────────────────
      // The pipeline determines the traveler-facing reason from what
      // actually happened — the UI never guesses.
      final failureStatus = mostSevereStatus([
        for (final i in validation.issues)
          _constraintIssueStatus(i, effectiveMustVisitIds.toSet()),
      ]);
      final resultStatus = _classifyResult(
        request: request,
        scored: scored,
        constraintStatus: failureStatus,
        aiFailureReason: aiFailureReason,
      );
      debugPrint('[RESULT STATUS] ${resultStatus.name}');

      onProgress('Finalizing your itinerary... (8/9)');
      return ItineraryResult.success(
          scheduledDays: finalScheduledDays,
          weather: finalWeather,
          criticFeedback: critic,
          status: resultStatus,
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
          unretrievableMustVisits: unretrievable
      );
    } catch (e, stack) {
      // Technical details stay in the log — the traveler receives a
      // safe, generic classification, never '$e'.
      debugPrint('❌ [PIPELINE ERROR]');
      debugPrint('Stage: UNKNOWN (see stack)');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      return ItineraryResult.error(
        travelerMessage: 'Could not generate the itinerary. '
            'Please check your connection and try again.',
      );
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  // ============================================================
  // HELPERS — RESULT CLASSIFICATION (traveler-facing status)
  // ============================================================

  /// True when [place] lies outside every planned destination's travel area
  /// (reuses the existing search-radius ceiling).
  bool _isOutsideTravelArea(TripDraft request, Place place) {
    if (request.destinationCoordinates.isEmpty) return false;
    for (final coord in request.destinationCoordinates.values) {
      if (coord.distanceTo(place.coordinates) <=
          ItineraryConstants.maxSearchRadiusKm) {
        return false;
      }
    }
    return true;
  }

  /// Maps one validation issue to its traveler-facing status. Issues that do
  /// not carry traveler-relevant information return null.
  ItineraryGenerationStatus? _constraintIssueStatus(
    AiValidationIssue issue,
    Set<String> mustVisitIds,
  ) {
    switch (issue.type) {
      case 'must_visit':
        return ItineraryGenerationStatus.mustVisitUnavailable;
      case 'destination_allocation':
        // Only a must-visit outside its planned destination is traveler
        // facing; generic allocation drift is repaired silently.
        final pid = issue.placeId;
        if (pid != null && mustVisitIds.contains(pid)) {
          return ItineraryGenerationStatus.mustVisitOutsideDestination;
        }
        return null;
      case 'route_jump':
        return ItineraryGenerationStatus.travelDistanceTooLong;
      case 'window':
        // Scheduled outside the allowed time window — closest traveler
        // semantic is an opening-hours/time-window conflict.
        return ItineraryGenerationStatus.openingHoursConflict;
      default:
        return null;
    }
  }

  /// Maps the reason the deterministic fallback was used to a status.
  ItineraryGenerationStatus? _aiStatusToGenerationStatus(String reason) {
    switch (reason) {
      case 'AI_TIMEOUT':
      case 'AI_PROVIDER_ERROR':
        return ItineraryGenerationStatus.aiUnavailable;
      case 'AI_TRUNCATED_RESPONSE':
      case 'AI_INVALID_JSON':
      case 'AI_INVALID_MODEL_OUTPUT':
      case 'AI_INVALID_RESPONSE':
      case 'AI_VALIDATION_FAILED':
        return ItineraryGenerationStatus.aiResponseInvalid;
      default:
        return null;
    }
  }

  /// Determines the final traveler-facing status of a SUCCESSFUL generation
  /// (an itinerary exists). Multiple findings are combined by severity
  /// priority; plain success is returned when nothing notable happened.
  ItineraryGenerationStatus _classifyResult({
    required TripDraft request,
    required List<ScoredAttraction> scored,
    ItineraryGenerationStatus? constraintStatus,
    required String aiFailureReason,
  }) {
    final findings = <ItineraryGenerationStatus?>[
      // Constraint conflicts that survived validation as warnings.
      constraintStatus,
      // AI degradation — the itinerary was produced by the deterministic
      // fallback because the AI was unavailable or unusable.
      aiFailureReason.isEmpty
          ? null
          : _aiStatusToGenerationStatus(aiFailureReason),
      // "Few places": candidates exist but not enough to fill the requested
      // schedule — free time was left instead of forcing unrelated places.
      _hasTooFewCandidates(request, scored)
          ? ItineraryGenerationStatus.fewSuitablePlaces
          : null,
    ];

    return mostSevereStatus(findings) ?? ItineraryGenerationStatus.success;
  }

  /// True when the usable attraction pool cannot cover the minimum planned
  /// stops for the whole trip.
  bool _hasTooFewCandidates(TripDraft request, List<ScoredAttraction> scored) {
    final availableAttractions =
        scored.where((s) => !_isFoodScored(s)).length;
    final needed =
        request.totalDays * ItineraryConstants.minAttractionsPerDay;
    return availableAttractions < needed;
  }

  // ============================================================
  // HELPERS — COMPACT AI PLANNER
  // ============================================================

  /// ONE B.AI / GLM-5.3-Flash recommendation attempt within the [deadline].
  ///
  /// B.AI is the ONLY AI provider for itinerary generation — OpenRouter and
  /// Cohere are never called here. Returns the parsed plan, a status string
  /// (AI_SUCCESS / AI_TIMEOUT / AI_PROVIDER_ERROR / AI_TRUNCATED_RESPONSE /
  /// AI_INVALID_MODEL_OUTPUT) and the provider attempt record for
  /// diagnostics. Any failure goes to the deterministic fallback — there is
  /// no second AI provider to try.
  Future<({
  List<AiCompactPlanDay>? plan,
  String status,
  List<ProviderAiAttempt> attempts,
  })> _tryAiPlan({
    required String prompt,
    required DateTime deadline,
  }) async {
    final remaining = _remainingTime(deadline);
    if (remaining <= Duration.zero) {
      debugPrint(
          '[AI FALLBACK: ITINERARY_PLANNER] No remaining budget — deterministic planner');
      return (plan: null, status: 'AI_TIMEOUT', attempts: const <ProviderAiAttempt>[]);
    }
    debugPrint(
        '[AI REQUEST: ITINERARY_PLANNER] Remaining: ${remaining.inMilliseconds} ms');

    final outcome = await _aiService.generatePlannerRecommendation(
      prompt,
      deadline: deadline,
    );

    if (outcome.outcome != 'AI_SUCCESS' || outcome.rawText == null) {
      return (plan: null, status: outcome.outcome, attempts: outcome.attempts);
    }

    try {
      final plan = parseCompactPlanJson(outcome.rawText!);
      debugPrint('[AI PARSE: ITINERARY_PLANNER] OK '
          '(${plan.fold<int>(0, (s, d) => s + d.placeIds.length)} places)');
      return (plan: plan, status: 'AI_SUCCESS', attempts: outcome.attempts);
    } catch (e) {
      // finish_reason == "length" with unparseable JSON = genuinely
      // truncated output. Anything else is malformed JSON.
      String? winnerFinish;
      for (final a in outcome.attempts) {
        if (a.provider == outcome.winningProvider) {
          winnerFinish = a.finishReason;
          break;
        }
      }
      final status = winnerFinish == 'length'
          ? 'AI_TRUNCATED_RESPONSE'
          : 'AI_INVALID_JSON';
      debugPrint('[AI PARSE: ITINERARY_PLANNER] FAILED ($status): $e');
      final raw = outcome.rawText!;
      debugPrint('[AI PARSE] content head: '
          '${raw.length > 800 ? raw.substring(0, 800) : raw}');
      return (plan: null, status: status, attempts: outcome.attempts);
    }
  }

  /// Granular repair of a compact AI plan.
  ///
  /// Tries to fix common problems deterministically while preserving the AI's
  /// intelligent grouping/ordering wherever possible. Returns null when the
  /// plan is unrecoverable (the caller then uses the full fallback).
  ///
  /// Repairs applied:
  ///   1. Discard unknown place IDs.
  ///   2. Deduplicate across all days (first occurrence wins).
  ///   3. Insert missing must-visits into the first day of their destination.
  ///   4. Move wrongly-placed places (destination mismatch) to the first day
  ///      of their correct destination.
  ///   5. Fill missing day indices (empty days) with the best remaining
  ///      candidates for that destination.
  List<AiCompactPlanDay>? _repairPlan({
    required List<AiCompactPlanDay> plan,
    required TripDraft request,
    required Set<String> knownIds,
    required List<String> mustVisitIds,
    required Map<String, String> placeIdToDestination,
    List<ScoredAttraction>? scored,
  }) {
    if (plan.isEmpty) return null;

    final allocation = _allocationFor(request);
    // Map dayIndex → destination name.
    final dayDest = <int, String>{};
    var counter = 0;
    for (final name in request.destinationNames) {
      final days = (allocation[name] ?? 1).clamp(1, 14);
      for (var d = 0; d < days; d++) {
        if (counter < request.totalDays) dayDest[counter++] = name;
      }
    }

    // 1. Collect per-day placeIds, discarding unknowns. AI-estimated visit
    //    minutes are preserved so the schedule constructor keeps using them.
    final byDay = <int, List<String>>{};
    for (var d = 0; d < request.totalDays; d++) {
      byDay[d] = [];
    }
    final visitMinutes = <String, int>{};
    // Track reasons per day.
    final reasons = <int, String>{};

    // ── 0-based normalization ────────────────────────────────────
    final usedIndexes = plan.map((d) => d.dayIndex).toSet();
    final hasOutOfBounds = usedIndexes.any((i) => i >= request.totalDays);
    var normalizedPlan = plan;
    if (hasOutOfBounds &&
        !usedIndexes.contains(0) &&
        usedIndexes.contains(request.totalDays)) {
      debugPrint('[REPAIR] Detected 1-based dayIndex — normalizing to 0-based');
      normalizedPlan = plan
          .map((d) => AiCompactPlanDay(
        dayIndex: d.dayIndex - 1,
        placeIds: d.placeIds,
        visitMinutes: d.visitMinutes,
        reason: d.reason,
      ))
          .toList();
    }

    for (final day in normalizedPlan) {
      final idx = day.dayIndex;
      if (idx < 0 || idx >= request.totalDays) continue;
      reasons[idx] = day.reason;
      visitMinutes.addAll(day.visitMinutes);
      for (final id in day.placeIds) {
        if (knownIds.contains(id)) byDay[idx]!.add(id);
      }
    }

    // 2. Dedup across all days (first occurrence keeps its spot).
    final seen = <String>{};
    for (var d = 0; d < request.totalDays; d++) {
      final deduped = <String>[];
      for (final id in byDay[d]!) {
        if (seen.add(id)) deduped.add(id);
      }
      byDay[d] = deduped;
    }

    // 3. Insert missing must-visits.
    final mvDest = <String, String>{};
    for (final mv in mustVisitIds.where((m) => m.isNotEmpty && knownIds.contains(m))) {
      if (seen.contains(mv)) continue; // already present
      final dest = placeIdToDestination[mv] ?? request.destinationNames.first;
      mvDest[mv] = dest;
      // Find first day for this destination, or day 0.
      var targetDay = 0;
      for (var d = 0; d < request.totalDays; d++) {
        if (dayDest[d] == dest) { targetDay = d; break; }
      }
      byDay[targetDay]!.insert(0, mv); // front of the day
      seen.add(mv);
    }

    // 4. Destination allocation: move misplaced places.
    for (var d = 0; d < request.totalDays; d++) {
      final expectedDest = dayDest[d] ?? request.destinationNames.first;
      final correct = <String>[];
      final misplaced = <String, String>{}; // placeId → correctDest
      for (final id in byDay[d]!) {
        final dest = placeIdToDestination[id] ?? expectedDest;
        if (dest == expectedDest) {
          correct.add(id);
        } else {
          misplaced[id] = dest;
        }
      }
      byDay[d] = correct;
      // Re-insert misplaced places into the first day of their destination.
      for (final entry in misplaced.entries) {
        var targetDay = 0;
        for (var td = 0; td < request.totalDays; td++) {
          if (dayDest[td] == entry.value) { targetDay = td; break; }
        }
        byDay[targetDay]!.add(entry.key);
      }
    }

    // 5. Fill empty days with candidates moved from other days that belong
    //    to this day's destination.
    for (var d = 0; d < request.totalDays; d++) {
      if (byDay[d]!.isNotEmpty) continue;
      final expectedDest = dayDest[d] ?? '';
      for (var od = 0; od < request.totalDays; od++) {
        if (od == d) continue;
        final removable = <int>[];
        for (var i = 0; i < byDay[od]!.length; i++) {
          final id = byDay[od]![i];
          final dest = placeIdToDestination[id] ?? '';
          if (dest == expectedDest) {
            byDay[d]!.add(id);
            removable.add(i);
          }
        }
        // Remove from source (reverse order).
        for (var i = removable.length - 1; i >= 0; i--) {
          byDay[od]!.removeAt(removable[i]);
        }
      }
    }

    // 6. Enrich sparse or underpopulated days with unused candidates so NO day
    //    is left starved (e.g. Day 1 has 1 stop while Day 2/3 are empty).
    final targetStops = request.pace == 'Slow' ? 4 : (request.pace == 'Fast' ? 6 : 5);
    if (scored != null && scored.isNotEmpty) {
      final usedIds = <String>{
        for (final list in byDay.values) ...list,
      };
      final unusedSorted = List<ScoredAttraction>.from(scored)
        ..sort((a, b) => b.score.compareTo(a.score));

      for (var d = 0; d < request.totalDays; d++) {
        if (byDay[d]!.length >= targetStops) continue;
        final expectedDest = (dayDest[d] ?? request.destinationNames.first).trim().toLowerCase();

        for (final s in unusedSorted) {
          if (byDay[d]!.length >= targetStops) break;
          final pid = s.place.placeId;
          if (usedIds.contains(pid)) continue;
          final dest = (placeIdToDestination[pid] ?? expectedDest).trim().toLowerCase();
          if (dest != expectedDest) continue;
          if (_isNightlifeScored(s)) continue; // Never top up with more nightlife venues

          byDay[d]!.add(pid);
          usedIds.add(pid);
        }
      }
    }

    // Rebuild plan.
    final result = <AiCompactPlanDay>[];
    for (var d = 0; d < request.totalDays; d++) {
      result.add(AiCompactPlanDay(
        dayIndex: d,
        placeIds: byDay[d]!,
        visitMinutes: visitMinutes,
        reason: reasons[d] ?? 'Balanced and repaired by Dart.',
      ));
    }

    // Final check: if every day is empty, the plan is unrecoverable.
    if (result.every((day) => day.placeIds.isEmpty)) return null;
    return result;
  }

  /// Converts a compact AI plan (dayIndex + ordered places) into a list of
  /// fully computed [AIDaySchedule]s. All clock times and travel times are
  /// computed deterministically in Dart. AI-estimated visit minutes are used
  /// when provided; otherwise the Dart category baseline applies.
  List<AIDaySchedule> _constructAiDaysFromPlan({
    required List<String> mustVisitIds,
    required List<AiCompactPlanDay> plan,
    required TripDraft request,
    required List<ScoredAttraction> scored,
  }) {
    final scoredById = <String, ScoredAttraction>{
      for (final s in scored) s.place.placeId: s,
    };
    final window = ItineraryConstants.explorationWindowFor(
        request.exploration ?? 'Standard');
    final startDate = request.startDate ?? DateTime.now();
    final travelPace = request.pace ?? 'Standard';
    final transportation = request.transportation;

    final globalUsedIds = <String>{};
    for (final day in plan) {
      globalUsedIds.addAll(day.placeIds);
    }

    final days = <AIDaySchedule>[];
    for (final day in plan) {
      days.add(
        _constructDaySchedule(
          dayIndex: day.dayIndex,
          date: startDate.add(Duration(days: day.dayIndex)),
          orderedPlaceIds: day.placeIds,
          aiVisitMinutes: day.visitMinutes,
          reason: day.reason,
          window: window,
          travelPace: travelPace,
          transportation: transportation,
          scoredById: scoredById,
          request: request,
          globalUsedIds: globalUsedIds,
        ),
      );
    }
    final seenStops = <String>{};
    final cleanedDays = <AIDaySchedule>[];
    for (final day in days) {
      final validStops = <AIScheduleStop>[];
      for (final stop in day.schedule) {
        if (seenStops.add(stop.placeId)) {
          validStops.add(stop);
        } else {
          debugPrint('⚠️ [DEDUP SAFETY] Dropping duplicate placeId "${stop.placeId}" from day ${day.dayIndex}');
        }
      }
      final reorderedStops = <AIScheduleStop>[];
      for (var i = 0; i < validStops.length; i++) {
        final s = validStops[i];
        reorderedStops.add(AIScheduleStop(
          stopOrder: i + 1,
          placeId: s.placeId,
          startTime: s.startTime,
          endTime: s.endTime,
          visitDurationMinutes: s.visitDurationMinutes,
          travelFromPreviousMinutes: i == 0 ? 0 : s.travelFromPreviousMinutes,
          scheduleReason: s.scheduleReason,
          weatherNote: s.weatherNote,
        ));
      }
      cleanedDays.add(AIDaySchedule(
        dayIndex: day.dayIndex,
        date: day.date,
        reason: day.reason,
        schedule: reorderedStops,
      ));
    }
    final durations = <String, int>{};
    final targets = <String, int>{};
    for (final id in mustVisitIds) {
      final attraction = scoredById[id];
      if (attraction == null) continue;
      final destination = _destinationForPlace(request, attraction.place);
      final eligible = cleanedDays.where((d) =>
        _destinationForDay(request, d.dayIndex) == destination).toList();
      if (eligible.isEmpty) continue;
      final intended = plan.where((d) => d.placeIds.contains(id)).toList();
      final target = eligible.firstWhere(
        (d) => intended.any((p) => p.dayIndex == d.dayIndex),
        orElse: () => eligible.first);
      durations[id] = attraction.place.visitDurationMinutes ?? 60;
      targets[id] = target.dayIndex;
    }
    final retained = retainUnscheduledMustVisits(
      days: cleanedDays, durations: durations, targetDays: targets);
    for (final day in retained) {
      for (final stop in day.schedule.where((s) => s.startTime == '00:00' && s.endTime == '00:00')) {
        debugPrint('[MUST-VISIT RETAINED] ${stop.placeId} day=${day.dayIndex + 1} Unscheduled');
      }
    }
    return retained;
  }

  /// Dart-side schedule constructor. Given an ordered list of place IDs for
  /// one day, it computes:
  ///   • stopOrder (sequential)
  ///   • visitDuration (AI estimate when supplied, else category baseline;
  ///     both pace-adjusted and clamped to a sane range)
  ///   • travelFromPrevious (coordinate distance × transport speed)
  ///   • startTime / endTime (chained inside the exploration window)
  AIDaySchedule _constructDaySchedule({
    required int dayIndex,
    required DateTime date,
    required List<String> orderedPlaceIds,
    Map<String, int> aiVisitMinutes = const {},
    required String reason,
    required ExplorationWindow window,
    required String travelPace,
    required String transportation,
    required Map<String, ScoredAttraction> scoredById,
    required TripDraft request,
    required Set<String> globalUsedIds,
  }) {
    final winStart = window.startMinutes;
    final buffer = ItineraryConstants.bufferForPace(travelPace);
    final factor = ItineraryConstants.durationFactorForPace(travelPace);

    // ── Daily stop limit (pace-based, accommodating 3 meals + sights) ──────
    int maxStops;
    if (travelPace == 'Slow') {
      maxStops = 5; // Breakfast, Morning sight, Lunch, Afternoon sight, Dinner
    } else if (travelPace == 'Fast') {
      maxStops = 7; // Breakfast, 2 Morning sights, Lunch, Afternoon sight, Dinner, Nightlife
    } else {
      maxStops = 6; // Standard: Breakfast, Morning sight, Lunch, Afternoon sight, Dinner, (optional nightlife)
    }

    final stops = <AIScheduleStop>[];
    var cursor = winStart;
    Coordinates? prevCoord;

    // Categorize proposed places into:
    // 1. Genuine Sightseeing Attractions (museums, monuments, parks, nature, culture, landmarks)
    // 2. Dining / Food (restaurants, cafes, bakeries)
    // 3. Nightlife (bars, clubs, lounges)
    final attractionIds = <String>[];
    final foodIds = <String>[];
    final nightlifeIds = <String>[];

    for (final id in orderedPlaceIds) {
      final scored = scoredById[id];
      if (scored == null) continue;
      if (_isNightlifeScored(scored)) {
        nightlifeIds.add(id);
      } else if (_isFoodScored(scored)) {
        foodIds.add(id);
      } else {
        attractionIds.add(id);
      }
    }

    // Separate food into Breakfast (cafes/bakeries) and Lunch/Dinner (restaurants/dining)
    final breakfastCandidates = <String>[];
    final diningCandidates = <String>[];
    for (final id in foodIds) {
      final s = scoredById[id];
      if (s == null) continue;
      if (_isBreakfastScored(s)) {
        breakfastCandidates.add(id);
      } else {
        diningCandidates.add(id);
      }
    }

    // 1 breakfast cafe in the morning
    final dailyBreakfast = breakfastCandidates.take(1).toList();

    // 1 dining restaurant for midday lunch
    final dailyFood = diningCandidates.take(1).toList();

    // 1 dining restaurant for dinner
    final dailyDinner = diningCandidates.skip(1).take(1).toList();

    // Determine the exact destination allocated for this day
    final dayDestination = _destinationForDay(request, dayIndex);

    // ── GUARANTEED THREE MEALS (BREAKFAST, LUNCH, DINNER) ──
    final dayDestLower = dayDestination.trim().toLowerCase();

    // 1. Breakfast: morning cafe/bakery/kopitiam (09:00 - 10:00)
    if (dailyBreakfast.isEmpty) {
      // (a) First try unused breakfast in destination
      for (final entry in scoredById.entries) {
        final s = entry.value;
        if (!_isBreakfastScored(s)) continue;
        final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
        if (dest != dayDestLower) continue;
        if (globalUsedIds.contains(entry.key)) continue;
        dailyBreakfast.add(entry.key);
        globalUsedIds.add(entry.key);
        break;
      }
      // (b) Fallback: any unused food in destination
      if (dailyBreakfast.isEmpty) {
        for (final entry in scoredById.entries) {
          final s = entry.value;
          if (!_isFoodScored(s) || _isNightlifeScored(s)) continue;
          final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
          if (dest != dayDestLower) continue;
          if (globalUsedIds.contains(entry.key)) continue;
          dailyBreakfast.add(entry.key);
          globalUsedIds.add(entry.key);
          break;
        }
      }
    }

    // 2. Lunch: midday dining restaurant (12:00 - 13:30)
    if (dailyFood.isEmpty) {
      // (a) First try unused dining in destination (different from breakfast)
      for (final entry in scoredById.entries) {
        final s = entry.value;
        if (!_isDiningScored(s)) continue;
        final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
        if (dest != dayDestLower) continue;
        if (globalUsedIds.contains(entry.key) || dailyBreakfast.contains(entry.key)) continue;
        dailyFood.add(entry.key);
        globalUsedIds.add(entry.key);
        break;
      }
      // (b) Fallback: any unused food in destination
      if (dailyFood.isEmpty) {
        for (final entry in scoredById.entries) {
          final s = entry.value;
          if (!_isFoodScored(s) || _isNightlifeScored(s)) continue;
          final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
          if (dest != dayDestLower) continue;
          if (globalUsedIds.contains(entry.key) || dailyBreakfast.contains(entry.key)) continue;
          dailyFood.add(entry.key);
          globalUsedIds.add(entry.key);
          break;
        }
      }
    }

    // 3. Dinner: evening dining restaurant (18:00 - 20:00, different from lunch)
    if (dailyDinner.isEmpty) {
      // (a) First try unused dining in destination
      for (final entry in scoredById.entries) {
        final s = entry.value;
        if (!_isDiningScored(s)) continue;
        final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
        if (dest != dayDestLower) continue;
        if (globalUsedIds.contains(entry.key) ||
            dailyFood.contains(entry.key) ||
            dailyBreakfast.contains(entry.key)) {
          continue;
        }
        dailyDinner.add(entry.key);
        globalUsedIds.add(entry.key);
        break;
      }
      // (b) Fallback: any unused food in destination
      if (dailyDinner.isEmpty) {
        for (final entry in scoredById.entries) {
          final s = entry.value;
          if (!_isFoodScored(s) || _isNightlifeScored(s)) continue;
          final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
          if (dest != dayDestLower) continue;
          if (globalUsedIds.contains(entry.key) ||
              dailyFood.contains(entry.key) ||
              dailyBreakfast.contains(entry.key)) {
            continue;
          }
          dailyDinner.add(entry.key);
          globalUsedIds.add(entry.key);
          break;
        }
      }
    }

    // ── GUARANTEED NIGHTLIFE (OPTIONAL) ──
    final dailyNightlife = nightlifeIds.take(1).toList();
    final wantsNightlife = request.interests.any((i) =>
        i.toLowerCase().contains('night') || i.toLowerCase().contains('social'));
    if (wantsNightlife && dailyNightlife.isEmpty) {
      for (final entry in scoredById.entries) {
        final s = entry.value;
        if (!_isNightlifeScored(s)) continue;
        final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
        if (dest != dayDestLower) continue;
        if (globalUsedIds.contains(entry.key)) continue;
        dailyNightlife.add(entry.key);
        globalUsedIds.add(entry.key);
        break;
      }
    }

    // ── RELIGIOUS DIVERSITY & SIGHTSEEING SELECTION ──
    // Religious diversity: At most ONE mosque / temple / church per day!
    final diversifiedAttractionIds = <String>[];
    var hasReligious = false;
    for (final id in attractionIds) {
      final s = scoredById[id];
      if (s == null) continue;
      if (_isReligiousScored(s)) {
        if (hasReligious) continue; // Skip multiple religious places on the same day
        hasReligious = true;
      }
      diversifiedAttractionIds.add(id);
    }

    // Allow 2 daytime attractions (1 morning, 1 afternoon) for balanced pacing
    final allowedAttractions = travelPace == 'Slow' ? 2 : (travelPace == 'Fast' ? 3 : 2);

    // If needed, supplement secular attractions (museums, towers, parks)
    if (diversifiedAttractionIds.length < allowedAttractions) {
      for (final entry in scoredById.entries) {
        if (diversifiedAttractionIds.length >= allowedAttractions) break;
        final s = entry.value;
        if (_isNightlifeScored(s) || _isFoodScored(s)) continue;
        if (hasReligious && _isReligiousScored(s)) continue;
        if (diversifiedAttractionIds.contains(entry.key) ||
            orderedPlaceIds.contains(entry.key) ||
            globalUsedIds.contains(entry.key)) {
          continue;
        }
        final dest = _destinationForPlace(request, s.place).trim().toLowerCase();
        if (dest != dayDestLower) continue;
        if (_isReligiousScored(s)) hasReligious = true;
        diversifiedAttractionIds.add(entry.key);
        globalUsedIds.add(entry.key);
      }
    }

    final finalAttractionIds = diversifiedAttractionIds.take(allowedAttractions).toList();

    // ── Daily Flow with Geographical Proximity Ordering: ──
    // 1. Breakfast (09:00 - 10:00)
    // 2. Morning Sightseeing (10:15 - 11:45, nearest to breakfast)
    // 3. Midday Lunch (12:00 - 13:15, GUARANTEED)
    // 4. Afternoon Sightseeing (13:30 - 17:30, concluding by 17:45)
    // 5. Evening Dinner (18:00 - 19:30, GUARANTEED)
    // 6. Optional Nightlife (19:45 - 21:00)
    final sortedPlaceIds = <String>[];
    sortedPlaceIds.addAll(dailyBreakfast);

    final remainingSights = List<String>.from(finalAttractionIds);
    final morningSights = <String>[];
    Coordinates? currentCoord = dailyBreakfast.isNotEmpty
        ? scoredById[dailyBreakfast.first]?.place.coordinates
        : null;

    if (remainingSights.isNotEmpty) {
      final anchor = currentCoord;
      if (anchor != null) {
        remainingSights.sort((a, b) {
          final ca = scoredById[a]?.place.coordinates;
          final cb = scoredById[b]?.place.coordinates;
          if (ca == null || cb == null) return 0;
          return anchor.distanceTo(ca).compareTo(anchor.distanceTo(cb));
        });
      }
      final picked = remainingSights.removeAt(0);
      morningSights.add(picked);
      currentCoord = scoredById[picked]?.place.coordinates;
    }
    sortedPlaceIds.addAll(morningSights);

    // Lunch nearest to morning sight
    if (dailyFood.isNotEmpty) {
      sortedPlaceIds.addAll(dailyFood);
      currentCoord = scoredById[dailyFood.first]?.place.coordinates ?? currentCoord;
    }

    // Afternoon sights ordered by nearest neighbor from lunch
    final afternoonSights = <String>[];
    while (remainingSights.isNotEmpty) {
      final anchor = currentCoord;
      if (anchor != null) {
        remainingSights.sort((a, b) {
          final ca = scoredById[a]?.place.coordinates;
          final cb = scoredById[b]?.place.coordinates;
          if (ca == null || cb == null) return 0;
          return anchor.distanceTo(ca).compareTo(anchor.distanceTo(cb));
        });
      }
      final picked = remainingSights.removeAt(0);
      afternoonSights.add(picked);
      currentCoord = scoredById[picked]?.place.coordinates;
    }
    sortedPlaceIds.addAll(afternoonSights);

    final winEnd = window.endMinutes;

    // Evening dinner and optional nightlife as final stops
    if (dailyDinner.isNotEmpty) {
      sortedPlaceIds.addAll(dailyDinner);
    }
    if (dailyNightlife.isNotEmpty && winEnd > 1080) {
      sortedPlaceIds.addAll(dailyNightlife);
    }

    for (final placeId in sortedPlaceIds) {
      final isDinner = dailyDinner.contains(placeId);
      // NEVER drop dinner even if stops reached maxStops - 1!
      if (stops.length >= maxStops && !isDinner) break;

      final scored = scoredById[placeId];
      if (scored == null) continue; // filtered by structural validation

      final place = scored.place;
      final aiMinutes = aiVisitMinutes[placeId];
      final base = (aiMinutes != null && aiMinutes > 0)
          ? aiMinutes
          : (place.visitDurationMinutes ??
          ItineraryConstants.baseDurationForCategory(
              place.category, ItineraryConstants.defaultDurationMinutes));
      final duration = (base * factor)
          .round()
          .clamp(ItineraryConstants.minimumVisitDurationMinutes,
          ItineraryConstants.maximumVisitDurationMinutes);

      var travel = stops.isEmpty
          ? 0
          : _travelMinutes(
          prevCoord!, place.coordinates, transportation, buffer);
      if (travel > 60) {
        travel = 60; // Clamp intra-day travel to avoid breaking schedule on outlier coordinates
      }

      final isBreakfast = dailyBreakfast.contains(placeId) || _isBreakfastScored(scored);
      final isNightlife = dailyNightlife.contains(placeId) || _isNightlifeScored(scored);
      final isLunch = dailyFood.contains(placeId) || (_isDiningScored(scored) && !isDinner);
      final isMealOrNight = isBreakfast || isLunch || isDinner || isNightlife;

      // Skip nightlife completely if window ends at or before 18:00
      if (isNightlife && winEnd <= 1080) continue;

      var start = stops.isEmpty
          ? (isBreakfast ? 540 : winStart)
          : cursor + travel + buffer;

      // Realistic synchronized timing:
      // - Breakfast: 09:00 - 10:00
      // - Lunch: 12:00 - 13:30
      // - Dinner: within dinner window or before winEnd
      // - Nightlife: 20:00 - 21:30 (only if winEnd > 18:00)
      if (isBreakfast && stops.isEmpty) {
        start = 540; // 09:00 AM
      } else if (isNightlife) {
        const targetNightStart = 1200; // 20:00 PM (after dinner)
        if (start < targetNightStart) {
          start = targetNightStart;
        }
      } else if (isDinner) {
        final targetDinnerStart = winEnd <= 1080 ? (winEnd - 90).clamp(winStart, 1080) : 1080;
        if (start < targetDinnerStart) {
          start = targetDinnerStart;
        }
      } else if (isLunch) {
        const targetLunchStart = 720; // 12:00 PM (lunch window: 12:00 - 13:30)
        if (start < targetLunchStart) {
          start = targetLunchStart;
        }
      }

      var visitDuration = duration;
      var end = start + visitDuration;

      // Regular daytime sights conclude before dinner / by 17:45 or winEnd.
      // MUST-VISIT places and evening venues are allowed to extend up to 23:00 (1380 mins)
      // so the traveler's explicit must-go places are ALWAYS scheduled with concrete times!
      final isMustVisit = scored.isMustVisit || request.mustVisitPlaceIds.contains(placeId);
      final extendedWindowEnd = isMustVisit ? 1380 : (isMealOrNight ? (winEnd > 1260 ? winEnd : 1260) : winEnd);
      final daytimeEnd = winEnd < 1065 ? winEnd : 1065;
      final effectiveEnd = (isMealOrNight || isMustVisit) ? extendedWindowEnd : daytimeEnd;

      if (start >= effectiveEnd) {
        if (!isMealOrNight && !isMustVisit) continue;
        break;
      }

      if (end > effectiveEnd) {
        if (start + 30 <= effectiveEnd) {
          visitDuration = effectiveEnd - start;
          end = effectiveEnd;
        } else {
          // Cannot fit before window ends: never spill into next day or past window
          if (!isMealOrNight && !isMustVisit) continue;
          break;
        }
      }

      String stopScheduleReason;
      if (isBreakfast) {
        stopScheduleReason = 'Morning breakfast: Start your morning with local coffee, traditional breakfast delights, and a relaxed atmosphere.';
      } else if (isLunch) {
        stopScheduleReason = 'Midday dining: Savor authentic regional lunch specialties, signature local dishes, and vibrant flavors.';
      } else if (isDinner) {
        stopScheduleReason = 'Evening dinner: Enjoy a delicious local dinner, renowned culinary delights, and a vibrant evening dining ambiance.';
      } else if (isNightlife) {
        stopScheduleReason = 'Evening wind-down: Experience panoramic skyline views, signature refreshments, and ambient social vibes.';
      } else if (_isReligiousScored(scored)) {
        stopScheduleReason = 'Cultural heritage: Discover historical architecture, sacred artistry, and profound local traditions.';
      } else {
        stopScheduleReason = 'Must-visit highlight: Explore iconic landmarks, picturesque photo spots, and immersive local culture.';
      }

      stops.add(AIScheduleStop(
        stopOrder: stops.length + 1,
        placeId: placeId,
        startTime: _hhmm(start),
        endTime: _hhmm(end),
        visitDurationMinutes: visitDuration,
        travelFromPreviousMinutes: travel,
        scheduleReason: stopScheduleReason,
        weatherNote: '',
      ));
      cursor = end;
      prevCoord = place.coordinates;
    }

    return AIDaySchedule(
      dayIndex: dayIndex,
      date: date.toIso8601String().split('T').first,
      schedule: stops,
      warnings: [if (reason.isNotEmpty) reason],
      reason: reason,
    );
  }

  /// Deterministic travel time (minutes) between two coordinates using the
  /// transport mode. Accounts for actual road winding (1.35x) and realistic
  /// wait / walking buffer for public transit.
  int _travelMinutes(
      Coordinates a, Coordinates b, String transportation, int fallback) {
    final distanceKm = a.distanceTo(b);
    if (distanceKm <= 0.05) return fallback;

    final roadKm = distanceKm * 1.35;
    final mode = transportation.toLowerCase();
    int minutes;
    if (mode.contains('car') || mode.contains('driving') || mode.contains('drive')) {
      minutes = (roadKm / 35.0 * 60).ceil() + 5;
    } else if (mode.contains('transit') ||
        mode.contains('ktm') ||
        mode.contains('lrt') ||
        mode.contains('mrt') ||
        mode.contains('bus') ||
        mode.contains('train')) {
      minutes = (roadKm / 22.0 * 60).ceil() + 10;
    } else if (mode.contains('cycling') || mode.contains('bike')) {
      minutes = (roadKm / 12.0 * 60).ceil();
    } else {
      minutes = (roadKm / 4.5 * 60).ceil(); // walking
    }
    return minutes < 1 ? fallback : minutes;
  }

  /// Deterministic fallback planner. Builds a complete compact plan from
  /// scored candidates, must-visits, clusters and travel preferences when
  /// the AI is unavailable or returns an invalid response.
  List<AiCompactPlanDay> _buildDeterministicPlan({
    required TripDraft request,
    required List<ScoredAttraction> scored,
    required List<String> mustVisitIds,
  }) {
    final mustSet = mustVisitIds.where((m) => m.isNotEmpty).toSet();

    String dayDest(int dayIndex) => _destinationForDay(request, dayIndex);

    final byDest = <String, List<ScoredAttraction>>{};
    for (final s in scored) {
      (byDest[_destinationForPlace(request, s.place)] ??= []).add(s);
    }

    final used = <String>{};
    final dayPlaces = <int, List<ScoredAttraction>>{};

    // 1. Must-visits → first day of their destination.
    for (final s in scored) {
      if (!mustSet.contains(s.place.placeId)) continue;
      final dest = _destinationForPlace(request, s.place);
      for (var day = 0; day < request.totalDays; day++) {
        if (dayDest(day) == dest) {
          (dayPlaces[day] ??= []).add(s);
          used.add(s.place.placeId);
          break;
        }
      }
    }

    // 2. Fill slots per day by destination + score.
    const paceTarget = {'Slow': 3, 'Standard': 4, 'Fast': 5};
    final target = paceTarget[request.pace] ?? 4;
    final wantsNightlife = request.interests.any((i) =>
        i.toLowerCase().contains('night') || i.toLowerCase().contains('social'));

    for (var day = 0; day < request.totalDays; day++) {
      final dest = dayDest(day);
      final pool = List<ScoredAttraction>.of(byDest[dest] ?? const [])
        ..sort((a, b) => b.score.compareTo(a.score));
      final list = dayPlaces[day] ??= [];

      // (A) Core daytime attractions (museums, nature, towers, culture)
      // Enforce diversity: at most ONE religious place per day!
      final minDaytime = wantsNightlife ? (target - 2).clamp(1, 3) : (target - 1).clamp(2, 4);
      for (final s in pool) {
        if (list.length >= minDaytime) break;
        if (used.contains(s.place.placeId)) continue;
        if (_isFoodScored(s) || _isNightlifeScored(s)) continue;
        if (_isReligiousScored(s) && list.any(_isReligiousScored)) continue; // Max 1 temple/church/mosque
        list.add(s);
        used.add(s.place.placeId);
      }

      // (B) Exactly one dining / food stop for lunch
      for (final s in pool) {
        if (used.contains(s.place.placeId)) continue;
        if (!_isFoodScored(s) || _isNightlifeScored(s)) continue;
        list.add(s);
        used.add(s.place.placeId);
        break;
      }

      // (C) Guaranteed Nightlife: 1 evening nightlife venue per day when traveler wants nightlife
      if (wantsNightlife) {
        for (final s in pool) {
          if (used.contains(s.place.placeId)) continue;
          if (!_isNightlifeScored(s)) continue;
          list.add(s);
          used.add(s.place.placeId);
          break;
        }
      }

      // (D) If still under target, top up with more daytime ATTRACTIONS ONLY (never extra meals!)
      for (final s in pool) {
        if (list.length >= target) break;
        if (used.contains(s.place.placeId)) continue;
        if (_isFoodScored(s) || _isNightlifeScored(s)) continue; // ONLY real attractions!
        if (_isReligiousScored(s) && list.any(_isReligiousScored)) continue;
        list.add(s);
        used.add(s.place.placeId);
      }

      // (E) Safety guarantee: If daytime attractions are fewer than 2, borrow from the destination pool first!
      final attractionCount = list.where((s) => !_isFoodScored(s) && !_isNightlifeScored(s)).length;
      if (attractionCount < 2) {
        // First try unplaced attractions in the same destination pool
        for (final s in pool) {
          if (list.length >= target) break;
          if (used.contains(s.place.placeId)) continue;
          if (_isNightlifeScored(s) || _isFoodScored(s)) continue;
          if (_isReligiousScored(s) && list.any(_isReligiousScored)) continue;
          list.add(s);
          used.add(s.place.placeId);
        }
        // If still under target, borrow from places in the same destination across all scored
        if (list.length < target) {
          for (final s in scored) {
            if (list.length >= target) break;
            if (used.contains(s.place.placeId)) continue;
            if (_destinationForPlace(request, s.place) != dest) continue; // NEVER borrow across cities!
            if (_isNightlifeScored(s) || _isFoodScored(s)) continue;
            if (_isReligiousScored(s) && list.any(_isReligiousScored)) continue;
            list.add(s);
            used.add(s.place.placeId);
          }
        }
      }

      // (F) Long-trip guarantee (e.g. 7-10 days in single city):
      // Top up from any remaining unused places in destination pool
      if (list.length < target) {
        for (final s in pool) {
          if (list.length >= target) break;
          if (used.contains(s.place.placeId)) continue; // STRICTLY NO DUPLICATES
          if (_isReligiousScored(s) && list.any(_isReligiousScored)) continue;
          list.add(s);
          used.add(s.place.placeId);
        }
      }
    }

    // 3. Logical daily flow:
    //    Morning Attractions (1-2) → Midday Lunch (1) → Afternoon Attractions (1-2) → Evening Nightlife (max 1)
    return [
      for (var day = 0; day < request.totalDays; day++)
        AiCompactPlanDay(
          dayIndex: day,
          placeIds: () {
            final all = dayPlaces[day] ?? const [];
            final attractions = all.where((s) => !_isFoodScored(s) && !_isNightlifeScored(s)).toList();
            final food = all.where((s) => _isFoodScored(s) && !_isNightlifeScored(s)).toList();
            final nightlife = all.where((s) => _isNightlifeScored(s)).toList();

            // Safety guard: if attractions is empty, borrow from scored pool
            if (attractions.isEmpty) {
              final dest = dayDest(day);
              final fallback = (byDest[dest] ?? scored)
                  .where((s) => !_isFoodScored(s) && !_isNightlifeScored(s) && !used.contains(s.place.placeId))
                  .take(3)
                  .toList();
              for (final f in fallback) {
                used.add(f.place.placeId);
              }
              attractions.addAll(fallback);
            }

            final orderedAttractions = _orderByProximity(attractions);
            final dayStops = <ScoredAttraction>[];

            // 1. Morning Sightseeing (1 to 2 attractions)
            if (orderedAttractions.isNotEmpty) {
              dayStops.add(orderedAttractions.removeAt(0));
            }
            if (orderedAttractions.length >= 2) {
              dayStops.add(orderedAttractions.removeAt(0));
            }

            // 2. Midday Lunch (EXACTLY ONE meal!)
            if (food.isNotEmpty) {
              dayStops.add(food.first);
            }

            // 3. Afternoon Sightseeing / Culture / Shopping
            dayStops.addAll(orderedAttractions);

            // 4. Evening Nightlife (at most 1, at the end of the day)
            dayStops.addAll(nightlife.take(1));

            return dayStops.map((s) => s.place.placeId).toList();
          }(),
          reason: 'Balanced schedule: morning sightseeing, midday lunch, afternoon exploration.',
        ),
    ];
  }

  /// Greedy nearest-neighbour ordering: start from the first place, then
  /// repeatedly pick the still-unplaced attraction closest to the last one.
  List<ScoredAttraction> _orderByProximity(List<ScoredAttraction> places) {
    if (places.length <= 2) return List.of(places);
    final remaining = List<ScoredAttraction>.of(places);
    final ordered = <ScoredAttraction>[remaining.removeAt(0)];
    while (remaining.isNotEmpty) {
      final last = ordered.last.place.coordinates;
      var bestIdx = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final d = last.distanceTo(remaining[i].place.coordinates);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      ordered.add(remaining.removeAt(bestIdx));
    }
    return ordered;
  }

  AiValidationResult _validateSchedule({
    required List<AIDaySchedule> aiDays,
    required TripDraft request,
    required Set<String> knownPlaceIds,
    required List<String> mustVisitIds,
    Map<String, String>? placeIdToDestination,
  }) {
    return _validator.validate(
      days: aiDays,
      unscheduledPlaceIds: mustVisitIds.toSet(),
      knownPlaceIds: knownPlaceIds,
      mustVisitIds: mustVisitIds,
      totalDays: request.totalDays,
      explorationTime: request.exploration ?? 'Standard',
      destinationOrder: request.destinationNames,
      allocatedDaysPerDestination: _allocationFor(request),
      placeIdToDestination: placeIdToDestination,
    );
  }

  /// Day-per-destination allocation: the user's explicit [TripDraft.daySplit]
  /// when provided, otherwise an even split across destinations (matching
  /// what the AI prompt tells DeepSeek to assume).
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

  /// Builds the compact candidate pool handed to DeepSeek.
  ///
  /// Dart has already filtered, scored and clustered the full pool. This
  /// selects a SMALL (~12–20) high-quality subset for the AI prompt while
  /// strictly preserving everything needed for a COMPLETE itinerary:
  ///
  ///   1. MUST-VISITS are always retained (hard requirement).
  ///   2. The target size is derived from trip length via [targetCandidateCount].
  ///   3. Every destination keeps enough top-scored candidates to fill its
  ///      allocated days.
  ///   4. Each destination keeps at least one food option for meals.
  ///   5. Every geographic cluster keeps a representative so the AI can
  ///      reason about proximity instead of hopping between distant places.
  ///
  /// It is NOT a naive `take(n)` — coverage is guaranteed per destination,
  /// per meal and per cluster.
  List<ScoredAttraction> _selectAICandidates({
    required List<ScoredAttraction> scored,
    required TripDraft request,
    required List<Cluster> clusters,
  }) {
    final allocation = _allocationFor(request);
    final target = targetCandidateCount(request.totalDays);
    final selected = <ScoredAttraction>[];
    final selectedIds = <String>{};

    void add(ScoredAttraction s) {
      if (selectedIds.add(s.place.placeId)) selected.add(s);
    }

    // 1. Must-visits ALWAYS retained.
    final mustVisitIds = request.mustVisitPlaceIds.toSet();
    for (final s in scored) {
      if (s.isMustVisit || mustVisitIds.contains(s.place.placeId)) add(s);
    }

    // Group the remaining candidates by destination (score order kept).
    final byDest = <String, List<ScoredAttraction>>{};
    for (final s in scored) {
      if (selectedIds.contains(s.place.placeId)) continue;
      final dest = _destinationForPlace(request, s.place);
      (byDest[dest] ??= []).add(s);
    }

    // 2. Per-destination allowance proportional to its allocated days.
    final totalDays = request.totalDays < 1 ? 1 : request.totalDays;
    final destQuota = <String, int>{
      for (final entry in byDest.entries)
        entry.key: ((target * (allocation[entry.key] ?? 1)) /
            totalDays)
            .ceil(),
    };

    // ─── NEW: ENSURE EACH DESTINATION GETS ENOUGH CANDIDATES TO FILL TARGET STOPS PER DAY ───
    final pace = request.pace ?? 'Standard';
    int targetStopsPerDay;
    switch (pace) {
      case 'Slow':
        targetStopsPerDay = 3;
        break;
      case 'Fast':
        targetStopsPerDay = 5;
        break;
      default:
        targetStopsPerDay = 4; // Standard
    }
    // Clamp to sensible range
    if (targetStopsPerDay > 5) targetStopsPerDay = 5;
    if (targetStopsPerDay < 2) targetStopsPerDay = 2;

    for (final entry in byDest.entries) {
      final daysForDest = allocation[entry.key] ?? 1;
      final minNeeded = targetStopsPerDay * daysForDest;
      if (destQuota[entry.key]! < minNeeded) {
        destQuota[entry.key] = minNeeded;
      }
    }

    // 3. Per destination: ensure rich daytime sightseeing, balanced food, and at most 1 nightlife
    for (final entry in byDest.entries) {
      final daysForDest = allocation[entry.key] ?? 1;

      // (A) GUARANTEED DAYTIME SIGHTSEEING (Landmarks, museums, nature, culture)
      // Must NOT be food and must NOT be nightlife!
      // Enforce diversity: limit religious buildings to at most 1 per planned day
      var daytimeQuota = daysForDest * 3;
      var religiousCount = 0;
      for (final s in entry.value) {
        if (daytimeQuota <= 0) break;
        if (_isFoodScored(s) || _isNightlifeScored(s)) continue;
        if (_isReligiousScored(s)) {
          if (religiousCount >= daysForDest) continue;
          religiousCount++;
        }
        add(s);
        daytimeQuota--;
      }

      // (B) FOOD & DINING OPTIONS: Provide at least 3 dining options per day for lunch & dinner
      var diningQuota = daysForDest * 3;
      for (final s in entry.value) {
        if (diningQuota <= 0) break;
        if (!_isDiningScored(s)) continue;
        add(s);
        diningQuota--;
      }

      // (C) BREAKFAST & CAFES: Provide at least 1-2 breakfast / coffee spots per day
      var breakfastQuota = daysForDest * 2;
      for (final s in entry.value) {
        if (breakfastQuota <= 0) break;
        if (!_isBreakfastScored(s)) continue;
        add(s);
        breakfastQuota--;
      }

      // (D) OPTIONAL NIGHTLIFE: Up to 2 nightlife options per planned day
      final wantsNightlife = request.interests.any((i) =>
          i.toLowerCase().contains('night') || i.toLowerCase().contains('social'));
      if (wantsNightlife) {
        var nightlifeQuota = daysForDest * 2;
        for (final s in entry.value) {
          if (nightlifeQuota <= 0) break;
          if (!_isNightlifeScored(s)) continue;
          add(s);
          nightlifeQuota--;
        }
      }

      // (D) Fill remainder with top daytime attractions (NEVER extra food or nightlife)
      for (final s in entry.value) {
        if (selected.length >= target) break;
        if (selectedIds.contains(s.place.placeId)) continue;
        if (_isNightlifeScored(s) || _isFoodScored(s)) continue; // ONLY real attractions!
        add(s);
      }
    }

    // 5. Geographic diversity: every cluster keeps at least one candidate.
    for (final cluster in clusters) {
      if (selected.length >= target) break;
      final represented = cluster.attractions
          .any((a) => selectedIds.contains(a.place.placeId));
      if (represented) continue;
      ScoredAttraction? best;
      for (final a in cluster.attractions) {
        if (selectedIds.contains(a.place.placeId)) continue;
        if (best == null || a.score > best.score) best = a;
      }
      if (best != null) add(best);
    }

    // 6. Safety floor: top the pool back up with the highest-scored places (preferring daytime).
    if (selected.length < minAiCandidatePool) {
      final sorted = List<ScoredAttraction>.from(scored)
        ..sort((a, b) => b.score.compareTo(a.score));
      for (final s in sorted) {
        if (selected.length >= target) break;
        if (selected.length >= minAiCandidatePool) break;
        if (selectedIds.contains(s.place.placeId)) continue;
        if (_isNightlifeScored(s) && selected.where(_isNightlifeScored).length >= request.totalDays) continue;
        if (_isFoodScored(s) && selected.where(_isFoodScored).length >= request.totalDays * 4) continue;
        add(s);
      }
    }

    return selected;
  }

  /// Whether a scored candidate is a food/drink place.
  bool _isFoodScored(ScoredAttraction s) {
    final types = s.place.types.map((t) => t.toLowerCase()).toSet();
    if (types.any(CandidateRetrievalService.foodTypes.contains)) return true;
    final cat = (s.place.category ?? '').toLowerCase();
    return cat.contains('food') ||
        cat.contains('restaurant') ||
        cat.contains('cafe') ||
        cat.contains('bakery') ||
        cat.contains('dining');
  }

  /// Whether a scored candidate is a nightlife venue (bar, club, pub, etc.).
  bool _isNightlifeScored(ScoredAttraction s) {
    final types = s.place.types.map((t) => t.toLowerCase()).toSet();
    if (types.contains('night_club') ||
        types.contains('bar') ||
        types.contains('casino') ||
        types.contains('wine_bar') ||
        types.contains('liquor_store')) {
      return true;
    }
    final cat = (s.place.category ?? '').toLowerCase();
    return cat.contains('nightlife') || cat.contains('bar') || cat.contains('club');
  }

  /// Whether a scored candidate is a place of worship (mosque, temple, church, etc.).
  bool _isReligiousScored(ScoredAttraction s) {
    final types = s.place.types.map((t) => t.toLowerCase()).toSet();
    return types.any((t) => const {
      'place_of_worship', 'hindu_temple', 'church', 'mosque', 'synagogue'
    }.contains(t));
  }

  /// Whether a scored candidate is a breakfast / morning cafe / bakery / kopitiam.
  bool _isBreakfastScored(ScoredAttraction s) {
    if (_isNightlifeScored(s)) return false;
    final types = s.place.types.map((t) => t.toLowerCase()).toSet();
    if (types.contains('cafe') || types.contains('bakery') || types.contains('coffee_shop')) return true;
    final cat = (s.place.category ?? '').toLowerCase();
    final name = s.place.placeName.toLowerCase();
    return cat.contains('cafe') ||
        cat.contains('bakery') ||
        cat.contains('breakfast') ||
        cat.contains('coffee') ||
        name.contains('cafe') ||
        name.contains('kopitiam') ||
        name.contains('kopi') ||
        name.contains('toast') ||
        name.contains('breakfast') ||
        name.contains('dim sum') ||
        name.contains('noodle') ||
        name.contains('roti') ||
        name.contains('tea');
  }

  /// Whether a scored candidate is an authentic dining / lunch / dinner restaurant
  /// (strictly excluding bakeries, dessert shops, ice cream parlors, bubble tea, etc.).
  bool _isDiningScored(ScoredAttraction s) {
    if (_isNightlifeScored(s)) return false;
    final types = s.place.types.map((t) => t.toLowerCase()).toSet();
    final name = s.place.placeName.toLowerCase();
    final cat = (s.place.category ?? '').toLowerCase();

    // Strictly exclude dessert, sweets, bakery, ice cream from lunch/dinner dining
    final isDessert = types.contains('bakery') ||
        types.contains('dessert_shop') ||
        types.contains('ice_cream_shop') ||
        name.contains('dessert') ||
        name.contains('ice cream') ||
        name.contains('gelato') ||
        name.contains('bingsu') ||
        name.contains('cendol') ||
        name.contains('cake') ||
        name.contains('waffle') ||
        name.contains('pastry') ||
        name.contains('sweet') ||
        name.contains('bubble tea') ||
        name.contains('boba') ||
        name.contains('tea house') ||
        cat.contains('dessert') ||
        cat.contains('bakery');
    if (isDessert) return false;

    if (types.contains('restaurant') || types.contains('meal_takeaway')) return true;
    return cat.contains('restaurant') || cat.contains('dining') || cat.contains('food');
  }

  /// Time remaining before [deadline], clamped to zero.
  Duration _remainingTime(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _hhmm(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).clamp(0, 23).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).clamp(0, 59).toString().padLeft(2, '0');
    return '$h:$m';
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

      // Every requested day MUST be preserved in the final model, even when
      // it has zero stops (e.g. a 3-day trip must always yield 3 days). This
      // prevents an empty day from silently shrinking the itinerary.
      result.add(normalizeProposedDay(ScheduledDay(
        dayIndex: day.dayIndex,
        date: date,
        stops: stops,
        totalDuration:
        stops.fold<int>(0, (sum, s) => sum + s.durationMinutes),
        totalTravelTime:
        stops.fold<double>(0, (sum, s) => sum + s.travelFromPreviousMinutes),
        reason: day.reason,
      ), request.exploration ?? 'Standard'));
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
    return best ?? (request.destinationNames.isNotEmpty ? request.destinationNames.first : 'Unknown');
  }

  String _destinationForDay(TripDraft request, int dayIndex) {
    final allocation = _allocationFor(request);
    var counter = 0;
    for (final name in request.destinationNames) {
      final days = (allocation[name] ?? 1).clamp(1, 14);
      for (var d = 0; d < days; d++) {
        if (counter == dayIndex) return name;
        counter++;
      }
    }
    return request.destinationNames.isNotEmpty ? request.destinationNames.first : '';
  }

  // ============================================================
  // NEW: Weather extraction function
  // ============================================================

  /// Fetches the weather forecast for the trip's location and dates.
  /// Returns an empty forecast if coordinates or dates are unavailable,
  /// or if the network request fails.
  Future<WeatherForecast> _fetchWeatherForTrip(
      Coordinates? coord,
      DateTime startDate,
      DateTime endDate,
      ) async {
    try {
      if (coord != null) {
        return await _weather.getDailyForecast(
          latitude: coord.latitude,
          longitude: coord.longitude,
          startDate: startDate,
          endDate: endDate,
        );
      }
    } catch (e) {
      debugPrint('[WEATHER] Fetch failed: $e');
    }
    return WeatherForecast(daily: []);
  }
}
