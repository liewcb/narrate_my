// lib/core/services/ai_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';
import '../config/itinerary_constants.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/business_logic/itinerary_service/schedule_repair_service.dart';
import '../../model/entities/place.dart';

/// Unified AI service using:
/// - Primary: B.AI Gateway (DeepSeek V4 Flash/Pro)
/// - Fallback 1: OpenRouter (free router)
/// - Fallback 2: Cohere
///
/// RESPONSIBILITY SPLIT (mandatory):
///   DART / DETERMINISTIC — input validation, retrieval, must-visit
///     recovery, filtering, scoring, expansion, K-Means clustering,
///     fact preservation, hard-constraint validation, persistence.
///   DEEPSEEK / AI — daily activity selection, activity combination,
///     activity sequence, reasonable activity count, human-friendly
///     schedule, meal placement, weather-aware planning, travel-pace
///     interpretation, daily-flow reasoning, planning explanations.
class AIService {
  final String baiApiKey;
  final String baiModel;
  final String openRouterApiKey;
  final String cohereApiKey;

  static const String _baiBaseUrl = 'https://api.b.ai/v1/chat/completions';

  /// Timeout for the main (B.AI / DeepSeek) itinerary-planning request.
  static const Duration aiRequestTimeout = Duration(seconds: 90);

  /// Timeout for the explicit fallback providers (OpenRouter / Cohere).
  static const Duration fallbackProviderTimeout = Duration(seconds: 30);

  /// Print the full prompt body when enabled (off by default to avoid
  /// flooding the console). The prompt SIZE is always printed.
  static const bool debugAiPrompt = false;

  /// Maximum regeneration attempts for a single failed AI planning day.
  static const int maxAiRegenerationAttempts = 2;

  AIService({
    String? baiApiKey,
    String? baiModel,
    String? openRouterApiKey,
    String? cohereApiKey,
  })  : baiApiKey = (baiApiKey ?? ApiKeys.baiApiKey).trim(),
        baiModel = (baiModel ?? ApiKeys.baiModel).trim(),
        openRouterApiKey = (openRouterApiKey ?? ApiKeys.openRouterApiKey).trim(),
        cohereApiKey = (cohereApiKey ?? ApiKeys.cohereApiKey).trim();

  // ============================================================
  // 1. ESTIMATE VISIT DURATION
  // ============================================================

  Future<int> estimateDuration(Place place) async {
    final prompt = '''
Estimate visit duration for this place in MINUTES.

Place: ${place.name}
Category: ${place.category}
Types: ${place.types.join(', ')}
Rating: ${place.rating}

Return ONLY a number. Examples: 120, 60, 90.
''';

    final response = await _callAi(prompt);
    final match = RegExp(r'\d+').firstMatch(response);
    return match != null ? int.parse(match.group(0)!) : 120;
  }

  /// Public wrapper to generate raw text from a custom prompt
  Future<String> generateRawContent(String prompt) async {
    return await _callAi(prompt, timeout: aiRequestTimeout);
  }

  // ============================================================
  // AI ITINERARY PLANNER
  //
  // DeepSeek is the ACTUAL planner: it selects daily places, their order,
  // a reasonable number of stops and the human-friendly schedule from the
  // supplied candidate pool + geographic clusters. It NEVER invents places,
  // times, opening hours or travel data — it plans within the facts given.
  //
  // Dart retains: validation, must-visit enforcement, hard constraints,
  // destination allocation checks and persistence.
  // ============================================================

  Future<AIItineraryPlanningResult> generatePlannedItinerary({
    required AIPlannerTripContext trip,
    required List<AIPlannerCandidate> candidates,
    required List<String> mustVisitIds,
    required List<AIPlannerCluster> clusters,
    String? regenerationFeedback,
  }) async {
    final prompt = _buildPlannerPrompt(
      trip: trip,
      candidates: candidates,
      mustVisitIds: mustVisitIds,
      clusters: clusters,
      regenerationFeedback: regenerationFeedback,
    );

    debugPrint('[AI INPUT SUMMARY]');
    debugPrint('Destinations: ${trip.destinations.length}');
    debugPrint('Days: ${trip.totalDays}');
    debugPrint('Candidates: ${candidates.length}');
    debugPrint('Must-visits: ${mustVisitIds.length}');
    debugPrint('Clusters: ${clusters.length}');
    debugPrint('Prompt characters: ${prompt.length}');
    if (debugAiPrompt) {
      debugPrint('─── FULL PROMPT ───\n$prompt\n─── END PROMPT ───');
    }

    try {
      final raw = await _callAi(prompt, timeout: aiRequestTimeout);
      debugPrint('[AI RESPONSE]');
      debugPrint('Status: ok');
      debugPrint('Response characters: ${raw.length}');
      final days = _parsePlannerDays(raw);

      return AIItineraryPlanningResult(
        success: true,
        days: days,
      );
    } catch (e) {
      debugPrint('❌ [AI PLANNER] Failed: $e');
      return AIItineraryPlanningResult(
        success: false,
        errorMessage: 'AI itinerary planning failed: $e',
      );
    }
  }

  /// Builds the structured DeepSeek planner prompt. No pre-computed times,
  /// no "schedule formatter" role, no fixed stops-per-day rule.
  String _buildPlannerPrompt({
    required AIPlannerTripContext trip,
    required List<AIPlannerCandidate> candidates,
    required List<String> mustVisitIds,
    required List<AIPlannerCluster> clusters,
    String? regenerationFeedback,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('You are an expert travel itinerary PLANNER.');
    buffer.writeln('You plan a complete multi-day itinerary from the supplied '
        'candidate places and geographic clusters. You NEVER invent places, '
        'place IDs, coordinates, opening hours, visit durations or travel '
        'times. Every place you schedule MUST come from the CANDIDATES below.');
    buffer.writeln('');

    // ── TRIP ────────────────────────────────────────────────────
    buffer.writeln('TRIP');
    buffer.writeln('Start date: ${trip.startDate}');
    buffer.writeln('End date: ${trip.endDate}');
    buffer.writeln('Total days: ${trip.totalDays}');
    buffer.writeln('Exploration window: ${trip.explorationStart} → '
        '${trip.explorationEnd}');
    buffer.writeln('Travel pace (comfort preference, NOT a stop-count rule): '
        '${trip.travelPace}');
    buffer.writeln('Transportation mode: ${trip.transportationMode}');
    buffer.writeln('Traveler interests: '
        '${trip.interests.isEmpty ? 'none' : trip.interests.join(', ')}');
    buffer.writeln('Weather condition: ${trip.weatherCondition ?? 'Unknown'}');
    buffer.writeln('');

    // ── DESTINATIONS ────────────────────────────────────────────
    buffer.writeln('DESTINATIONS (with allocated days — respect these)');
    for (final d in trip.destinations) {
      buffer.writeln(
        '- ${d.destinationId} ${d.destinationName}: ${d.allocatedDays} day(s)',
      );
    }
    buffer.writeln('');

    // ── MUST-VISITS ─────────────────────────────────────────────
    buffer.writeln('MUST-VISITS (hard requirement — include every one of '
        'these in the itinerary)');
    final mustVisits = candidates.where((c) => c.isMustVisit).toList();
    if (mustVisits.isEmpty) {
      buffer.writeln('- none');
    } else {
      for (final c in mustVisits) {
        buffer.writeln(
          '- ${c.placeId} | ${c.name} | ${c.destinationId ?? '?'} | '
          'cluster=${c.clusterId}',
        );
      }
    }
    buffer.writeln('');

    // ── CLUSTERS ────────────────────────────────────────────────
    buffer.writeln('GEOGRAPHIC CLUSTERS (for proximity reasoning — '
        'clusters are NOT days)');
    for (final cluster in clusters) {
      final names = cluster.candidatePlaceIds.map((id) {
        AIPlannerCandidate? match;
        for (final c in candidates) {
          if (c.placeId == id) {
            match = c;
            break;
          }
        }
        return match?.name ?? id;
      }).join(', ');
      buffer.writeln(
        '- cluster ${cluster.clusterId} | destination=${cluster.destinationId} '
        '| center=(${cluster.centerLatitude}, ${cluster.centerLongitude}) '
        '| places: $names',
      );
    }
    buffer.writeln('');

    // ── CANDIDATES ──────────────────────────────────────────────
    buffer.writeln('CANDIDATES (select from these ONLY — never invent)');
    for (final c in candidates) {
      buffer.writeln(jsonEncode({
        'placeId': c.placeId,
        'name': c.name,
        'destinationId': c.destinationId,
        'destinationName': c.destinationName,
        'clusterId': c.clusterId,
        'latitude': c.latitude,
        'longitude': c.longitude,
        'category': c.category,
        'types': c.types,
        'rating': c.rating,
        'interestScore': c.interestScore,
        'finalScore': c.finalScore,
        'isMustVisit': c.isMustVisit,
        'visitDurationMinutes': c.visitDurationMinutes,
        'openingHours': c.openingHours,
        'bestTimeSuggestion': c.bestTimeSuggestion,
      }));
    }
    buffer.writeln('');

    // ── TRAVEL TIMES (if supplied) ──────────────────────────────
    if (trip.travelTimes != null && trip.travelTimes!.isNotEmpty) {
      buffer.writeln('TRAVEL TIMES (facts — use these exactly; do NOT invent)');
      trip.travelTimes!.forEach((k, v) => buffer.writeln('- $k = $v'));
      buffer.writeln('');
    } else {
      buffer.writeln('No travel-time matrix supplied. Reason qualitatively '
          'about proximity using coordinates/clusters. Do NOT fabricate '
          'precise travel minutes.');
      buffer.writeln('');
    }

    // ── REGENERATION FEEDBACK (optional) ────────────────────────
    if (regenerationFeedback != null && regenerationFeedback.trim().isNotEmpty) {
      buffer.writeln('PREVIOUS ATTEMPT WAS REJECTED. Fix ALL of these:');
      buffer.writeln(regenerationFeedback);
      buffer.writeln('');
    }

    // ── PLANNING GUIDANCE ───────────────────────────────────────
    buffer.writeln('PLANNING GUIDANCE');
    buffer.writeln('- Decide the reasonable NUMBER of stops per day yourself, '
        'based on visit durations, travel proximity, opening hours, weather '
        'and the exploration window. Do NOT force a fixed count.');
    buffer.writeln('- ${_paceGuidance(trip.travelPace)}');
    buffer.writeln('- Lunch ≈ 11:00–14:00, Dinner ≈ 17:00–21:00 — only using '
        'food places supplied in CANDIDATES.');
    buffer.writeln('- Keep every activity inside the exploration window. '
        'Unused time is acceptable; a realistic flow beats filling the window.');
    buffer.writeln('- If a place is closed per its opening hours on a day, '
        'do not schedule it that day.');
    buffer.writeln('- Group places geographically so transitions are '
        'reasonable.');
    buffer.writeln('- Must-visits must appear exactly once and may not be '
        'replaced by invented alternatives.');
    buffer.writeln('- For each day, you MUST assign a unique, sequential '
        '"stopOrder" starting from 1. '
        'Example: "stopOrder": 1, "stopOrder": 2, ...');
    buffer.writeln('');

    // ── OUTPUT CONTRACT ─────────────────────────────────────────
    buffer.writeln('Return STRICT JSON ONLY (no Markdown fences, no extra '
        'text) with this exact structure:');
    buffer.writeln(_plannerJsonTemplate());

    return buffer.toString();
  }

  String _paceGuidance(String pace) {
    switch (pace) {
      case 'Slow':
        return 'Travel pace is Slow → prefer a relaxed schedule with more '
            'free time and avoid rushing. Fewer, longer activities are fine.';
      case 'Fast':
        return 'Travel pace is Fast → the traveler tolerates a denser '
            'schedule when geographically and temporally reasonable, but do '
            'not force it.';
      case 'Standard':
      default:
        return 'Travel pace is Standard → create a balanced itinerary that '
            'makes reasonable use of the exploration window without rushing.';
    }
  }

  String _plannerJsonTemplate() {
    return '''
{
  "days": [
    {
      "dayIndex": 1,
      "destinationId": "D001",
      "clusterId": 2,
      "reasoning": "Short explanation of why these places work well together.",
      "stops": [
        {
          "stopOrder": 1,
          "placeId": "EXACT_CANDIDATE_PLACE_ID",
          "startTime": "09:30",
          "endTime": "11:00",
          "visitDurationMinutes": 90,
          "travelFromPreviousMinutes": 0,
          "reason": "Good morning activity and close to the next attraction."
        }
      ]
    }
  ]
}
''';
  }

  /// Parses the raw planner JSON into a list of [AIDaySchedule].
  List<AIDaySchedule> _parsePlannerDays(String rawJson) {
    final cleaned = _normaliseModelText(rawJson);
    final data = jsonDecode(cleaned) as Map<String, dynamic>;
    final rawDays = data['days'];
    if (rawDays is! List) {
      throw const FormatException('AI planner output has no "days" array.');
    }

    final days = <AIDaySchedule>[];
    for (final rawDay in rawDays) {
      final map = rawDay as Map<String, dynamic>;
      final rawStops = map['stops'] ?? map['schedule'];
      final schedule = <AIScheduleStop>[];
      if (rawStops is List) {
        for (final rawStop in rawStops) {
          final s = rawStop as Map<String, dynamic>;
          schedule.add(AIScheduleStop(
            stopOrder: (s['stopOrder'] as num?)?.toInt() ?? 0,
            placeId: s['placeId'] as String? ?? '',
            startTime: s['startTime'] as String? ?? '',
            endTime: s['endTime'] as String? ?? '',
            visitDurationMinutes:
                (s['visitDurationMinutes'] as num?)?.toInt() ?? 0,
            travelFromPreviousMinutes:
                (s['travelFromPreviousMinutes'] as num?)?.toInt() ?? 0,
            scheduleReason: s['reason'] as String? ?? '',
            weatherNote: '',
          ));
        }
      }
      days.add(AIDaySchedule(
        dayIndex: (map['dayIndex'] as num?)?.toInt() ?? -1,
        date: map['date'] as String? ?? '',
        schedule: schedule,
        warnings: [
          if (map['reasoning'] != null) '${map['reasoning']}',
        ],
      ));
    }
    return days;
  }

  // ============================================================
  // 2. CHECK PUBLIC HOLIDAY
  // ============================================================

  Future<HolidayResult> checkPublicHoliday(DateTime date, String state) async {
    final prompt = '''
Is ${date.toString().split(' ').first} a public holiday in Malaysia${state != 'Malaysia' ? ', specifically in $state' : ''}?

Return valid JSON only:
{
  "is_holiday": true,
  "holiday_name": "Hari Merdeka",
  "is_national": true
}
''';

    final response = await _callAi(prompt);
    return HolidayResult.fromJson(response);
  }

  // ============================================================
  // 3. GET BEST TIME OF DAY
  // ============================================================

  Future<BestTimeResult> getBestTimeOfDay(Place place) async {
    final prompt = '''
When is the best time to visit ${place.name}?

Place: ${place.name}
Category: ${place.category}
Types: ${place.types.join(', ')}

Return valid JSON only:
{
  "best_time": "morning",
  "reason": "Morning is cooler and less crowded",
  "morning_score": 90,
  "afternoon_score": 60,
  "evening_score": 40
}
''';

    final response = await _callAi(prompt);
    return BestTimeResult.fromJson(response);
  }

  // ============================================================
  // 4. ITINERARY CRITIC (Human Comfort)
  // ============================================================

  Future<CriticResult> evaluateItinerary({
    required List<ScheduledDay> days,
    required String travelPace,
    required List<String> interests,
  }) async {
    final itineraryText = _formatItinerary(days);

    final prompt = '''
Evaluate this itinerary for human comfort.

User Preferences:
- Travel Pace: $travelPace
- Interests: ${interests.join(', ')}

Itinerary:
$itineraryText

Evaluate:
1. Is the pace appropriate for "$travelPace"?
2. Are meals at reasonable times?
3. Is there too much travel?
4. Does the daily flow feel natural?
5. Are activities appropriate for the weather?

Return valid JSON only:
{
  "overall_suitable": true,
  "score": 85,
  "issues": [
    {
      "day": 1,
      "severity": "medium",
      "description": "Day 2 has 6 activities, which is too many for Standard pace"
    }
  ],
  "recommendations": [
    {
      "day": 2,
      "action": "remove",
      "place": "National Museum",
      "reason": "Reduce activity count"
    }
  ],
  "summary": "Overall suitable with minor adjustments"
}
''';

    final response = await _callAi(prompt);
    return CriticResult.fromJson(response);
  }

  // ============================================================
  // 5. AI-ASSISTED ROUTE PLANNING
  // ============================================================

  Future<RoutePlanResult> planRoute({
    required int dayIndex,
    required List<String> candidatePlaceIds,
    required String travelPace,
    required List<String> interests,
    String? destinationName,
    // Add these new missing parameters:
    List<String> dietaryPreferences = const [],
    List<String> categoryExclusions = const [],
    String weatherCondition = 'Unknown',
  }) async {
    final prompt = '''
You are an itinerary route planner. You only decide the ORDER of places
for one day. You never invent places or factual data.

DAY ${dayIndex + 1}
Destination: ${destinationName ?? 'N/A'}
Travel pace: $travelPace
Traveler interests: ${interests.join(', ')}
Weather Condition today: $weatherCondition

USER PREFERENCES (STRICT FILTERS):
- Dietary: ${dietaryPreferences.isEmpty ? 'None' : dietaryPreferences.join(', ')}
- Exclusions: DO NOT include ${categoryExclusions.isEmpty ? 'None' : categoryExclusions.join(', ')}

The ONLY places available today (identified by their Google Place IDs):
${candidatePlaceIds.map((id) => ' - $id').join('\n')}

Return valid JSON only, using EXACTLY these placeId values and nothing else:
{
  "order": ["placeId1", "placeId2", "placeId3"],
  "reasoning": "Brief reasoning about sequence, meals, weather, and flow"
}
Rules:
- "order" must contain every provided placeId exactly once.
- Filter or push less ideal places to the end based on USER PREFERENCES.
- If the weather is Rain/Thunderstorm, prioritize indoor places first.
- Do NOT add placeIds that are not listed above.
- Do NOT include addresses, coordinates, ratings, or opening hours.
''';

    try {
      final response = await _callAi(prompt, timeout: aiRequestTimeout);
      print('[STEP 9 - AI ROUTE] raw response: $response');
      return RoutePlanResult.fromJson(response);
    } catch (e) {
      print('[STEP 9 - AI ROUTE] AI unavailable, using fallback: $e');
      return RoutePlanResult(
        order: List.of(candidatePlaceIds),
        reasoning: 'AI unavailable — deterministic order used.',
      );
    }
  }

// ============================================================
  // 6. AI-ASSISTED SCHEDULE CONSTRUCTION
  // ============================================================

  /// LEGACY per-day schedule formatter (kept ONLY for the "Add Custom
  /// Place" feature — CustomPlaceService → ScheduleConstructionService).
  ///
  /// DEPRECATED ARCHITECTURE: this builds a pre-computed schedule and asks
  /// the AI to copy times. The main itinerary-generation pipeline does NOT
  /// use this path — it uses [generatePlannedItinerary] / the structured
  /// planner prompt, where DeepSeek is the actual planner.
  @Deprecated('Legacy AI formatter for CustomPlaceService only. The main '
      'pipeline uses the AI planner architecture instead.')
  Future<AIDaySchedule> constructDaySchedule({
    required int dayIndex,
    required DateTime date,
    required String destinationName,
    required String explorationStart, // HH:mm
    required String explorationEnd,   // HH:mm
    required String travelPace,
    required List<Map<String, dynamic>> stops, // ordered stop facts
    String weatherCondition = 'Unknown',
    // Pass the window so the repair service can use it.
    ExplorationWindow? explorationWindow,
  }) async {
    // ── 1. Derive the window (minutes) used for validation/repair ────────────
    final windowStartParts = explorationStart.split(':');
    final windowEndParts = explorationEnd.split(':');

    final window = explorationWindow ??
        ExplorationWindow(
          startHour: int.parse(windowStartParts[0]),
          startMinute: int.parse(windowStartParts[1]),
          endHour: int.parse(windowEndParts[0]),
          endMinute: int.parse(windowEndParts[1]),
        );

    // ── 2. Build the strongly-worded prompt ──────────────────────────────────
    // Compute the ADJUSTED schedule (pace modifier + slack redistribution)
    // first, so the AI only ever sees the correct, window-filling times.
    final computed = _computeAdjustedSchedule(
      stops: stops,
      window: window,
      travelPace: travelPace,
    );

    final prompt = _buildSchedulePrompt(
      dayIndex: dayIndex,
      date: date,
      destinationName: destinationName,
      explorationStart: explorationStart,
      explorationEnd: explorationEnd,
      travelPace: travelPace,
      weatherCondition: weatherCondition,
      stopFacts: stops,
      computed: computed,
    );

    // ── 3. Call AI ────────────────────────────────────────────────────────────
    AIDaySchedule aiResult;
    try {
      final response = await _callAi(prompt);
      print('[STEP 8 - AI SCHEDULE] Day ${dayIndex + 1} raw: $response');
      aiResult = AIDaySchedule.fromJson(response);
    } catch (e) {
      print('[STEP 8 - AI SCHEDULE] AI failed Day ${dayIndex + 1}: $e');
      // Return fully deterministic schedule immediately.
      return _deterministicDay(
        dayIndex: dayIndex,
        date: date,
        stops: stops,
        window: window,
      );
    }

    // ── 4. Override dayIndex/date with caller-supplied values ─────────────────
    final rawSchedule = aiResult.schedule;

    // ── 5. Validate AI output ─────────────────────────────────────────────────
    final isValid = ScheduleRepairService.isValid(
      stops: rawSchedule,
      window: window,
    );

    print('[STEP 8 - VALIDATE] Day ${dayIndex + 1} valid=$isValid '
        '(${rawSchedule.length} stops)');

    // ── 6. Repair if needed ───────────────────────────────────────────────────
    final finalSchedule = isValid
        ? rawSchedule
        : ScheduleRepairService.repairSchedule(
            stops: rawSchedule,
            window: window,
            stopFacts: stops,
          );

    print('[STEP 8 - FINAL] Day ${dayIndex + 1}:');
    for (final s in finalSchedule) {
      print('   ${s.startTime} → ${s.endTime} : ${s.placeId}');
    }

    return AIDaySchedule(
      dayIndex: dayIndex,
      date: date.toIso8601String().split('T').first,
      schedule: finalSchedule,
      warnings: [
        ...aiResult.warnings,
        if (!isValid)
          'Schedule repaired to fit $explorationStart–$explorationEnd window',
      ],
      needsRepair: !isValid,
    );
  }

  /// Builds a deterministic [AIDaySchedule] from ground-truth stop facts.
  ///
  /// LEGACY fallback for [constructDaySchedule] (CustomPlaceService flow).
  /// Uses the SAME `_computeAdjustedSchedule()` as the AI prompt, so the
  /// deterministic fallback also applies the pace modifier, distributes
  /// slack, and ends at explorationEnd. It does NOT route through
  /// `ScheduleRepairService` with an empty stop list.
  @Deprecated('Legacy deterministic fallback for CustomPlaceService only.')
  AIDaySchedule _deterministicDay({
    required int dayIndex,
    required DateTime date,
    required List<Map<String, dynamic>> stops,
    required ExplorationWindow window,
  }) {
    final computed = _computeAdjustedSchedule(
      stops: stops,
      window: window,
      travelPace: 'Standard',
    );

    final schedule = computed.stops
        .map((cs) => AIScheduleStop(
              stopOrder: cs.stopOrder,
              placeId: cs.placeId,
              startTime: _minsToHHmm(cs.startMinute),
              endTime: _minsToHHmm(cs.endMinute),
              visitDurationMinutes: cs.visitDurationMinutes,
              travelFromPreviousMinutes: cs.travelFromPreviousMinutes,
              scheduleReason: 'Deterministic fallback (AI unavailable)',
              weatherNote: 'AI schedule unavailable — deterministic times used',
            ))
        .toList();

    return AIDaySchedule(
      dayIndex: dayIndex,
      date: date.toIso8601String().split('T').first,
      schedule: schedule,
      warnings: const ['AI unavailable — deterministic schedule used'],
      needsRepair: schedule.isEmpty,
    );
  }

  /// Forward pass with pace modifier + slack redistribution.
  ///
  /// LEGACY helper used by [constructDaySchedule] / [_deterministicDay]
  /// (CustomPlaceService flow). Not used by the main pipeline.
  ///
  /// 1. Apply the pace modifier to each base visit duration.
  /// 2. Chain stops forward (start at window start).
  /// 3. Compute slack = window span − used time.
  /// 4. Distribute slack evenly; the last stop absorbs the remainder so the
  ///    final stop ends at explorationEnd exactly.
  ///
  /// If slack is negative (the schedule already overflows the window),
  /// visits are NOT shrunk — the caller (repair service) handles overflow.
  @Deprecated('Legacy formatter helper for CustomPlaceService only.')
  _ComputedSchedule _computeAdjustedSchedule({
    required List<Map<String, dynamic>> stops,
    required ExplorationWindow window,
    required String travelPace,
  }) {
    final buffer = ItineraryConstants.bufferForPace(travelPace);
    final factor = ItineraryConstants.durationFactorForPace(travelPace);
    final winStart = window.startHour * 60 + window.startMinute;
    final winEnd = window.endHour * 60 + window.endMinute;
    final windowSpan = winEnd - winStart;

    // ── Forward pass (pace-modified) ─────────────────────────────
    final baseVisit = <int>[];
    final travel = <int>[];
    final pacedVisit = <int>[];
    final rawStart = <int>[];
    final rawEnd = <int>[];
    var cursor = winStart;

    for (int i = 0; i < stops.length; i++) {
      final s = stops[i];
      final base = (s['visitDurationMinutes'] as num?)?.toInt() ?? 60;
      baseVisit.add(base);
      travel.add(i == 0 ? 0 : ((s['travelFromPreviousMinutes'] as num?)?.toInt() ?? buffer));
      pacedVisit.add((base * factor).round());

      final start = i == 0 ? winStart : cursor + travel[i] + buffer;
      final end = start + pacedVisit[i];
      rawStart.add(start);
      rawEnd.add(end);
      cursor = end;
    }

    final n = stops.length;
    final usedMins = n == 0 ? 0 : (rawEnd.last - winStart);
    final slack = windowSpan - usedMins;

    // ── Redistribute slack (only when positive) ──────────────────
    final adjVisit = List<int>.from(pacedVisit);
    if (slack > 0 && n > 0) {
      final slackPerStop = slack ~/ n;
      final remainder = slack - (slackPerStop * n);
      for (int i = 0; i < n; i++) {
        adjVisit[i] += slackPerStop;
      }
      adjVisit[n - 1] += remainder; // last stop absorbs remainder
    }

    // ── Rebuild times with adjusted visits ───────────────────────
    final computed = <_ComputedStop>[];
    cursor = winStart;
    for (int i = 0; i < n; i++) {
      final start = i == 0 ? winStart : cursor + travel[i] + buffer;
      final end = start + adjVisit[i];
      computed.add(_ComputedStop(
        stopOrder: i + 1,
        placeId: stops[i]['placeId'] as String? ?? '',
        name: stops[i]['name'] as String? ?? '',
        baseVisitMinutes: baseVisit[i],
        paceVisitMinutes: pacedVisit[i],
        visitDurationMinutes: adjVisit[i],
        travelFromPreviousMinutes: i == 0 ? 0 : travel[i],
        bufferMinutes: i == 0 ? 0 : buffer,
        startMinute: start,
        endMinute: end,
      ));
      cursor = end;
    }

    return _ComputedSchedule(
      windowStartMinute: winStart,
      windowEndMinute: winEnd,
      bufferMinutes: buffer,
      usedMins: usedMins,
      slackMins: slack,
      stops: computed,
    );
  }

  /// Builds the full AI prompt using the ADJUSTED (paced + slack-adjusted)
  /// schedule. The AI is a FORMATTER, never a planner.
  String _buildSchedulePrompt({
    required int dayIndex,
    required DateTime date,
    required String destinationName,
    required String explorationStart,
    required String explorationEnd,
    required String travelPace,
    required String weatherCondition,
    required List<Map<String, dynamic>> stopFacts,
    required _ComputedSchedule computed,
  }) {
    final wStart = computed.windowStartMinute;
    final wEnd = computed.windowEndMinute;

    // Build the MANDATORY TABLE + chain proof per stop.
    final tableLines = StringBuffer();
    final proofLines = StringBuffer();
    for (int i = 0; i < computed.stops.length; i++) {
      final cs = computed.stops[i];
      final prev = i > 0 ? computed.stops[i - 1] : null;
      tableLines.writeln(
        '  Stop ${cs.stopOrder}: ${_minsToHHmm(cs.startMinute)} → '
            '${_minsToHHmm(cs.endMinute)} | ${cs.name} '
            '(visit=${cs.visitDurationMinutes}min, '
            'travel=${cs.travelFromPreviousMinutes}min, '
            'buffer=${cs.bufferMinutes}min)',
      );

      if (i == 0) {
        proofLines.writeln(
          '  Stop 1: startTime = $explorationStart (window start) '
              'adjVisit = ${cs.visitDurationMinutes}min '
              'endTime = ${_minsToHHmm(cs.startMinute)} + '
              '${cs.visitDurationMinutes}min = ${_minsToHHmm(cs.endMinute)}',
        );
      } else {
        proofLines.writeln(
          '  Stop ${cs.stopOrder}: '
              'startTime = ${_minsToHHmm(prev!.endMinute)} (prev end) + '
              '${cs.travelFromPreviousMinutes}min travel + '
              '${cs.bufferMinutes}min buffer = ${_minsToHHmm(cs.startMinute)} '
              'adjVisit = ${cs.paceVisitMinutes}min paced + '
              '${cs.visitDurationMinutes - cs.paceVisitMinutes}min slack = '
              '${cs.visitDurationMinutes}min '
              'endTime = ${_minsToHHmm(cs.startMinute)} + '
              '${cs.visitDurationMinutes}min = ${_minsToHHmm(cs.endMinute)}',
        );
      }
    }

    final adjFacts = stopFacts.asMap().entries.map((e) {
      final i = e.key;
      final s = e.value;
      final cs = computed.stops[i];
      return '  ${s['placeId']} | ${s['name']} | '
          'Your times: ${_minsToHHmm(cs.startMinute)} → '
          '${_minsToHHmm(cs.endMinute)} '
          '(${cs.visitDurationMinutes}min adjusted visit) | '
          'travelFromPrev=${cs.travelFromPreviousMinutes}min';
    }).join('\n');

    final maxStopsNote = 'The window from $explorationStart to '
        '$explorationEnd is the ONLY constraint on how many stops fit. '
        'The pre-computed MANDATORY TABLE already contains the correct '
        'stop count. Do NOT add or remove stops.';

    return '''
════════════════════════════════════════════════════════════════
ROLE: YOU ARE A SCHEDULE FORMATTER, NOT A PLANNER.
All times have been pre-calculated. Your only job is to copy them
into JSON and write a scheduleReason and weatherNote for each stop.
You must NOT invent, recalculate, or re-plan any times.
════════════════════════════════════════════════════════════════

FIXED SCHEDULING PARAMETERS (use these EXACT numbers)
Exploration window: $explorationStart → $explorationEnd
Travel pace: $travelPace
Fixed transition buffer: ${computed.bufferMinutes} minutes (EXACT, no ranges)

WINDOW MATH
  Window span  = $explorationEnd − $explorationStart = ${wEnd - wStart} min
  Used time    = ${computed.usedMins} min
  Slack        = ${computed.slackMins} min
  If slack > 0, it was distributed evenly across stops; the last stop
  absorbed the remainder so the final stop ends at $explorationEnd exactly.

$maxStopsNote

CHAIN PROOF (arithmetic for every stop):
$proofLines

MANDATORY TIME TABLE — COPY THESE VALUES EXACTLY
⚠️ These values are NON-NEGOTIABLE.
$tableLines

DAY ${dayIndex + 1}
Date: ${date.toIso8601String().split('T').first}
Destination: $destinationName
Weather: $weatherCondition

STOP DETAILS (with ADJUSTED times):
$adjFacts

Write scheduleReason and weatherNote only.
Do NOT use the base duration. Use adjVisit (the adjusted time above).

MEAL TIMING (food stops only, minimal adjustment):
• Lunch window: 11:00–14:00
• Dinner window: 17:00–21:00
• If a food stop cannot reach its meal window without breaking the
  chain, keep the chained time and mark "needsRepair": true.

OPENING HOURS:
• If opening-hours data is available and the place is closed that day,
  exclude it from the schedule.
• If opening-hours data is NOT available, include it if it otherwise fits.

SELF-CHECK — COMPLETE BEFORE RETURNING JSON (fix any failure):
  Check 1: schedule[0].startTime == "$explorationStart"?
  Check 2: schedule[last].endTime == "$explorationEnd"?
  Check 3: Every startTime matches the MANDATORY TABLE?
  Check 4: Every endTime matches the MANDATORY TABLE?
  Check 5: Every placeId copied exactly from input?
  Check 6: stopOrder sequential from 1?
  Check 7: No stop endTime exceeds "$explorationEnd"?
  Check 8: JSON valid with no trailing commas?
  If ANY check fails → fix it before returning.

Return valid JSON only (no Markdown fences):
{
  "dayIndex": ${dayIndex + 1},
  "date": "${date.toIso8601String().split('T').first}",
  "schedule": [
    {
      "stopOrder": 1,
      "placeId": "EXACT_ID_FROM_INPUT",
      "startTime": "$explorationStart",
      "endTime": "HH:mm",
      "visitDurationMinutes": 60,
      "travelFromPreviousMinutes": 0,
      "scheduleReason": "short reason",
      "weatherNote": "weather note"
    }
  ],
  "warnings": [],
  "needsRepair": <true if you changed ANY time value or skipped ANY stop,
                 false only if you copied ALL values exactly from the
                 MANDATORY TABLE>
}
''';
  }

  String _minsToHHmm(int mins) {
    final h = (mins ~/ 60).clamp(0, 23);
    final m = (mins % 60).clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
  // ============================================================
  // AI PROVIDERS: B.AI (DeepSeek) → OpenRouter → Cohere
  // ============================================================

  Future<String> _callAi(String prompt, {Duration timeout = aiRequestTimeout}) async {
    debugPrint('[AI REQUEST]');
    debugPrint('Provider: B.AI (DeepSeek)');
    debugPrint('Model: $baiModel');
    debugPrint('Prompt characters: ${prompt.length}');
    debugPrint('Timeout: ${timeout.inSeconds}s');

    // 1. Try B.AI Gateway (DeepSeek)
    if (baiApiKey.isNotEmpty && baiModel.isNotEmpty) {
      try {
        return await _callBai(prompt, timeout: timeout);
      } catch (error) {
        debugPrint('[AI FALLBACK]');
        debugPrint('Primary provider failed: B.AI — $error');
        debugPrint('Trying: OpenRouter');
      }
    }

    // 2. Try OpenRouter
    if (openRouterApiKey.isNotEmpty &&
        openRouterApiKey.startsWith('sk-or-v1-')) {
      try {
        return await _callOpenRouter(prompt, timeout: fallbackProviderTimeout);
      } catch (error) {
        debugPrint('[AI FALLBACK]');
        debugPrint('OpenRouter failed: $error');
        debugPrint('Trying: Cohere');
      }
    }

    // 3. Try Cohere
    if (cohereApiKey.isNotEmpty) {
      try {
        return await _callCohere(prompt, timeout: fallbackProviderTimeout);
      } catch (error) {
        debugPrint('Cohere failed: $error');
      }
    }

    throw Exception(
      'All AI providers failed. Check your API keys and network.',
    );
  }

  // ---------- B.AI Gateway (DeepSeek V4) ----------

  Future<String> _callBai(String prompt, {Duration timeout = aiRequestTimeout}) async {
    try {
      // Try with structured JSON output first. Some gateways reject
      // `response_format`, so fall back to a plain request on failure.
      try {
        return await _postBai(prompt, enforceJson: true, timeout: timeout);
      } catch (e) {
        debugPrint('⚠️ [B.AI] structured JSON request failed — retrying plain: $e');
        return await _postBai(prompt, enforceJson: false, timeout: timeout);
      }
    } catch (e) {
      // 🛑 Catch and print the exact reason for failure before rethrowing
      debugPrint('❌ [_callBai CRITICAL ERROR]: $e');
      rethrow;
    }
  }

  Future<String> _postBai(String prompt,
      {required bool enforceJson, Duration timeout = aiRequestTimeout}) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final response = await http.post(
        Uri.parse(_baiBaseUrl),
        headers: {
          'Authorization': 'Bearer $baiApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': baiModel, // 'deepseek-v4-flash' or 'deepseek-v4-pro'
          'messages': [
            {
              'role': 'system',
              'content':
              'Follow the requested output format exactly. If JSON is requested, return JSON only without Markdown fences.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.2,
          'max_tokens': 8192,
          'reasoning': {'effort': 'low'},
          'stream': false,
          if (enforceJson) 'response_format': {'type': 'json_object'},
        }),
      ).timeout(timeout);

      debugPrint('[AI RESPONSE]');
      debugPrint('Provider: B.AI (DeepSeek)');
      debugPrint('Status: ${response.statusCode}');
      debugPrint('Response characters: ${response.body.length}');
      debugPrint('Elapsed: ${sw.elapsedMilliseconds}ms');

      if (response.statusCode != 200) {
        throw Exception(
          'B.AI error (${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final message = (choices.first as Map)['message'];
        if (message is Map) {
          final content = message['content'];
          if (content is String && content.trim().isNotEmpty) {
            final normalised = _normaliseModelText(content);
            if (normalised.trim().isEmpty) {
              throw const FormatException(
                'B.AI returned a 200 OK, but the JSON content was entirely empty.',
              );
            }
            debugPrint('[AI RESPONSE] content parsed (${normalised.length} chars)');
            return normalised;
          }

          throw const FormatException(
            'B.AI returned 200 OK but `content` is empty. The model produced '
            'only reasoning_content — refusing to treat reasoning text as the answer.',
          );
        }
      }

      throw const FormatException('B.AI returned no text content.');
    } on TimeoutException {
      debugPrint('[AI TIMEOUT]');
      debugPrint('Provider: B.AI (DeepSeek)');
      debugPrint('Timeout: ${timeout.inSeconds}s');
      debugPrint('Prompt characters: ${prompt.length}');
      rethrow;
    }
  }

  // ---------- OpenRouter ----------

  Future<String> _callOpenRouter(String prompt,
      {Duration timeout = fallbackProviderTimeout}) async {
    if (!openRouterApiKey.startsWith('sk-or-v1-')) {
      throw StateError('OpenRouter API key is invalid.');
    }

    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $openRouterApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'openrouter/free',
        'messages': [
          {
            'role': 'system',
            'content':
            'Follow the requested output format exactly. If JSON is requested, return JSON only without Markdown fences.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.2,
      }),
    ).timeout(timeout);

    debugPrint('[AI RESPONSE]');
    debugPrint('Provider: OpenRouter');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Response characters: ${response.body.length}');

    if (response.statusCode != 200) {
      throw Exception(
        'OpenRouter error (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return _normaliseModelText(message['content'] as String);
      }
    }

    throw const FormatException('OpenRouter returned no text content.');
  }

  // ---------- Cohere ----------

  Future<String> _callCohere(String prompt,
      {Duration timeout = fallbackProviderTimeout}) async {
    if (cohereApiKey.isEmpty) {
      throw StateError('Cohere API key is missing.');
    }

    final response = await http.post(
      Uri.parse('https://api.cohere.com/v2/chat'),
      headers: {
        'Authorization': 'Bearer $cohereApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'command-r-08-2024',
        'messages': [
          {
            'role': 'system',
            'content':
            'Follow the requested output format exactly. If JSON is requested, return JSON only without Markdown fences.',
          },
          {'role': 'user', 'content': prompt},
        ],
      }),
    ).timeout(timeout);

    debugPrint('[AI RESPONSE]');
    debugPrint('Provider: Cohere');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Response characters: ${response.body.length}');

    if (response.statusCode != 200) {
      throw Exception('Cohere error (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final message = data['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is List && content.isNotEmpty && content.first is Map) {
        final text = (content.first as Map)['text'];
        if (text is String && text.trim().isNotEmpty) {
          return _normaliseModelText(text);
        }
      }
    }

    throw const FormatException('Cohere returned no text content.');
  }

  // ---------- Helpers ----------

  String _normaliseModelText(String text) {
    var value = text.trim();

    // Remove Markdown code fences
    if (value.startsWith('```')) {
      value = value
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }

    // For JSON results, extract the actual JSON object.
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return value.substring(start, end + 1);
    }

    return value;
  }

  String _formatItinerary(List<ScheduledDay> days) {
    final buffer = StringBuffer();
    for (final day in days) {
      buffer.writeln('Day ${day.dayIndex + 1} - ${day.date}');
      for (final stop in day.stops) {
        final s = stop.startTime;
        final e = stop.endTime;
        buffer.writeln(
          '  ${s.hour.toString().padLeft(2, '0')}:'
              '${s.minute.toString().padLeft(2, '0')} - '
              '${e.hour.toString().padLeft(2, '0')}:'
              '${e.minute.toString().padLeft(2, '0')} '
              '${stop.attraction.place.name} (${stop.durationMinutes} min)',
        );
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

// ============================================================
// RESULT CLASSES (unchanged)
// ============================================================

class HolidayResult {
  final bool isHoliday;
  final String? holidayName;
  final bool isNational;

  const HolidayResult({
    required this.isHoliday,
    this.holidayName,
    this.isNational = false,
  });

  factory HolidayResult.fromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return HolidayResult(
        isHoliday: data['is_holiday'] ?? false,
        holidayName: data['holiday_name'],
        isNational: data['is_national'] ?? false,
      );
    } catch (_) {
      return const HolidayResult(isHoliday: false);
    }
  }
}

class BestTimeResult {
  final String bestTime;
  final String reason;
  final int morningScore;
  final int afternoonScore;
  final int eveningScore;

  const BestTimeResult({
    required this.bestTime,
    required this.reason,
    required this.morningScore,
    required this.afternoonScore,
    required this.eveningScore,
  });

  factory BestTimeResult.fromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return BestTimeResult(
        bestTime: data['best_time'] ?? 'morning',
        reason: data['reason'] ?? 'Check local conditions',
        morningScore: data['morning_score'] ?? 70,
        afternoonScore: data['afternoon_score'] ?? 50,
        eveningScore: data['evening_score'] ?? 30,
      );
    } catch (_) {
      return const BestTimeResult(
        bestTime: 'morning',
        reason: 'Default recommendation',
        morningScore: 70,
        afternoonScore: 50,
        eveningScore: 30,
      );
    }
  }
}

class CriticResult {
  final bool overallSuitable;
  final int score;
  final List<CriticIssue> issues;
  final List<CriticRecommendation> recommendations;
  final String summary;

  const CriticResult({
    required this.overallSuitable,
    required this.score,
    required this.issues,
    required this.recommendations,
    required this.summary,
  });

  factory CriticResult.fromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return CriticResult(
        overallSuitable: data['overall_suitable'] ?? true,
        score: data['score'] ?? 80,
        issues: (data['issues'] as List?)
            ?.map((i) => CriticIssue.fromJson(i as Map<String, dynamic>))
            .toList() ??
            [],
        recommendations: (data['recommendations'] as List?)
            ?.map((r) => CriticRecommendation.fromJson(r as Map<String, dynamic>))
            .toList() ??
            [],
        summary: data['summary'] ?? 'No major issues.',
      );
    } catch (_) {
      return const CriticResult(
        overallSuitable: true,
        score: 80,
        issues: [],
        recommendations: [],
        summary: 'Unable to parse critic review.',
      );
    }
  }
}

class CriticIssue {
  final int day;
  final String severity;
  final String description;

  const CriticIssue({
    required this.day,
    required this.severity,
    required this.description,
  });

  factory CriticIssue.fromJson(Map<String, dynamic> json) {
    return CriticIssue(
      day: json['day'] ?? 0,
      severity: json['severity'] ?? 'low',
      description: json['description'] ?? 'Unknown issue',
    );
  }
}

class CriticRecommendation {
  final int day;
  final String action;
  final String? place;
  final String reason;

  const CriticRecommendation({
    required this.day,
    required this.action,
    this.place,
    required this.reason,
  });

  factory CriticRecommendation.fromJson(Map<String, dynamic> json) {
    return CriticRecommendation(
      day: json['day'] ?? 0,
      action: json['action'] ?? 'none',
      place: json['place'],
      reason: json['reason'] ?? 'No reason provided',
    );
  }
}

class RoutePlanResult {
  final List<String> order;
  final String reasoning;

  RoutePlanResult({required this.order, this.reasoning = ''});

  factory RoutePlanResult.fromJson(String json) {
    // 1. Strip out any Markdown code blocks that DeepSeek might have added
    final cleanJson = json.replaceAll('```json', '').replaceAll('```', '').trim();

    // 2. Parse the JSON WITHOUT a try/catch block here.
    // We WANT it to crash and throw an error up to planRoute if it fails!
    final data = jsonDecode(cleanJson) as Map<String, dynamic>;

    return RoutePlanResult(
      order: (data['order'] as List).cast<String>(),
      reasoning: data['reasoning'] as String? ?? '',
    );
  }
}

// ============================================================
// 6. AI-ASSISTED SCHEDULE CONSTRUCTION
// ============================================================

/// A single scheduled stop returned by the AI for a day.
class AIScheduleStop {
  final int stopOrder;
  final String placeId;
  final String startTime;
  final String endTime;
  final int visitDurationMinutes;
  final int travelFromPreviousMinutes;
  final String scheduleReason;
  final String weatherNote; // <-- Add this line

  const AIScheduleStop({
    required this.stopOrder,
    required this.placeId,
    required this.startTime,
    required this.endTime,
    required this.visitDurationMinutes,
    this.travelFromPreviousMinutes = 0,
    this.scheduleReason = '',
    this.weatherNote = '', // <-- Add this line
  });
}

/// The AI schedule result for a single day.
class AIDaySchedule {
  final int dayIndex;
  final String date;
  final List<AIScheduleStop> schedule;
  final List<String> warnings;
  final bool needsRepair;

  const AIDaySchedule({
    required this.dayIndex,
    required this.date,
    required this.schedule,
    this.warnings = const [],
    this.needsRepair = false,
  });

  factory AIDaySchedule.fromJson(String json) {
    // FIX: Do NOT swallow parse errors into a fake `dayIndex: 0` schedule.
    // Rethrow so `constructDaySchedule` can build a proper fallback with the
    // authoritative day index + date (this is what fixes the "DAY 0" bug).
    final data = jsonDecode(json) as Map<String, dynamic>;
    final rawSchedule = data['schedule'];
    final scheduleList = (rawSchedule is List)
        ? rawSchedule.map((s) {
            final m = s as Map<String, dynamic>;
            return AIScheduleStop(
              stopOrder: (m['stopOrder'] as num?)?.toInt() ?? 0,
              placeId: m['placeId'] as String? ?? '',
              startTime: m['startTime'] as String? ?? '09:00',
              endTime: m['endTime'] as String? ?? '10:00',
              visitDurationMinutes: (m['visitDurationMinutes'] as num?)?.toInt() ?? 60,
              travelFromPreviousMinutes: (m['travelFromPreviousMinutes'] as num?)?.toInt() ?? 0,
              scheduleReason: m['scheduleReason'] as String? ?? '',
              weatherNote: m['weatherNote'] as String? ?? '',
            );
          }).toList()
        : <AIScheduleStop>[];
    return AIDaySchedule(
      dayIndex: (data['dayIndex'] as num?)?.toInt() ?? 0,
      date: data['date'] as String? ?? '',
      schedule: scheduleList,
      warnings: (data['warnings'] as List?)?.cast<String>() ?? [],
      needsRepair: data['needsRepair'] as bool? ?? false,
    );
  }
}


/// Result of the AI schedule construction for all days.
class AIScheduleResult {
  final List<AIDaySchedule> days;
  final bool success;

  const AIScheduleResult({
    required this.days,
    required this.success,
  });
}

/// One computed (adjusted) stop used to build the mandatory table and the
/// deterministic fallback.
class _ComputedStop {
  final int stopOrder;
  final String placeId;
  final String name;
  final int baseVisitMinutes;
  final int paceVisitMinutes; // after pace modifier, before slack
  final int visitDurationMinutes; // after pace + slack
  final int travelFromPreviousMinutes;
  final int bufferMinutes;
  final int startMinute;
  final int endMinute;

  const _ComputedStop({
    required this.stopOrder,
    required this.placeId,
    required this.name,
    required this.baseVisitMinutes,
    required this.paceVisitMinutes,
    required this.visitDurationMinutes,
    required this.travelFromPreviousMinutes,
    required this.bufferMinutes,
    required this.startMinute,
    required this.endMinute,
  });
}

/// The computed day schedule with window + slack metadata.
class _ComputedSchedule {
  final int windowStartMinute;
  final int windowEndMinute;
  final int bufferMinutes;
  final int usedMins;
  final int slackMins;
  final List<_ComputedStop> stops;

  const _ComputedSchedule({
    required this.windowStartMinute,
    required this.windowEndMinute,
    required this.bufferMinutes,
    required this.usedMins,
    required this.slackMins,
    required this.stops,
  });
}

// ============================================================
// AI ITINERARY PLANNER — INPUT CLASSES
// ============================================================

/// Trip-level context for the AI planner.
class AIPlannerTripContext {
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final List<AIPlannerDestination> destinations;
  final String explorationStart; // HH:mm
  final String explorationEnd;   // HH:mm
  final String travelPace;
  final String transportationMode;
  final String travelType;
  final List<String> interests;
  final String? weatherCondition;
  final Map<String, String>? travelTimes; // "A→B" → "15 min"

  const AIPlannerTripContext({
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.destinations,
    required this.explorationStart,
    required this.explorationEnd,
    required this.travelPace,
    required this.transportationMode,
    this.travelType = 'Solo',
    this.interests = const [],
    this.weatherCondition,
    this.travelTimes,
  });
}

/// A single destination with its day allocation.
class AIPlannerDestination {
  final String destinationId;
  final String destinationName;
  final int allocatedDays;

  const AIPlannerDestination({
    required this.destinationId,
    required this.destinationName,
    required this.allocatedDays,
  });
}

/// A single candidate place as seen by the AI planner.
class AIPlannerCandidate {
  final String placeId;
  final String name;
  final String? destinationId;
  final String? destinationName;
  final int? clusterId;
  final double latitude;
  final double longitude;
  final String? category;
  final List<String> types;
  final double rating;
  final double? interestScore;
  final double? finalScore;
  final bool isMustVisit;
  final int? visitDurationMinutes;
  final String? openingHours;
  final String? bestTimeSuggestion;

  const AIPlannerCandidate({
    required this.placeId,
    required this.name,
    this.destinationId,
    this.destinationName,
    this.clusterId,
    required this.latitude,
    required this.longitude,
    this.category,
    this.types = const [],
    this.rating = 0.0,
    this.interestScore,
    this.finalScore,
    this.isMustVisit = false,
    this.visitDurationMinutes,
    this.openingHours,
    this.bestTimeSuggestion,
  });
}

/// A geographic cluster of candidates.
class AIPlannerCluster {
  final int clusterId;
  final String? destinationId;
  final double centerLatitude;
  final double centerLongitude;
  final List<String> candidatePlaceIds;

  const AIPlannerCluster({
    required this.clusterId,
    this.destinationId,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.candidatePlaceIds,
  });
}

/// Result of the AI itinerary planner.
class AIItineraryPlanningResult {
  final bool success;
  final String? errorMessage;
  final List<AIDaySchedule>? days;

  const AIItineraryPlanningResult({
    required this.success,
    this.errorMessage,
    this.days,
  });
}

