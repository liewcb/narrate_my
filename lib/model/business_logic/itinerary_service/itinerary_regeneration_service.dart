// lib/model/business_logic/itinerary_service/itinerary_regeneration_service.dart
//
// FAST FULL-PIPELINE itinerary regeneration.
//
// Regeneration now mirrors the CORE planning stages of the initial generation
// pipeline — but orchestrated against the SAME shared services (no duplicated
// retrieval / scoring / clustering / validation logic):
//
//   Existing valid itinerary
//     → refresh candidate knowledge (CandidateRetrievalService, parallelised)
//     → filter + bounded sufficiency expansion
//     → score (ScoringService)
//     → geographic clustering (ClusteringService)
//     → compact AI context (fresh candidates + fresh clusters)
//     → DeepSeek generates an ALTERNATIVE plan (bounded timeout)
//     → hard-constraint validation (AiScheduleValidator)
//     → bounded retry with feedback
//     → replace ONLY if valid; otherwise preserve the current itinerary.
//
// The service NEVER writes to the database and NEVER mutates the current
// result until a regenerated schedule has passed hard validation.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../entities/place.dart';
import '../../entities/trip_draft.dart';
import '../../entities/weather.dart';
import './ai_schedule_validator.dart';
import './candidate_retrieval_service.dart';
import './clustering_service.dart';
import './generation_pipeline_service.dart';
import './place_registry.dart';
import './schedule_construction_service.dart';
import './scoring_service.dart';

/// Service responsible for regenerating a valid itinerary using FRESH
/// candidate planning while respecting the same traveler requirements.
class ItineraryRegenerationService {
  /// Bounded AI/validation retry attempts. The expensive pipeline stages run
  /// ONCE; only the (cheap) AI request + validation repeat.
  static const int maxRegenerationAttempts = 3;

  // ── Bounded stage timeouts (protect the < 20s target) ──────────
  static const Duration retrievalTimeout = Duration(seconds: 6);
  static const Duration recoveryTimeout = Duration(seconds: 6);
  static const Duration expansionTimeout = Duration(seconds: 5);
  static const Duration aiTimeout = Duration(seconds: 14);

  /// Global wall-clock budget for the whole regeneration operation. The AI
  /// request is clamped to whatever remains so the total stays bounded even
  /// when a stage runs long. This is a TARGET, not a guarantee — external
  /// services can still exceed it independently.
  static const Duration globalBudget = Duration(seconds: 20);

  /// Safety margin reserved for parse + validation + result rebuild after the
  /// AI request returns.
  static const Duration postAiBuffer = Duration(seconds: 1);

  final AIService _aiService;
  final AiScheduleValidator _validator;
  final CandidateRetrievalService _candidateRetrieval;
  final ScoringService _scoring;
  final ClusteringService _clustering;

  ItineraryRegenerationService({
    AIService? aiService,
    AiScheduleValidator? validator,
    CandidateRetrievalService? candidateRetrieval,
    ScoringService? scoring,
    ClusteringService? clustering,
  })  : _aiService = aiService ??
            AIService(
              baiApiKey: ApiKeys.baiApiKey,
              baiModel: ApiKeys.baiModel,
              openRouterApiKey: ApiKeys.openRouterApiKey,
              cohereApiKey: ApiKeys.cohereApiKey,
            ),
        _validator = validator ?? AiScheduleValidator(),
        _candidateRetrieval =
            candidateRetrieval ?? CandidateRetrievalService(),
        _scoring = scoring ?? ScoringService(),
        _clustering = clustering ?? ClusteringService();

  /// Regenerate [current] with fresh candidate planning using the traveler's
  /// original [request]. Returns the new result on success, or the original
  /// [current] unchanged when the pipeline cannot produce a valid alternative.
  Future<ItineraryResult> regenerate({
    required ItineraryResult current,
    required TripDraft request,
  }) async {
    final totalSw = Stopwatch()..start();
    final globalDeadline = DateTime.now().add(globalBudget);

    debugPrint('════════════════════════════════════');
    debugPrint('🔄 FAST-PIPELINE REGENERATION START');
    debugPrint('════════════════════════════════════');
    debugPrint('[REGENERATE] Total days: ${request.totalDays}');
    debugPrint('[REGENERATE] Destinations: ${request.destinationNames}');
    debugPrint('[REGENERATE] Must-visits: ${request.mustVisitPlaceIds}');

    // ── STAGE 1-5: refresh candidate knowledge (retrieve → filter →
    //    sufficiency → score → cluster). Runs ONCE, before the retry loop.
    final plan = await _refreshCandidates(
      request: request,
      current: current,
      globalDeadline: globalDeadline,
    );
    if (plan == null) {
      debugPrint('[REGENERATE] Candidate refresh produced no usable plan — '
          'preserving current itinerary.');
      debugPrint('[REGENERATE] TOTAL: '
          '${(totalSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
      return current;
    }

    final usedIds = _usedPlaceIds(current);
    final alternatives = _alternativesFromPlan(
      plan: plan,
      usedIds: usedIds,
    );

    debugPrint('[REGENERATE] Fresh candidates: ${plan.pool.totalCount}');
    debugPrint('[REGENERATE] Currently used: ${usedIds.length}');
    debugPrint('[REGENERATE] Alternative candidates for AI: '
        '${alternatives.length}');

    final knownPlaceIds = plan.registry.placeIds;
    final placeIdToDestination = _placeIdToDestination(plan, request);

    String? lastFeedback;

    // ── STAGE 6-9: AI alternative generation + hard validation, bounded.
    for (int attempt = 1; attempt <= maxRegenerationAttempts; attempt++) {
      // Respect the global budget: stop early if there is no realistic time
      // left for an AI round trip + validation.
      if (_remaining(globalDeadline) <= postAiBuffer) {
        debugPrint('[REGENERATE] Global budget exhausted before attempt '
            '$attempt — preserving current itinerary.');
        break;
      }

      debugPrint('[REGENERATE] DeepSeek attempt $attempt');

      final promptSw = Stopwatch()..start();
      final prompt = _buildRegenerationPrompt(
        request: request,
        current: current,
        clusters: plan.clusters,
        alternatives: alternatives,
        feedback: lastFeedback,
      );
      debugPrint('[REGENERATE] Prompt construction: '
          '${(promptSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
          '(${prompt.length} chars)');

      // Clamp the AI timeout to whatever remains of the global budget.
      final aiBudget = _clampAiBudget(globalDeadline);

      try {
        final aiSw = Stopwatch()..start();
        final raw = await _aiService
            .generateRawContent(
              prompt,
              timeout: aiBudget,
              totalBudget: aiBudget,
              requestName: 'REGENERATE',
            )
            .timeout(aiBudget + const Duration(seconds: 1));
        debugPrint('[REGENERATE] AI generation: '
            '${(aiSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
            '(${raw.length} chars)');

        final parseSw = Stopwatch()..start();
        final List<AIDaySchedule> aiDays;
        try {
          // The prompt omits stopOrder (array ordering IS the stop order), so
          // normalise it from position before validation — otherwise every
          // multi-stop day would trip the duplicate-stopOrder hard check.
          aiDays = _normalizeStopOrders(parseAiScheduleJson(raw));
        } catch (e) {
          debugPrint('[REGENERATE] JSON parse: '
              '${(parseSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
          debugPrint('[REGENERATE] JSON parse failed: $e');
          // Parse failure is recoverable → retry with feedback.
          lastFeedback = 'AI returned unparseable JSON: $e';
          continue;
        }
        debugPrint('[REGENERATE] JSON parsing: '
            '${(parseSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');

        final validationSw = Stopwatch()..start();
        final validation = _validator.validate(
          days: aiDays,
          knownPlaceIds: knownPlaceIds,
          mustVisitIds: plan.mustVisitIds,
          totalDays: request.totalDays,
          explorationTime: request.exploration ?? 'Standard',
          destinationOrder: request.destinationNames,
          allocatedDaysPerDestination: _allocationFor(request),
          placeIdToDestination: placeIdToDestination,
        );
        debugPrint('[REGENERATE] Validation: '
            '${(validationSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
            '→ ${validation.passed ? "PASS" : "FAIL"}');

        if (validation.passed) {
          final updated = _toResult(
            current: current,
            plan: plan,
            aiDays: aiDays,
            request: request,
          );
          debugPrint('[REGENERATE] Attempt $attempt produced a valid '
              'alternative (${_verifiedMustVisitCount(aiDays, plan.mustVisitIds)}'
              '/${plan.mustVisitIds.length} must-visits, '
              '${aiDays.fold<int>(0, (s, d) => s + d.schedule.length)} stops).');
          debugPrint('[REGENERATE] TOTAL: '
              '${(totalSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
          debugPrint('✅ REGENERATION COMPLETE');
          debugPrint('════════════════════════════════════');
          return updated;
        }

        // Validation failure → retry with feedback (bounded).
        lastFeedback = validation.feedbackText;
        debugPrint('[REGENERATE] Attempt $attempt rejected: '
            '${validation.issues.map((i) => i.message).join('; ')}');
      } on TimeoutException {
        debugPrint('[REGENERATE] Attempt $attempt AI request timed out.');
        lastFeedback = 'The planning service timed out. Produce a valid, '
            'complete schedule for every day.';
      } catch (e) {
        final message = e.toString();
        debugPrint('[REGENERATE] Attempt $attempt error: $e');
        // Non-recoverable provider/auth failures must not be hammered.
        if (_isFatalProviderError(message)) {
          debugPrint('[REGENERATE] Non-recoverable provider error — '
              'stopping retries, preserving current itinerary.');
          break;
        }
        lastFeedback = 'AI provider error: $message';
      }
    }

    debugPrint('[REGENERATE] All attempts failed — preserving previous '
        'valid itinerary.');
    debugPrint('[REGENERATE] TOTAL: '
        '${(totalSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
    debugPrint('════════════════════════════════════');
    debugPrint('❌ REGENERATION FAILED (old itinerary kept)');
    debugPrint('════════════════════════════════════');
    return current;
  }

  // ============================================================
  // STAGE 1-5 — FRESH CANDIDATE PLANNING (reuses pipeline services)
  // ============================================================

  /// Refreshes candidate knowledge exactly like the initial pipeline:
  /// parallel retrieval + must-visit recovery → bounded sufficiency
  /// expansion → scoring → geographic clustering. Returns null when no
  /// usable plan can be produced (the caller then preserves the current
  /// itinerary).
  Future<_RegenerationPlan?> _refreshCandidates({
    required TripDraft request,
    required ItineraryResult current,
    required DateTime globalDeadline,
  }) async {
    final exploration = request.exploration ?? 'Standard';
    final existingRegistry = current.placeRegistry;
    final existingIds = existingRegistry?.placeIds ?? const <String>{};

    // ── PARALLEL: general retrieval + targeted must-visit recovery.
    //    These are independent network operations (no shared mutable state),
    //    so they run concurrently to save wall-clock time.
    final retrievalSw = Stopwatch()..start();
    CandidatePool pool;
    MustVisitRecoveryResult? recovery;
    try {
      final results = await Future.wait([
        _candidateRetrieval
            .retrieveCandidates(request: request)
            .timeout(retrievalTimeout),
        request.mustVisitPlaceIds.isEmpty
            ? Future<Object?>.value(null)
            : _candidateRetrieval.recoverMustVisits(
                requestedMustVisitIds: request.mustVisitPlaceIds,
                alreadyRetrievedIds: existingIds,
                mustVisitNames: request.mustVisitPlaceIds,
                searchCenter: request.primaryCoordinates,
                destinationName: request.destinationNames.isNotEmpty
                    ? request.destinationNames.first
                    : null,
              ).timeout(recoveryTimeout),
      ]);
      pool = results[0] as CandidatePool;
      recovery = results[1] as MustVisitRecoveryResult?;
    } on TimeoutException {
      debugPrint('[REGENERATE] Candidate retrieval: TIMEOUT — preserving '
          'current itinerary.');
      return null;
    } catch (e) {
      debugPrint('[REGENERATE] Candidate retrieval failed: $e — preserving '
          'current itinerary.');
      return null;
    }
    debugPrint('[REGENERATE] Candidate retrieval: '
        '${(retrievalSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
        '(${pool.totalCount} candidates)');

    final registry = PlaceRegistry()
      ..addAll(pool.attractions)
      ..addAll(pool.food);
    final attractions = <Place>[...pool.attractions];
    final food = <Place>[...pool.food];

    // Merge recovered must-visits into the fresh pool.
    if (recovery != null && recovery.recoveredPlaces.isNotEmpty) {
      for (final p in recovery.recoveredPlaces) {
        if (registry.contains(p.placeId)) continue;
        registry.add(p);
        (p.types.any(CandidateRetrievalService.foodTypes.contains)
                ? food
                : attractions)
            .add(p);
      }
    }

    // ── MUST-VISIT PRESERVATION (hard requirement).
    //    Guarantee every requested must-visit is a candidate. If fresh
    //    retrieval missed it, fall back to the existing registry (it is
    //    currently scheduled) so the candidate refresh can never drop one.
    final effectiveMustVisitIds = <String>[];
    for (final id in request.mustVisitPlaceIds) {
      if (id.isEmpty) continue;
      if (registry.contains(id)) {
        effectiveMustVisitIds.add(id);
        continue;
      }
      final existing = existingRegistry?.byId(id);
      if (existing != null) {
        registry.add(existing);
        attractions.add(existing);
        effectiveMustVisitIds.add(id);
      } else {
        debugPrint('[REGENERATE] Must-visit "$id" unavailable through '
            'retrieval or the existing registry — cannot guarantee inclusion.');
      }
    }

    // ── SUFFICIENCY: one bounded expansion when the pool is too small.
    final usableTarget = ItineraryConstants.usableCandidateTarget(
      days: request.totalDays,
      mustVisitCount: effectiveMustVisitIds.length,
      explorationTime: exploration,
    );
    if (attractions.length + food.length < usableTarget &&
        _remaining(globalDeadline) > expansionTimeout + postAiBuffer) {
      final expandSw = Stopwatch()..start();
      try {
        final expanded = await _candidateRetrieval
            .expandCandidates(
              request: request,
              alreadySeenIds: registry.placeIds,
              radiusMultiplier: ItineraryConstants.expansionMultiplier,
            )
            .timeout(expansionTimeout);
        var added = 0;
        for (final p in expanded.attractions) {
          if (registry.contains(p.placeId)) continue;
          registry.add(p);
          attractions.add(p);
          added++;
        }
        for (final p in expanded.food) {
          if (registry.contains(p.placeId)) continue;
          registry.add(p);
          food.add(p);
          added++;
        }
        debugPrint('[REGENERATE] Sufficiency expansion: '
            '${(expandSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
            '(+$added)');
      } on TimeoutException {
        debugPrint('[REGENERATE] Sufficiency expansion timed out — '
            'continuing with current pool.');
      } catch (e) {
        debugPrint('[REGENERATE] Sufficiency expansion failed: $e');
      }
    }

    if (attractions.isEmpty) {
      debugPrint('[REGENERATE] No usable attraction candidates after '
          'refresh — preserving current itinerary.');
      return null;
    }

    // ── SCORING (existing ScoringService).
    final scoringSw = Stopwatch()..start();
    final scored = _scoring.scorePlaces(
      places: <Place>[...attractions, ...food],
      selectedInterests: request.interests.toList(),
      mustVisitIds: effectiveMustVisitIds,
      explorationTime: exploration,
      tripLocation: request.primaryCoordinates,
      strictInterestFilter: false, // rank all, do not eliminate
    );
    debugPrint('[REGENERATE] Scoring: '
        '${(scoringSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
        '(${scored.length} ranked)');
    if (scored.isEmpty) return null;

    // ── GEOGRAPHIC CLUSTERING (existing ClusteringService).
    final clusterSw = Stopwatch()..start();
    final clusters = _clustering.clusterGeographically(
      scoredPlaces: scored,
      clusterCount: request.totalDays.clamp(1, scored.length),
    );
    debugPrint('[REGENERATE] Clustering: '
        '${(clusterSw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
        '(${clusters.length} clusters)');

    return _RegenerationPlan(
      pool: CandidatePool(attractions: attractions, food: food),
      registry: registry,
      scored: scored,
      clusters: clusters,
      mustVisitIds: effectiveMustVisitIds,
    );
  }

  /// Alternative candidates for the AI: fresh scored places, excluding the
  /// ones already scheduled (to force a genuinely different plan) but always
  /// keeping must-visits. Falls back to the full fresh pool when scarce.
  List<Place> _alternativesFromPlan({
    required _RegenerationPlan plan,
    required Set<String> usedIds,
  }) {
    final mustSet = plan.mustVisitIds.toSet();
    final alternatives = <Place>[];
    final seen = <String>{};
    for (final s in plan.scored) {
      final p = s.place;
      if (p.placeId.isEmpty || seen.contains(p.placeId)) continue;
      if (usedIds.contains(p.placeId) && !mustSet.contains(p.placeId)) continue;
      seen.add(p.placeId);
      alternatives.add(p);
    }
    if (alternatives.isEmpty) {
      return plan.scored.map((s) => s.place).toList();
    }
    return alternatives;
  }

  // ============================================================
  // PROMPT BUILDING (compact context from FRESH candidates + clusters)
  // ============================================================

  String _buildRegenerationPrompt({
    required TripDraft request,
    required ItineraryResult current,
    required List<Cluster> clusters,
    required List<Place> alternatives,
    String? feedback,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('You are generating a NEW ALTERNATIVE version of an '
        'existing travel itinerary. Use ONLY the supplied candidates. Do not '
        'invent places, place IDs, coordinates, visit durations, opening '
        'hours, or travel times. Every scheduled place must come from the '
        'ALTERNATIVE CANDIDATES below.');
    buffer.writeln('');

    // ── TRIP REQUIREMENTS ───────────────────────────────────────────
    buffer.writeln('TRIP REQUIREMENTS');
    buffer.writeln('Total days: ${request.totalDays}');
    if (request.startDate != null) {
      buffer.writeln(
          'Start date: ${request.startDate!.toIso8601String().split('T').first}');
    }
    if (request.endDate != null) {
      buffer.writeln(
          'End date: ${request.endDate!.toIso8601String().split('T').first}');
    }
    buffer.writeln('Destinations: ${request.destinationNames.join(', ')}');
    buffer.writeln('Exploration time: ${request.exploration ?? 'Standard'}');
    buffer.writeln('Travel pace (comfort preference, not a stop-count rule): '
        '${request.pace ?? 'Standard'}');
    buffer.writeln('Transportation: ${request.transportation}');
    buffer.writeln(
        'Traveler interests: ${request.interests.toList().join(', ')}');
    buffer.writeln('');

    // ── MUST-VISITS (hard) ──────────────────────────────────────────
    buffer.writeln('MUST-VISITS (HARD requirement — must appear exactly '
        'once — never removed, never replaced)');
    final mustVisitIds = request.mustVisitPlaceIds.toSet();
    final mustVisits =
        alternatives.where((p) => mustVisitIds.contains(p.placeId)).toList();
    if (mustVisits.isEmpty) {
      buffer.writeln('- none');
    } else {
      for (final mv in mustVisits) {
        buffer.writeln('- ${mv.placeId} | ${mv.placeName} | '
            '${mv.destinationId ?? '?'}');
      }
    }
    buffer.writeln('');

    // ── ALTERNATIVE CANDIDATES (compact context) ───────────────────
    buffer.writeln('ALTERNATIVE CANDIDATES (select from these ONLY)');
    for (final place in alternatives) {
      final clusterId = _clusterIdForPlace(clusters, place.placeId);
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

    // ── CURRENT ITINERARY (produce a DIFFERENT combination) ────────
    buffer.writeln('CURRENT ITINERARY (previous plan — produce a DIFFERENT '
        'combination)');
    final days = current.scheduledDays;
    if (days != null && days.isNotEmpty) {
      for (final day in days) {
        final names =
            day.stops.map((s) => s.attraction.place.placeName).join(' → ');
        buffer.writeln('Day ${day.dayIndex + 1}: $names');
      }
    } else {
      buffer.writeln('- none');
    }
    buffer.writeln('');

    // ── PLANNING GUIDANCE ──────────────────────────────────────────
    buffer.writeln('PLANNING GUIDANCE');
    buffer.writeln('- Produce a genuinely different but reasonable plan using '
        'the alternative candidates.');
    buffer.writeln('- Decide the number of stops per day from visit '
        'durations, travel proximity, opening hours and the exploration '
        'window. Do NOT force a fixed count.');
    buffer.writeln('- Keep activities inside the exploration window.');
    buffer.writeln('- Group places geographically for reasonable '
        'transitions.');
    buffer.writeln('- Do not reorder or duplicate places beyond what is '
        'reasonable.');
    buffer.writeln('');

    // ── REGENERATION FEEDBACK (retry) ──────────────────────────────
    if (feedback != null && feedback.trim().isNotEmpty) {
      buffer.writeln('PREVIOUS ATTEMPT WAS REJECTED. Fix ALL of these:');
      buffer.writeln(feedback);
      buffer.writeln('');
    }

    // ── OUTPUT CONTRACT ────────────────────────────────────────────
    buffer.writeln('Return STRICT JSON ONLY (no Markdown fences) with this '
        'structure. Do NOT emit a "stopOrder" field — the array ordering IS '
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
  // RESULT REBUILD (fresh pool/registry/scored/clusters preserved)
  // ============================================================

  /// Builds an updated [ItineraryResult] from a validated AI schedule using
  /// the FRESH candidate pool / registry / scored / clusters so downstream
  /// features (add place, further regeneration) operate on refreshed
  /// knowledge. Weather + warnings + must-visit info are preserved.
  ItineraryResult _toResult({
    required ItineraryResult current,
    required _RegenerationPlan plan,
    required List<AIDaySchedule> aiDays,
    required TripDraft request,
  }) {
    final scheduledDays = _toScheduledDays(aiDays, request, plan.registry);
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
      candidatePool: plan.pool,
      placeRegistry: plan.registry,
      scoredCandidates: plan.scored,
      clusters: plan.clusters,
      unretrievableMustVisits: current.unretrievableMustVisits,
    );
  }

  List<ScheduledDay> _toScheduledDays(
    List<AIDaySchedule> aiDays,
    TripDraft request,
    PlaceRegistry registry,
  ) {
    final startDate = request.startDate ?? DateTime.now();
    final result = <ScheduledDay>[];

    for (final day in aiDays) {
      final date = DateTime.tryParse(day.date) ??
          startDate.add(Duration(days: day.dayIndex));
      final stops = <ScheduledStop>[];

      for (final aiStop in day.schedule) {
        final place = registry.byId(aiStop.placeId);
        if (place == null) continue;

        stops.add(ScheduledStop(
          attraction: ScoredAttraction(
            place: place,
            score: 0,
            breakdown: const {},
            isMustVisit: request.mustVisitPlaceIds.contains(place.placeId),
          ),
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
        totalTravelTime: stops.fold<double>(
            0, (sum, s) => sum + s.travelFromPreviousMinutes),
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

  // ============================================================
  // HELPERS
  // ============================================================

  /// Reassigns each day's stopOrder sequentially from array position. The
  /// regeneration prompt intentionally omits stopOrder (array ordering IS the
  /// stop order), so this prevents the validator's duplicate-stopOrder hard
  /// check from rejecting every multi-stop day.
  List<AIDaySchedule> _normalizeStopOrders(List<AIDaySchedule> days) {
    return [
      for (final day in days)
        AIDaySchedule(
          dayIndex: day.dayIndex,
          date: day.date,
          warnings: day.warnings,
          needsRepair: day.needsRepair,
          schedule: [
            for (var i = 0; i < day.schedule.length; i++)
              AIScheduleStop(
                stopOrder: i + 1,
                placeId: day.schedule[i].placeId,
                startTime: day.schedule[i].startTime,
                endTime: day.schedule[i].endTime,
                visitDurationMinutes: day.schedule[i].visitDurationMinutes,
                travelFromPreviousMinutes:
                    day.schedule[i].travelFromPreviousMinutes,
                scheduleReason: day.schedule[i].scheduleReason,
                weatherNote: day.schedule[i].weatherNote,
              ),
          ],
        ),
    ];
  }

  int _verifiedMustVisitCount(
      List<AIDaySchedule> aiDays, List<String> mustVisitIds) {
    final seen = <String>{};
    for (final day in aiDays) {
      for (final stop in day.schedule) {
        if (mustVisitIds.contains(stop.placeId)) seen.add(stop.placeId);
      }
    }
    return seen.length;
  }

  Set<String> _usedPlaceIds(ItineraryResult current) {
    final ids = <String>{};
    for (final day in current.scheduledDays ?? const <ScheduledDay>[]) {
      for (final stop in day.stops) {
        ids.add(stop.attraction.place.placeId);
      }
    }
    return ids;
  }

  int? _clusterIdForPlace(List<Cluster> clusters, String placeId) {
    for (final cluster in clusters) {
      for (final a in cluster.attractions) {
        if (a.place.placeId == placeId) return cluster.dayIndex;
      }
    }
    return null;
  }

  /// placeId → destination NAME (validator compares against allocated-day
  /// destination names). Built from the FRESH scored candidates.
  Map<String, String> _placeIdToDestination(
      _RegenerationPlan plan,
      TripDraft request,
      ) {
    final result = <String, String>{};
    for (final s in plan.scored) {
      final destName = _destinationNameForPlace(request, s.place);
      if (destName != null) {
        result[s.place.placeId] = destName;
      }
    }
    return result;
  }

  /// Day-per-destination allocation (names as keys), matching the initial
  /// pipeline: the explicit [TripDraft.daySplit] when present, otherwise an
  /// even split across destinations.
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

  /// Destination NAME for a place by nearest coordinate, matching the main
  /// pipeline's logic. Falls back to the first destination name / DB id.
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

  Duration _remaining(DateTime deadline) {
    final r = deadline.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  /// AI budget = min(aiTimeout, remaining global budget - post-AI buffer),
  /// floored so a request always gets a usable window when time remains.
  Duration _clampAiBudget(DateTime globalDeadline) {
    final remaining = _remaining(globalDeadline) - postAiBuffer;
    if (remaining <= Duration.zero) return const Duration(seconds: 5);
    return remaining < aiTimeout ? remaining : aiTimeout;
  }

  /// Non-recoverable provider failures (auth / bad key) must not be retried.
  bool _isFatalProviderError(String message) {
    final m = message.toLowerCase();
    return m.contains('401') ||
        m.contains('403') ||
        m.contains('unauthorized') ||
        m.contains('forbidden') ||
        m.contains('invalid api key') ||
        m.contains('authentication');
  }
}

/// Fresh candidate planning produced once per regeneration, reused across the
/// bounded AI retry attempts.
class _RegenerationPlan {
  final CandidatePool pool;
  final PlaceRegistry registry;
  final List<ScoredAttraction> scored;
  final List<Cluster> clusters;
  final List<String> mustVisitIds;

  const _RegenerationPlan({
    required this.pool,
    required this.registry,
    required this.scored,
    required this.clusters,
    required this.mustVisitIds,
  });
}
