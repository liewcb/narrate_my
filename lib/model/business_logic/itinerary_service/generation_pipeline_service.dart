import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/weather_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import '../../entities/trip_draft.dart';
import '../../entities/weather.dart';
import './ai_prompt_builder.dart';
import 'candidate_diversity.dart';
import '../../data_sources/remote/places_remote_data_source.dart';
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
///   Build AI context → AI planner → Validate → (regenerate) → Save.
///
/// AI planner is responsible for context-aware scheduling. Flutter remains
/// responsible for retrieval, filtering, scoring, clustering, hard
/// constraints, validation and persistence.
class ItineraryGenerationPipeline {
  static const int maxRegenerationAttempts = 3;

  /// Candidate alternatives scale with trip length; must-visits are never cut.
  static int targetCandidateCount(int tripDays) =>
      ItineraryConstants.planningPoolSize(tripDays);

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
        _aiService = aiService ?? AIService();

  Future<ItineraryResult> generate({
    required TripDraft request,
    required void Function(String) onProgress,
    Coordinates? tripLocation,
  }) async {
    final effectivePace = request.pace ?? 'Standard';
    final effectiveExploration = request.exploration ?? 'Standard';

    final pipelineStopwatch = Stopwatch()..start();
    // Network stages share one deadline: 10s discovery, up to 18s AI,
    // with 2s reserved for local scheduling and optional weather.
    final generationStart = DateTime.now();
    final globalDeadline = generationStart.add(const Duration(seconds: 30));
    final preprocessingDeadline =
    generationStart.add(const Duration(seconds: 10));

    Duration remainingPreprocessing() =>
        _remainingTime(preprocessingDeadline);
    var expansionAttempted = false;

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
    if (request.totalDays < 1 ||
        request.totalDays > 7 ||
        (request.startDate != null &&
            request.endDate != null &&
            request.endDate!.isBefore(request.startDate!))) {
      return ItineraryResult.error(
        travelerMessage: 'Trip duration must be between 1 and 7 days.',
      );
    }

    final allocation = _allocationFor(request);
    if (allocation.values.any((days) => days < 1 || days > 7) ||
        allocation.keys
            .toSet()
            .difference(request.destinationNames.toSet())
            .isNotEmpty ||
        request.destinationNames.any((name) => !allocation.containsKey(name)) ||
        allocation.values.fold<int>(0, (sum, days) => sum + days) !=
            request.totalDays) {
      return ItineraryResult.error(
        travelerMessage: 'Allocate all trip days to the selected destinations.',
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
      onProgress('Finding attractions... (1/9)');
      final retrievalSw = Stopwatch()..start();
      CandidatePool candidatePool;
      try {
        // Retrieval is the slow part of preprocessing (Google Places
        // network calls) — it is bounded by the 10s preprocessing deadline so
        // a slow network can never push the AI stage out of its window.
        candidatePool = await _candidateRetrieval
            .retrieveCandidates(request: request,
            )
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
      if (request.mustVisitPlaceIds.isEmpty &&
          (rawCount < retrievalTarget ||
              candidatePool.foodCount < request.totalDays * 2) &&
          remainingPreprocessing() > const Duration(seconds: 2)) {
        debugPrint('Status: RAW CANDIDATES INSUFFICIENT → EXPANDING');
        debugPrint('[STAGE 07B - CANDIDATE EXPANSION]');
        debugPrint('Reason: $rawCount < $retrievalTarget');
        debugPrint('Previous count: $rawCount');
        debugPrint('Search strategy: radius × ${ItineraryConstants.expansionMultiplier}');

        expansionAttempted = true;

        final expanded = await _candidateRetrieval.expandCandidates(
          request: request,
          alreadySeenIds: registry.placeIds,
          radiusMultiplier: ItineraryConstants.expansionMultiplier,
            )
            .timeout(
              remainingPreprocessing(),
              onTimeout: () => const CandidatePool(attractions: [], food: []),
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
        // Hard 10s preprocessing budget: must-visit recovery needs network
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
      onProgress('Filtering candidates...');
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
      if (!expansionAttempted &&
          (usableCount < usableTarget ||
              candidatePool.foodCount < request.totalDays * 2) &&
          remainingPreprocessing() > const Duration(seconds: 2)) {
        debugPrint('Status: USABLE CANDIDATES INSUFFICIENT → EXPANDING');
        debugPrint('[STAGE 10B - CANDIDATE EXPANSION]');
        debugPrint('Reason: $usableCount < $usableTarget');
        debugPrint('Previous count: $usableCount');

        expansionAttempted = true;
        final expanded = await _candidateRetrieval.expandCandidates(
          request: request,
          alreadySeenIds: registry.placeIds,
          radiusMultiplier: ItineraryConstants.expansionMultiplier,
            )
            .timeout(
              remainingPreprocessing(),
              onTimeout: () => const CandidatePool(attractions: [], food: []),
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

      final scoringSw = Stopwatch()..start();
      var scored = _scoring.scorePlaces(
        places: allPlaces,
        selectedInterests: request.interests.toList(),
        mustVisitIds: effectiveMustVisitIds,
        explorationTime: effectiveExploration,
        tripLocation: tripLocation,
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
      onProgress('Grouping by location... (4/9)');
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
      onProgress('Building AI context... (5/9)');
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
          destination: _destinationForPlace(request, place),
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

      final prompt = _promptBuilder.buildCompactPlanPrompt(
        request: request,
        candidates: candidates,
        clusters: aiClusters,
        mustVisitIds: effectiveMustVisitIds,
      );

      debugPrint('[STAGE 13 - AI PLANNER INPUT]');
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
      // There is exactly ONE global 30s deadline for the whole AI planning
      // operation (safety margin including the postprocessing reserve). It is never
      // reset: a timeout or invalid response goes straight to the
      // deterministic planner — NO second AI request.
      onProgress('Creating schedule... (7/9)');
      final plannerSw = Stopwatch()..start();

      // ── [DART PREPROCESSING] summary ────────────────────────────
      final preprocessingMs = pipelineStopwatch.elapsedMilliseconds;
      final preprocessingStatus =
      remainingPreprocessing() <= Duration.zero ? 'TIMEOUT' : 'SUCCESS';
      debugPrint('[DART PREPROCESSING]');
      debugPrint('retrieved=$rawCount');
      debugPrint('scored=${scored.length}');
      debugPrint('clusters=${clusters.length}');
      debugPrint('reduced=${candidates.length}');
      debugPrint('elapsedMs=$preprocessingMs');
      debugPrint('status=$preprocessingStatus');

      final latestAiDeadline = globalDeadline.subtract(
        const Duration(seconds: 2),
      );
      final remainingAi = _remainingTime(latestAiDeadline);
      final aiDuration = remainingAi > const Duration(seconds: 18)
          ? const Duration(seconds: 18)
          : remainingAi;
      final aiDeadline = DateTime.now().add(aiDuration);

      debugPrint('[AI PLANNER] AI deadline: ${aiDuration.inMilliseconds} ms from now',
      );
      debugPrint('[AI PLANNER] PROVIDER: B.AI');
      debugPrint('[AI PLANNER] MODEL: ${_aiService.baiModel}');
      debugPrint('[AI PLANNER] START');
      debugPrint('[AI PLANNER] Candidates: ${candidates.length}');
      debugPrint('[AI PLANNER] Prompt: ${prompt.length} chars');
      debugPrint('[AI PLANNER] AI deadline: '
          '${aiDeadline.difference(DateTime.now()).inMilliseconds} ms from now');

      // AI must only reference place IDs that survived scoring.
      final scoredPlaceIds = scored.map((s) => s.place.placeId).toSet();

      // 1. ONE AI recommendation attempt within the global deadline.
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
        knownIds: aiCandidateIds,
              scored: scored,
        mustVisitIds: effectiveMustVisitIds,
        placeIdToDestination: placeIdToDestination,
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
          foodPlaceIds: scored
              .where(_isFoodScored)
              .map((s) => s.place.placeId)
              .toSet(),
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
          foodPlaceIds: scored
              .where(_isFoodScored)
              .map((s) => s.place.placeId)
              .toSet(),
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
      onProgress('Validating... (8/9)');
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
      // ============================================================
      //
      // The travel plan is complete at this point. Weather is fetched from
      // Open-Meteo (a free, fast API). There is deliberately NO AI critic
      // call here: another LLM request would keep running asynchronously
      // after PIPELINE COMPLETE, wasting ~15–35s of background work and
      // misleading the timing logs. All validation (duplicates, windows,
      // chronology, must-visits, place IDs, travel/duration) is performed
      // deterministically by Dart already.

      // Extract coordinates from the first stop, if available.
      Coordinates? firstCoord;
      if (scheduledDays.isNotEmpty && scheduledDays.first.stops.isNotEmpty) {
        firstCoord = scheduledDays.first.stops.first.attraction.place.coordinates;
      }
      final startDate = request.startDate ?? DateTime.now();
      final endDate = request.endDate ??
          startDate.add(Duration(days: request.totalDays));
      final weather = await _fetchWeatherForTrip(
        firstCoord,
        startDate,
        endDate,
        _remainingTime(globalDeadline),
      );
      final List<String> unretrievable = const [];
      final critic = const CriticResult(
        overallSuitable: true,
        score: 0,
        issues: [],
        recommendations: [],
        summary: 'AI feedback unavailable.',
      );

      // 5. DIAGNOSTIC SUMMARY
      onProgress('Finalizing your itinerary...');
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

      return ItineraryResult.success(
          scheduledDays: scheduledDays,
          weather: weather,
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

  /// ONE configured provider recommendation attempt within the [deadline].
  ///
  /// B.AI / GLM is called once. Returns the parsed plan, a status string
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

    PlannerRecommendation outcome;
    try {
      outcome = await _aiService.generatePlannerRecommendation(
      prompt,
      deadline: deadline,
    )
          .timeout(remaining);
    } on TimeoutException {
      return (
        plan: null,
        status: 'AI_TIMEOUT',
        attempts: <ProviderAiAttempt>[],
      );
    } catch (_) {
      return (
        plan: null,
        status: 'AI_PROVIDER_ERROR',
        attempts: <ProviderAiAttempt>[],
      );
    }

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

  /// Repair day allocation, duplicate IDs, must-visits, meals and distribution.
  /// Retain supplied AI preferences when filling each day's optional slots.
  /// The same routine builds the deterministic fallback from an empty plan.
  List<AiCompactPlanDay>? _repairPlan({
    required List<AiCompactPlanDay> plan,
    required TripDraft request,
    required Set<String> knownIds,
    required List<ScoredAttraction> scored,
    required List<String> mustVisitIds,
    required Map<String, String> placeIdToDestination,
  }) {
    final allocation = _allocationFor(request);
    final destinations = [
      for (final name in request.destinationNames)
        for (var i = 0; i < (allocation[name] ?? 0); i++) name,
    ];
    if (destinations.length != request.totalDays) return null;
    final byId = {for (final s in scored) s.place.placeId: s};
    final lists = List.generate(request.totalDays, (_) => <ScoredAttraction>[]);
    final used = <String>{};
    final target = ItineraryConstants.stopsPerDay(request.pace);
    final must = mustVisitIds.toSet();
    bool add(int day, ScoredAttraction s) {
      if (!used.add(s.place.placeId)) return false;
      lists[day].add(s);
      return true;
    }

    // Spread mandatory stops before reserving meals and optional attractions.
    for (final id in must) {
      final s = byId[id];
      if (s == null) return null;
      final eligible = [
        for (var d = 0; d < lists.length; d++)
          if (destinations[d] == placeIdToDestination[id]) d,
      ];
      if (eligible.isEmpty) return null;
      eligible.sort((a, b) => lists[a].length.compareTo(lists[b].length));
      add(eligible.first, s);
    }
    final ranked = List<ScoredAttraction>.of(scored)
      ..sort((a, b) => b.score.compareTo(a.score));
      for (var d = 0; d < lists.length; d++) {
        if (lists[d].any(_isFoodScored)) continue;
      final food = ranked.where(
        (s) =>
            _isFoodScored(s) &&
            !used.contains(s.place.placeId) &&
            placeIdToDestination[s.place.placeId] == destinations[d],
      );
      if (food.isNotEmpty && lists[d].length < target) add(d, food.first);
    }
    // One supporting sight on alternate days keeps primary interests dominant.
    for (var d = 0; d < lists.length; d += 2) {
      if (request.interests.isEmpty || lists[d].length >= target - 1) continue;
      final support = ranked.where(
        (s) =>
            !_isFoodScored(s) &&
            s.matchedInterest == 'Unknown' &&
            !used.contains(s.place.placeId) &&
            placeIdToDestination[s.place.placeId] == destinations[d],
      );
      if (support.isNotEmpty) add(d, support.first);
    }
    final oneBased =
        plan.isNotEmpty &&
        !plan.any((d) => d.dayIndex == 0) &&
        plan.any((d) => d.dayIndex == request.totalDays);
    final preferred = <int, List<String>>{};
    for (final day in plan) {
      final index = day.dayIndex - (oneBased ? 1 : 0);
      if (index < 0 || index >= lists.length) continue;
      (preferred[index] ??= []).addAll(day.placeIds.where(knownIds.contains));
    }
    // Round-robin filling prevents early days consuming all remaining choices.
    for (var slot = 0; slot < target; slot++) {
      for (var d = 0; d < lists.length; d++) {
        if (lists[d].length >= target) continue;
        final pool = ranked
            .where((s) =>
                  !used.contains(s.place.placeId) &&
                  placeIdToDestination[s.place.placeId] == destinations[d] &&
                  !_isFoodScored(s),
            )
            .toList();
        pool.sort((a, b) {
          final primaryA = a.matchedInterest != 'Unknown';
          final primaryB = b.matchedInterest != 'Unknown';
          if (primaryA != primaryB) return primaryA ? -1 : 1;
          final groupA = CandidateDiversity.groupFor(a.place.types);
          final groupB = CandidateDiversity.groupFor(b.place.types);
          int count(Iterable<ScoredAttraction> places, String group) => places
              .where((s) => !_isFoodScored(s) && CandidateDiversity.groupFor(s.place.types) == group).length;
          final dayComparison = count(lists[d], groupA).compareTo(count(lists[d], groupB));
          if (dayComparison != 0) return dayComparison;
          final tripComparison = count(lists.expand((list) => list), groupA)
              .compareTo(count(lists.expand((list) => list), groupB));
          if (tripComparison != 0) return tripComparison;
          final aiA = preferred[d]?.contains(a.place.placeId) ?? false;
          final aiB = preferred[d]?.contains(b.place.placeId) ?? false;
          if (aiA != aiB) return aiA ? -1 : 1;
          return b.score.compareTo(a.score);
        });
        if (pool.isNotEmpty) add(d, pool.first);
      }
    }
    return [
      for (var d = 0; d < lists.length; d++)
        AiCompactPlanDay(
        dayIndex: d,
          // Mandatory stops and meals go first so window trimming protects them.
          placeIds: [
            ...lists[d].where((s) => must.contains(s.place.placeId)),
            ...lists[d].where(
              (s) => !must.contains(s.place.placeId) && _isFoodScored(s),
            ),
            ..._orderByProximity(
              lists[d]
                  .where(
                    (s) => !must.contains(s.place.placeId) && !_isFoodScored(s),
                  )
                  .toList(),
            ),
          ].map((s) => s.place.placeId).toList(),
        ),
    ];
  }

  /// Converts a compact AI plan (dayIndex + ordered places) into a list of
  /// fully computed [AIDaySchedule]s. All clock times and travel times are
  /// computed deterministically in Dart. Visit durations always use the Dart category baseline.
  List<AIDaySchedule> _constructAiDaysFromPlan({
    required List<AiCompactPlanDay> plan,
    required TripDraft request,
    required List<ScoredAttraction> scored,
  }) {
    final scoredById = <String, ScoredAttraction>{
      for (final s in scored) s.place.placeId: s,
    };
    final window = ItineraryConstants.explorationWindows[
    request.exploration ?? 'Standard'] ??
        ItineraryConstants.explorationWindows['Standard']!;
    final startDate = request.startDate ?? DateTime.now();
    final travelPace = request.pace ?? 'Standard';
    final transportation = request.transportation;

    return [
      for (final day in plan)
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
        ),
    ];
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
  }) {
    final winStart = window.startMinutes;
    final winEnd = window.endMinutes;
    final buffer = ItineraryConstants.bufferForPace(travelPace);
    final factor = ItineraryConstants.durationFactorForPace(travelPace);

    // ── Hard daily stop limit (pace-based) ──────────────────────
    // Enforced directly in Dart so the AI can never pack the first days
    // and starve the last ones under the global cap. Slow = 3, Fast = 5,
    // Standard = 4 — matching the prompt's daily TARGET.
    final maxStops = ItineraryConstants.stopsPerDay(travelPace);

    final stops = <AIScheduleStop>[];
    var cursor = winStart;
    Coordinates? prevCoord;

    for (final placeId in orderedPlaceIds) {
      if (stops.length >= maxStops) break;
      final scored = scoredById[placeId];
      if (scored == null) continue; // filtered by structural validation

      final place = scored.place;
      const int? aiMinutes = null;
      final base = (aiMinutes != null && aiMinutes > 0)
          ? aiMinutes
          : (place.visitDurationMinutes ??
          ItineraryConstants.baseDurationForCategory(
              place.category, ItineraryConstants.defaultDurationMinutes));
      final duration = (base * factor)
          .round()
          .clamp(ItineraryConstants.minimumVisitDurationMinutes,
          ItineraryConstants.maximumVisitDurationMinutes);

      final travel = stops.isEmpty
          ? 0
          : _travelMinutes(
          prevCoord!, place.coordinates, transportation, buffer);

      final start = stops.isEmpty ? winStart : cursor + travel + buffer;
      final end = start + duration;
      if (end > winEnd) continue;

      stops.add(AIScheduleStop(
        stopOrder: stops.length + 1,
        placeId: placeId,
        startTime: _hhmm(start),
        endTime: _hhmm(end),
        visitDurationMinutes: duration,
        travelFromPreviousMinutes: travel,
        scheduleReason: reason,
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
    );
  }

  /// Deterministic travel time (minutes) between two coordinates using the
  /// transport mode. Speeds match the existing [ScheduleConstructionService]
  /// conventions: walking 5 km/h, driving 40 km/h, transit 30 km/h.
  int _travelMinutes(
      Coordinates a, Coordinates b, String transportation, int fallback) {
    final distanceKm = a.distanceTo(b);
    double speed;
    switch (transportation) {
      case 'driving':
        speed = 40.0;
      case 'transit':
        speed = 30.0;
      case 'cycling':
        speed = 12.0;
      default:
        speed = 5.0; // walking
    }
    final minutes = (distanceKm / speed * 60).ceil();
    return minutes < 1 ? fallback : minutes;
  }

  /// Deterministic fallback planner. Builds a complete compact plan from
  /// scored candidates, must-visits, clusters and travel preferences when
  /// the AI is unavailable or returns an invalid response.
  List<AiCompactPlanDay> _buildDeterministicPlan({
    required TripDraft request,
    required List<ScoredAttraction> scored,
    required List<String> mustVisitIds,
  }) =>
      _repairPlan(
        plan: const [],
        request: request,
        scored: scored,
        knownIds: scored.map((s) => s.place.placeId)
              .toSet(),
        mustVisitIds: mustVisitIds,
        placeIdToDestination: {
          for (final s in scored)
            s.place.placeId: _destinationForPlace(request, s.place),
        },
      ) ??
      const [];

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
    Set<String> foodPlaceIds = const {},
  }) {
    return _validator.validate(
      foodPlaceIds: foodPlaceIds,
      maxDailyStops: ItineraryConstants.stopsPerDay(request.pace),
      days: aiDays,
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
  /// what the AI prompt tells AI planner to assume).
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

  /// Reserve food, primary interests and supporting sights per destination.
  List<ScoredAttraction> _selectAICandidates({
    required List<ScoredAttraction> scored,
    required TripDraft request,
    required List<Cluster> clusters,
  }) {
    final selected = <String, ScoredAttraction>{};

    void add(ScoredAttraction s) {
      selected[s.place.placeId] = s;
    }

    for (final s in scored.where((s) => s.isMustVisit)) {
      add(s);
    }
    final allocation = _allocationFor(request);
    final target = ItineraryConstants.planningPoolSize(request.totalDays, pace: request.pace);
    for (final entry in allocation.entries) {
      final pool =
          scored
              .where((s) => _destinationForPlace(request, s.place) == entry.key)
              .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      final quota = (target * entry.value / request.totalDays).ceil();
      for (final s in pool.where(_isFoodScored).take(entry.value * 2)) {
        add(s);
      }
      for (final s
          in pool
              .where((s) => !_isFoodScored(s) && s.matchedInterest == 'Unknown')
              .take(entry.value)) {
        add(s);
      }
      final primary = pool.where((s) => !_isFoodScored(s) &&
          s.matchedInterest != 'Unknown' && !selected.containsKey(s.place.placeId)).toList();
      while (primary.isNotEmpty && selected.values.where((s) =>
          _destinationForPlace(request, s.place) == entry.key).length < quota) {
        primary.sort((a, b) {
          int count(ScoredAttraction candidate) => selected.values.where((s) =>
              _destinationForPlace(request, s.place) == entry.key &&
              CandidateDiversity.groupFor(s.place.types) ==
                  CandidateDiversity.groupFor(candidate.place.types)).length;
          final difference = count(a).compareTo(count(b));
          return difference != 0 ? difference : b.score.compareTo(a.score);
        });
        add(primary.removeAt(0));
      }
      for (final s in pool) {
        if (selected.values
                .where(
                  (s) => _destinationForPlace(request, s.place) == entry.key,
                )
                .length >=
            quota) {
          break;
        }
        add(s);
      }
    }

    return selected.values.toList();
  }

  /// Whether a scored candidate is a food/drink place.
  bool _isFoodScored(ScoredAttraction s) {
    final types = s.place.types.map((t) => t.toLowerCase()).toSet();
    return types.any(CandidateRetrievalService.foodTypes.contains);
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
    for (final destination in request.destinations) {
      if (place.destinationId == destination.destinationId ||
          place.destinationId == destination.destinationName) {
        return destination.destinationName;
      }
    }
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
    Duration budget,
  ) async {
    try {
      if (coord != null && budget > Duration.zero) {
        return await _weather.getDailyForecast(
          latitude: coord.latitude,
          longitude: coord.longitude,
          startDate: startDate,
          endDate: endDate,
            )
            .timeout(
              budget < const Duration(seconds: 2)
                  ? budget
                  : const Duration(seconds: 2),
            );
      }
    } catch (e) {
      debugPrint('[WEATHER] Fetch failed: $e');
    }
    return WeatherForecast(daily: []);
  }
}
