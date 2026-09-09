// lib/model/business_logic/itinerary_service/ai_prompt_builder.dart
//
// Builds the structured DeepSeek context prompt for itinerary scheduling.
//
// DeepSeek is responsible for CONTEXT-AWARE scheduling: which day a
// candidate belongs to, stop order, times, restaurant placement, and
// schedule density. Flutter provides constraints, facts and candidate data;
// DeepSeek must NOT invent places or ignore destination day allocation.

import 'dart:convert';

import '../../../core/config/itinerary_constants.dart';
import '../../entities/trip_draft.dart';
import '../../entities/weather.dart';
import './clustering_service.dart';

/// Structured context for a single candidate place.
class AiCandidateContext {
  final String placeId;
  final String name;
  final String destination;
  final int? clusterId;
  final String? category;
  final double rating;
  final double finalScore;
  final bool isMustVisit;
  final int? visitDurationMinutes;
  final String? openingHours;
  final String? bestTimeSuggestion;
  final double latitude;
  final double longitude;

  const AiCandidateContext({
    required this.placeId,
    required this.name,
    required this.destination,
    this.clusterId,
    this.category,
    required this.rating,
    required this.finalScore,
    required this.isMustVisit,
    this.visitDurationMinutes,
    this.openingHours,
    this.bestTimeSuggestion,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
    'place_id': placeId,
    'name': name,
    'destination': destination,
    'cluster_id': clusterId,
    'category': category,
    'rating': rating,
    'final_score': finalScore,
    'is_must_visit': isMustVisit,
    'visit_duration_minutes': visitDurationMinutes,
    'opening_hours': openingHours ?? 'unknown',
    'best_time_suggestion': bestTimeSuggestion ?? 'unknown',
    'latitude': latitude,
    'longitude': longitude,
  };
}

/// Builds the structured DeepSeek prompt.
class AiPromptBuilder {
  /// Build the full scheduling prompt.
  ///
  /// [tripLocation] is the traveler's hub when known. [routeInfo] may carry
  /// travel times/distances between candidates when a travel service
  /// provides them (the builder only prints what it is given — it never
  /// fabricates travel data).
  String buildSchedulePrompt({
    required TripDraft request,
    required List<AiCandidateContext> candidates,
    required List<Cluster> clusters,
    Map<String, String>? routeInfo,
  }) {
    final buffer = StringBuffer();

    // ── TRIP ─────────────────────────────────────────────────────
    buffer.writeln('TRIP');
    buffer.writeln('- total_days: ${request.totalDays}');
    if (request.startDate != null) {
      buffer.writeln('- start_date: ${request.startDate!.toIso8601String().split('T').first}');
    }
    if (request.endDate != null) {
      buffer.writeln('- end_date: ${request.endDate!.toIso8601String().split('T').first}');
    }
    buffer.writeln('- destinations: ${request.destinationNames.join(', ')}');
    buffer.writeln('- allocated_days_per_destination: '
        '${_formatDaySplit(request)}');
    buffer.writeln('- travel_type: ${request.travelType ?? 'Solo'}');
    buffer.writeln('- interests: ${request.interests.isEmpty ? 'none' : request.interests.join(', ')}');
    buffer.writeln('- travel_pace: ${request.pace ?? 'Standard'}');
    buffer.writeln('- exploration_time: ${request.exploration ?? 'Standard'}');
    buffer.writeln('- transportation_mode: ${request.transportation}');
    buffer.writeln('');

    // ── MUST-VISITS ──────────────────────────────────────────────
    buffer.writeln('MUST-VISITS (all mandatory — must appear EXACTLY once)');
    final mustVisits = candidates.where((c) => c.isMustVisit).toList();
    if (mustVisits.isEmpty) {
      buffer.writeln('- none');
    } else {
      for (final c in mustVisits) {
        buffer.writeln(
          '- place_id: ${c.placeId} | name: ${c.name} '
              '| destination: ${c.destination} | mandatory: true',
        );
      }
    }
    buffer.writeln('');

    // ── CANDIDATES ───────────────────────────────────────────────
    buffer.writeln('CANDIDATES (select from these ONLY — never invent places)');
    for (final c in candidates) {
      buffer.writeln(jsonEncode(c.toJson()));
    }
    buffer.writeln('');

    // ── CLUSTER INFORMATION ──────────────────────────────────────
    buffer.writeln('CLUSTER INFORMATION (geographic groups, NOT days)');
    for (final cluster in clusters) {
      final names = cluster.attractions
          .map((a) => a.place.placeName)
          .join(', ');
      buffer.writeln(
        '- cluster ${cluster.dayIndex}: '
            'center=(${cluster.center.latitude.toStringAsFixed(4)}, '
            '${cluster.center.longitude.toStringAsFixed(4)}) '
            'places: $names',
      );
    }
    buffer.writeln('');

    // ── ROUTE INFORMATION ────────────────────────────────────────
    buffer.writeln('ROUTE INFORMATION (travel times if available)');
    if (routeInfo == null || routeInfo.isEmpty) {
      buffer.writeln(
        '- no travel matrix provided. Rely on coordinates and clusters. '
            'The validator will check route feasibility when data exists.',
      );
    } else {
      for (final entry in routeInfo.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
    }
    buffer.writeln('');

    // ── CONSTRAINTS ──────────────────────────────────────────────
    buffer.writeln('HARD CONSTRAINTS');
    buffer.writeln(
      '- Every day must stay within the exploration window: '
          '${_windowText(request.exploration)}.',
    );
    buffer.writeln('- Destination day allocation must be respected exactly.');
    buffer.writeln(
      '- Consider opening hours, visit duration, travel pace, '
          'transportation mode, weather and user interests.',
    );
    buffer.writeln('');

    buffer.writeln(
      '- For each day, you MUST assign a unique, sequential "stopOrder" starting from 1.',
    );
    buffer.writeln('  Example: "stopOrder": 1, "stopOrder": 2, ...');
    buffer.writeln('');

    // ── OUTPUT CONTRACT ──────────────────────────────────────────
    buffer.writeln(
      'Return STRICT JSON ONLY (no Markdown fences, no extra text):',
    );
    buffer.writeln(_jsonTemplate());

    return buffer.toString();
  }

  String _formatDaySplit(TripDraft request) {
    if (request.daySplit.isNotEmpty) {
      final parts = request.daySplit.entries
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      return '{ $parts }';
    }
    if (request.destinationNames.isEmpty || request.totalDays <= 0) {
      return 'not provided — split evenly across all destinations';
    }
    final base = request.totalDays ~/ request.destinationNames.length;
    final extra = request.totalDays % request.destinationNames.length;
    final parts = <String>[];
    for (int i = 0; i < request.destinationNames.length; i++) {
      final dest = request.destinationNames[i];
      parts.add('$dest=${base + (i < extra ? 1 : 0)}');
    }
    return '{ ${parts.join(', ')} }';
  }

  // ============================================================
  // COMPACT PLANNER PROMPT (optimized architecture)
  // ============================================================
  //
  // DeepSeek is now asked to do ONLY what benefits from AI: select, group
  // and order places, matching interests and travel pace, with a short
  // reason. It returns ONLY { dayIndex, placeIds[], reason }. All start/end
  // times, visit durations, travel times, stop ordering, validation and
  // repair are computed deterministically by Dart afterwards. This shrinks
  // the prompt (≈5–8k chars) and the output (≈150–300 tokens), which is what
  // makes a 5–15s normal response achievable.

  /// Builds the compact DeepSeek planning prompt.
  ///
  /// [mustVisitIds] are the verified must-visit place IDs. [candidates] is
  /// the reduced (~12–20) high-quality pool and [clusters] the geographic
  /// groups — both already produced by the Dart scoring/clustering pipeline.
  String buildCompactPlanPrompt({
    required TripDraft request,
    required List<AiCandidateContext> candidates,
    required List<Cluster> clusters,
    required List<String> mustVisitIds,
    WeatherForecast? weatherForecast,
  }) {
    final pace = request.pace ?? 'Standard';
    final buffer = StringBuffer();

    // ── DETERMINE TARGET STOPS PER DAY ───────────────────────────
    int targetStopsPerDay;
    switch (pace) {
      case 'Slow':
        targetStopsPerDay = 4; // Breakfast, Sight, Lunch, Dinner
        break;
      case 'Fast':
        targetStopsPerDay = 6; // Breakfast, 2 Sights, Lunch, Sight, Dinner
        break;
      default:
        targetStopsPerDay = 5; // Breakfast, Morning Sight, Lunch, Afternoon Sight, Dinner
    }

    // ── PROMPT HEADER ────────────────────────────────────────────
    buffer.writeln('You are an expert travel itinerary planner.');
    buffer.writeln('Create a multi-day, balanced itinerary using ONLY the supplied '
        'candidates. You SELECT, GROUP and ORDER places chronologically for each day. '
        'You NEVER calculate clock times or durations — Dart does that deterministically.');
    buffer.writeln('');

    // ── CORE RULES ────────────────────────────────────────────────
    buffer.writeln('CORE RULES:');
    buffer.writeln('- Include every MUST-VISIT place exactly once across the trip.');
    buffer.writeln('- Use only the supplied place IDs. Never invent places or IDs.');
    buffer.writeln('- CRITICAL: Every place_id MUST appear AT MOST ONCE across the entire multi-day trip. NEVER repeat the same place_id on different days or within the same day.');
    if (request.totalDays >= 7) {
      buffer.writeln('- For trips of ${request.totalDays} days, prioritize distinct highlights every day, and ensure EVERY day receives 4-5 active stops. Never leave later days with few stops.');
    }
    buffer.writeln('- Return exactly ${request.totalDays} day(s) in the JSON array.');
    buffer.writeln('- dayIndex is 0-BASED: 0 is the first day, ${request.totalDays - 1} is the last day.');
    buffer.writeln('- Group geographically nearby places (same cluster) on the same day.');
    buffer.writeln('- Respect destination day allocation: ${_formatDaySplit(request)}.');
    buffer.writeln('');

    // ── DAILY THREE MEALS & STRUCTURE (CRITICAL & STRICTLY MANDATORY) ──
    buffer.writeln('DAILY THREE MEALS & STRUCTURE (CRITICAL & STRICTLY MANDATORY):');
    buffer.writeln('EVERY SINGLE DAY MUST INCLUDE THREE DISTINCT MEALS:');
    buffer.writeln('1. MORNING BREAKFAST & CAFE (09:00 - 10:00): Traditional breakfast spot, cafe, bakery, or local coffee kopitiam.');
    buffer.writeln('2. MORNING ATTRACTIONS (10:00 - 12:00): 1-2 famous tourist sights, heritage landmarks, or architectural icons.');
    buffer.writeln('3. MIDDAY LUNCH (12:00 - 13:30 - MANDATORY EVERY DAY): Authentic regional lunch dining restaurant or food street.');
    buffer.writeln('4. AFTERNOON SIGHTSEEING (13:30 - 17:30): 1-2 top museums, galleries, parks, or cultural spots (must conclude by 17:30!).');
    buffer.writeln('5. EVENING DINNER (18:00 - 20:00 - MANDATORY EVERY DAY): Savor a delicious evening dinner restaurant (different from lunch!).');
    buffer.writeln('6. OPTIONAL NIGHTLIFE (20:00 - 21:30): Rooftop cocktail bar or lively night market.');
    buffer.writeln('NEVER skip breakfast, never skip lunch, and never skip dinner on ANY day!');
    buffer.writeln('NEVER schedule daytime outdoor parks, nature reserves, or museums into the evening (18:00+). Evening is strictly reserved for Dinner and Nightlife.');
    buffer.writeln('');

    // ── GEOGRAPHIC EFFICIENCY & NO BACKTRACKING ─────────────────
    buffer.writeln('GEOGRAPHIC ROUTING & PROXIMITY (CRITICAL):');
    buffer.writeln('- MINIMIZE TRAVEL TIME: Follow a continuous, logical path through the city (A -> B -> C -> D).');
    buffer.writeln('- NEVER BACKTRACK: Avoid ping-ponging (e.g. going from Area A to far Area B and back to Area A) unless a specific venue only opens at that time!');
    buffer.writeln('- Cluster proximity: Each day should explore one cohesive neighborhood or adjacent zones.');
    buffer.writeln('');

    // ── CATEGORY BALANCE & SIGHTSEEING FOUNDATION ────────────────
    buffer.writeln('CATEGORY DIVERSITY & BALANCE RULES (MANDATORY):');
    buffer.writeln('- DIVERSIFY SIGHTSEEING: Mix iconic architecture, nature parks, history, and museums. Ensure places are popular tourist destinations or acclaimed hidden gems! NEVER schedule multiple mosques, temples, or churches on the same day (at most 1 religious site per day)!');
    buffer.writeln('- THREE MEALS RECOMMENDATIONS: Actively provide Breakfast/Cafe, Midday Lunch, and Evening Dinner options so traveler eats well every day!');
    buffer.writeln('- NIGHTLIFE TIMING: At most 1 nightlife stop per day, and it MUST ALWAYS be the VERY LAST stop in the evening (18:00+). NEVER in morning or early afternoon.');
    buffer.writeln('- TRAVEL INTELLIGENCE: Leverage your deep knowledge of Malaysia and local travel to provide a vivid "reason" for each day, highlighting signature local foods to try, cultural context, and optimal pacing.');
    buffer.writeln('');

    // ── TRAVEL STYLE PERSONALIZATION (STRICTLY ENFORCED) ────────
    buffer.writeln('TRAVEL STYLE PERSONALIZATION (MANDATORY ALIGNMENT):');
    buffer.writeln('- Travel Group Type: "${request.travelType ?? 'Solo'}"');
    final travelType = (request.travelType ?? 'Solo').toLowerCase();
    if (travelType.contains('family')) {
      buffer.writeln('  * [FAMILY STYLE]: Prioritize family-friendly, comfortable pacing. Favor interactive museums, theme parks, lush nature parks, safe walkable areas, and welcoming sit-down dining. Strictly avoid adult-only nightclubs.');
    } else if (travelType.contains('couple')) {
      buffer.writeln('  * [COUPLE STYLE]: Highlight romantic viewpoints, scenic waterfronts, cozy cafes, sunset photo spots, and ambient rooftop cocktail bars.');
    } else if (travelType.contains('friend') || travelType.contains('group')) {
      buffer.writeln('  * [FRIENDS STYLE]: Prioritize vibrant, high-energy spots, bustling night markets, fun group photo landmarks, and lively nightlife / social lounges.');
    } else {
      buffer.writeln('  * [SOLO STYLE]: Prioritize authentic cultural exploration, local street food trails, peaceful viewpoints, and walkable neighborhood immersion.');
    }

    buffer.writeln('- Exploration Window: "${request.exploration ?? 'Standard'}" (${_windowText(request.exploration)})');
    final exploration = (request.exploration ?? 'Standard').toLowerCase();
    if (exploration.contains('early')) {
      buffer.writeln('  * [EARLY BIRD]: Traveler wakes up early. Prioritize morning outdoor sights, sunrise spots, and traditional breakfast before noon.');
    } else if (exploration.contains('night')) {
      buffer.writeln('  * [NIGHT OWL]: Traveler starts later (11:00+). Emphasize afternoon cultural discoveries, evening markets, and vibrant nightlife past 19:00.');
    } else {
      buffer.writeln('  * [STANDARD TIME]: Balanced day starting at 09:00 through evening 21:00.');
    }

    buffer.writeln('- Travel Pace: "$pace"');
    if (pace == 'Slow') {
      buffer.writeln('  * [SLOW PACE]: 4 stops per day (Breakfast, Morning Sight, Lunch, Evening Dinner). Do not rush. Allow generous time for lingering at cafes, scenic gardens, and relaxed dining.');
    } else if (pace == 'Fast') {
      buffer.writeln('  * [FAST PACE]: 5-6 stops per day (Breakfast, 1-2 Morning Sights, Lunch, Afternoon Sight, Evening Dinner, optional Nightlife).');
    } else {
      buffer.writeln('  * [STANDARD PACE]: 5 stops per day (Breakfast, Morning Sight, Lunch, Afternoon Sight, Evening Dinner) with comfortable, balanced progression.');
    }

    buffer.writeln('- Transportation Mode: "${request.transportation}"');
    final trans = request.transportation.toLowerCase();
    if (trans.contains('walk')) {
      buffer.writeln('  * [WALKING]: Group stops in very tight, walkable geographical clusters to minimize foot fatigue.');
    } else if (trans.contains('transit') || trans.contains('bus') || trans.contains('train')) {
      buffer.writeln('  * [TRANSIT]: Schedule stops with direct, logical connectivity across the city.');
    } else {
      buffer.writeln('  * [DRIVING]: Flexible radius between distinct districts.');
    }

    buffer.writeln('- Selected Interests: ${request.interests.isEmpty ? 'General sightseeing' : request.interests.join(', ')}');
    buffer.writeln('  * [INTERESTS ALIGNMENT]: Heavily prioritize candidate places matching these user interests! Ensure the day\'s reason reflects these specific interests.');
    buffer.writeln('');

    // ── WEATHER FORECAST & ADAPTATION ────────────────────────────
    if (weatherForecast != null && weatherForecast.daily.isNotEmpty) {
      buffer.writeln('WEATHER FORECAST & METEOROLOGICAL ADAPTATION (CRITICAL):');
      for (int d = 0; d < request.totalDays; d++) {
        if (d < weatherForecast.daily.length) {
          final w = weatherForecast.daily[d];
          final cond = w.condition.toLowerCase();
          final isRainy = cond.contains('rain') ||
              cond.contains('storm') ||
              cond.contains('drizzle') ||
              cond.contains('thunder') ||
              cond.contains('shower');
          final tempText = '${w.minTemperature.round()}°C - ${w.maxTemperature.round()}°C';
          buffer.writeln(
            '- Day ${d + 1} (${w.date.year}-${w.date.month.toString().padLeft(2, '0')}-${w.date.day.toString().padLeft(2, '0')}): ${w.condition} ($tempText)',
          );
          if (isRainy) {
            buffer.writeln(
              '  * [RAINY DAY ADAPTATION]: Rainy forecast on Day ${d + 1}! Prioritize indoor cultural attractions, museums, galleries, covered markets, cafes, and shopping malls. Avoid steep open outdoor trails or unsheltered nature parks during peak rain.',
            );
          } else {
            buffer.writeln(
              '  * [FAIR WEATHER ADAPTATION]: Favorable weather on Day ${d + 1}! Prioritize scenic outdoor viewpoints, tea plantations, iconic architectural photo walks, and open heritage areas.',
            );
          }
        }
      }
      buffer.writeln('');
    } else if (request.startDate != null) {
      final daysUntilStart =
          request.startDate!.difference(DateTime.now()).inDays;
      if (daysUntilStart > 16) {
        buffer.writeln(
          'WEATHER CONTEXT: Trip starts in $daysUntilStart days (beyond the 16-day live meteorological window). Apply standard tropical climate planning: balanced indoor air-conditioned stops and shaded/sheltered afternoon options.',
        );
        buffer.writeln('');
      }
    }

    // ── DAILY STOP TARGET & EVEN DISTRIBUTION ─────────────────────
    buffer.writeln('DAILY DENSITY & DISTRIBUTION:');
    buffer.writeln('- TARGET: For "$pace" pace, place approximately **$targetStopsPerDay stops per day** (e.g. morning sight/breakfast, landmark, lunch, afternoon museum/culture, evening nightlife).');
    buffer.writeln('- EVEN DISTRIBUTION: Distribute stops evenly across ALL ${request.totalDays} day(s).');
    buffer.writeln('- NEVER leave any day empty or with only 1 stop.');
    buffer.writeln('');

    // ── WHAT NOT TO DO ───────────────────────────────────────────
    buffer.writeln('OUTPUT CONSTRAINTS:');
    buffer.writeln('- Do NOT calculate clock times or durations — Dart computes precise times and travel matrices.');
    buffer.writeln('- Return STRICT JSON ONLY matching the template below.');
    buffer.writeln('');

    // ── TRIP DETAILS ─────────────────────────────────────────────
    buffer.writeln('TRIP:');
    buffer.writeln('- destination: ${request.destinationNames.join(', ')}');
    buffer.writeln('- total_days: ${request.totalDays}');
    buffer.writeln('- day split: ${_formatDaySplit(request)}');
    buffer.writeln('- travel_type: ${request.travelType ?? 'Solo'}');
    buffer.writeln('- exploration: ${_windowText(request.exploration)}');
    buffer.writeln("- travel pace: $pace");
    buffer.writeln('- transportation: ${request.transportation}');
    buffer.writeln('- interests: '
        '${request.interests.isEmpty ? 'General sightseeing' : request.interests.join(', ')}');
    buffer.writeln('- must-visits: '
        '${mustVisitIds.isEmpty ? 'none' : mustVisitIds.join(', ')}');
    buffer.writeln('');

    // ── CANDIDATES ──────────────────────────────────────────────
    buffer.writeln('CANDIDATES (placeId | name | category | suggested_slot | clusterId):');
    for (final c in candidates) {
      final hint = _candidateTimeHint(c);
      buffer.writeln(
        '${c.placeId} | ${c.name} | ${c.category ?? 'attraction'} | $hint | c${c.clusterId}',
      );
    }
    buffer.writeln('');

    // ── CLUSTERS ─────────────────────────────────────────────────
    buffer.writeln('CLUSTERS (geographic groups):');
    for (final cluster in clusters) {
      buffer.writeln('- cluster ${cluster.dayIndex}');
    }
    buffer.writeln('');

    // ── OUTPUT TEMPLATE ─────────────────────────────────────────
    buffer.writeln('OUTPUT (STRICT JSON only):');
    buffer.writeln(_compactJsonTemplate());

    return buffer.toString();
  }

  String _candidateTimeHint(AiCandidateContext c) {
    final cat = (c.category ?? '').toLowerCase();
    if (cat.contains('night') || cat.contains('bar') || cat.contains('club')) {
      return 'Evening Nightlife / Rooftop Bar (18:00+)';
    }
    if (cat.contains('cafe') || cat.contains('bakery') || cat.contains('coffee')) {
      return 'Morning Breakfast / Coffee (09:00-10:30)';
    }
    if (cat.contains('food') || cat.contains('restaurant') || cat.contains('dining')) {
      return 'Midday Lunch (12:00-13:30)';
    }
    if (cat.contains('museum') || cat.contains('gallery') || cat.contains('aquarium')) {
      return 'Afternoon Culture / Indoor (14:00-17:00)';
    }
    if (cat.contains('shopping') || cat.contains('mall') || cat.contains('market')) {
      return 'Afternoon / Evening Shopping & Leisure';
    }
    return 'Morning / Afternoon Sightseeing Landmark';
  }

  String _compactJsonTemplate() {
    return '''
{
  "days": [
    {
      "dayIndex": 0,
      "placeIds": ["morning_place_id", "landmark_place_id", "lunch_place_id", "afternoon_place_id", "nightlife_place_id"],
      "reason": "Detailed narrative explaining morning highlights, signature lunch dishes, cultural significance, and evening vibe."
    }
  ]
}
''';
  }

  String _windowText(String? explorationTime) {
    final window = ItineraryConstants.explorationWindows[explorationTime] ??
        ItineraryConstants.explorationWindows['Standard']!;
    return '${window.startHour}:${window.startMinute.toString().padLeft(2, '0')} '
        '- ${window.endHour}:${window.endMinute.toString().padLeft(2, '0')}';
  }

  String _jsonTemplate() {
    return '''
{
  "days": [
    {
      "dayIndex": 0,
      "date": "2026-08-28",
      "schedule": [
        {
          "placeId": "ChIJ...",
          "stopOrder": 1,
          "startTime": "09:00",
          "endTime": "10:00",
          "visitDurationMinutes": 60,
          "travelFromPreviousMinutes": 0,
          "reason": "Start with a cultural highlight."
        },
        {
          "placeId": "ChIJ...",
          "stopOrder": 2,
          "stopOrder": 2,DISTRIBUTION
          "startTime": "10:10",
          "endTime": "11:10",
          "visitDurationMinutes": 60,
          "travelFromPreviousMinutes": 10,
          "reason": "Nearby museum."
        }
      ]
    }
  ]
}
''';
  }
}