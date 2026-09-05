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
import 'clustering_service.dart';

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
  }) {
    final pace = request.pace ?? 'Standard';
    final buffer = StringBuffer();

    // ── DETERMINE TARGET STOPS PER DAY ───────────────────────────
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
    // Cap at 5 to avoid overcrowding (absolute max)
    if (targetStopsPerDay > 5) targetStopsPerDay = 5;
    if (targetStopsPerDay < 2) targetStopsPerDay = 2;

    // ── PROMPT HEADER ────────────────────────────────────────────
    buffer.writeln('You are a travel itinerary planner.');
    buffer.writeln('Create a multi-day itinerary using ONLY the supplied '
        'candidates. You SELECT, GROUP and ORDER places. You NEVER calculate '
        'times, durations or travel minutes — Dart does that deterministically.');
    buffer.writeln('');

    // ── RULES ──────────────────────────────────────────────────────
    buffer.writeln('RULES:');
    buffer.writeln('- CRITICAL SPEED CONSTRAINT: Plan quickly and concisely. '
        'Do not over-analyze candidates in your reasoning. Output the JSON '
        'array immediately once you have selected the places.');
    buffer.writeln('- Include every MUST-VISIT place exactly once.');
    buffer.writeln('- Use only the supplied place IDs. Never invent places or IDs.');
    buffer.writeln('- A place may appear only once across the whole trip.');
    buffer.writeln('- Return exactly ${request.totalDays} day(s).');
    buffer.writeln('- dayIndex is 0-BASED: the first day is 0 and the last '
        'day is ${request.totalDays - 1}. Never use 1-based day numbers.');
    buffer.writeln('- Group geographically nearby places (same cluster) together.');
    buffer.writeln('- Match the traveler interests and travel pace.');
    buffer.writeln('- Respect the destination day allocation.');
    buffer.writeln('');

    // ── TARGET STOPS PER DAY (explicit) ──────────────────────────
    buffer.writeln('- TARGET: For a "$pace" pace, you should aim to place '
        'approximately **$targetStopsPerDay stops per day** (including meals). '
        'This is a target, not a hard limit – if you have fewer suitable '
        'candidates for a day, you may place fewer, but do NOT leave days '
        'very empty when candidates are available.');
    buffer.writeln('- DISTRIBUTION: Distribute places as evenly as possible '
        'across all days. Do NOT overload the first few days and leave the '
        'last days nearly empty. If a day has fewer than $targetStopsPerDay '
        'places and there are unused candidates from the same destination, '
        'add the highest-scored ones to fill it up.');
    buffer.writeln('- STRICT GLOBAL CAP: Do not generate more than 15 total '
        'places across the itinerary (this already accommodates all days).');
    buffer.writeln('');

    // ── WHAT NOT TO DO ───────────────────────────────────────────
    buffer.writeln('- Do NOT calculate startTime, endTime, visitMinutes, '
        'travel minutes, opening hours or distances — Dart computes all of '
        'those deterministically.');
    buffer.writeln('- Do NOT include reasons, explanations, comments or any '
        'text outside the JSON. Output ONLY the JSON shown in OUTPUT.');
    buffer.writeln('- Return ONLY valid JSON. No markdown, no extra text, '
        'no fields other than dayIndex and placeIds.');
    buffer.writeln('');

    // ── TRIP DETAILS ─────────────────────────────────────────────
    buffer.writeln('TRIP:');
    buffer.writeln('- destination: ${request.destinationNames.join(', ')}');
    buffer.writeln('- days: ${request.totalDays}');
    buffer.writeln('- day split: ${_formatDaySplit(request)}');
    buffer.writeln('- exploration: ${_windowText(request.exploration)}');
    buffer.writeln("- travel pace: $pace");
    buffer.writeln('- transportation: ${request.transportation}');
    buffer.writeln('- interests: '
        '${request.interests.isEmpty ? 'none' : request.interests.join(', ')}');
    buffer.writeln('- must-visits: '
        '${mustVisitIds.isEmpty ? 'none' : mustVisitIds.join(', ')}');
    buffer.writeln('');

    // ── CANDIDATES ──────────────────────────────────────────────
    // Minimal serialization: only the four fields the model needs for
    // selection/grouping/ordering. Coordinates, ratings and opening hours
    // are deterministic Dart concerns and are deliberately omitted.
    buffer.writeln('CANDIDATES (placeId | name | category | clusterId):');
    for (final c in candidates) {
      buffer.writeln(
        '${c.placeId} | ${c.name} | ${c.category ?? 'attraction'} | '
            'c${c.clusterId}',
      );
    }
    buffer.writeln('');

    // ── CLUSTERS ─────────────────────────────────────────────────
    buffer.writeln('CLUSTERS (geographic groups, NOT days):');
    for (final cluster in clusters) {
      buffer.writeln('- cluster ${cluster.dayIndex}');
    }
    buffer.writeln('');

    // ── OUTPUT TEMPLATE ─────────────────────────────────────────
    buffer.writeln('OUTPUT (JSON only):');
    buffer.writeln(_compactJsonTemplate());

    return buffer.toString();
  }

  String _compactJsonTemplate() {
    return '''
{
  "days": [
    {
      "dayIndex": 0,
      "placeIds": ["place_id_1", "place_id_2", "place_id_3"]
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