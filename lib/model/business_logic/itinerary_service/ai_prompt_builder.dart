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

  /// Dynamic visit-duration estimate from the DeepSeek candidate-evaluation
  /// stage. When present it REPLACES the static category-based duration for
  /// the planning pool; it is candidate metadata, NOT a final schedule value
  /// (the deterministic scheduler/validator remain authoritative).
  final int? estimatedVisitMinutes;

  /// AI relevance score (0..1) from the candidate-evaluation stage.
  final double? aiRelevanceScore;

  /// AI planning priority ('high' | 'medium' | 'low').
  final String? planningPriority;

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
    this.estimatedVisitMinutes,
    this.aiRelevanceScore,
    this.planningPriority,
  });

  /// The visit duration the planner should use: the AI estimate when the
  /// candidate-evaluation stage produced one, otherwise the static/known
  /// category-based duration.
  int? get effectiveVisitDurationMinutes =>
      estimatedVisitMinutes ?? visitDurationMinutes;

  AiCandidateContext copyWith({
    int? visitDurationMinutes,
    int? estimatedVisitMinutes,
    double? aiRelevanceScore,
    String? planningPriority,
  }) {
    return AiCandidateContext(
      placeId: placeId,
      name: name,
      destination: destination,
      clusterId: clusterId,
      category: category,
      rating: rating,
      finalScore: finalScore,
      isMustVisit: isMustVisit,
      visitDurationMinutes:
      visitDurationMinutes ?? effectiveVisitDurationMinutes,
      openingHours: openingHours,
      bestTimeSuggestion: bestTimeSuggestion,
      latitude: latitude,
      longitude: longitude,
      estimatedVisitMinutes: estimatedVisitMinutes ?? this.estimatedVisitMinutes,
      aiRelevanceScore: aiRelevanceScore ?? this.aiRelevanceScore,
      planningPriority: planningPriority ?? this.planningPriority,
    );
  }

  Map<String, dynamic> toJson() => {
    'place_id': placeId,
    'name': name,
    'destination': destination,
    'cluster_id': clusterId,
    'category': category,
    'rating': rating,
    'is_must_visit': isMustVisit,
    'visit_duration_minutes': effectiveVisitDurationMinutes,
    'estimated_visit_minutes': estimatedVisitMinutes,
    'ai_relevance_score': aiRelevanceScore,
    'planning_priority': planningPriority,
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
    /// Ordered placeIds per day produced by the planning phase, e.g.
    /// `{0: ["ChIJ...", "ChIJ..."], 1: ["ChIJ..."]}`. When provided the
    /// scheduling AI must use EXACTLY these places in this order.
    Map<int, List<String>>? plannedOrder,
    /// Reserve candidates not selected in the planning phase, available for
    /// replacement when the schedule would otherwise be infeasible.
    List<AiCandidateContext>? reserveCandidates,
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
    buffer.writeln('- destinations: ${request.destinations.join(', ')}');
    buffer.writeln('- allocated_days_per_destination: '
        '${_formatDaySplit(request)}');
    buffer.writeln('- travel_type: ${request.travelType ?? 'Solo'}');
    buffer.writeln('- interests: ${request.interests.isEmpty ? 'none' : request.interests.join(', ')}');
    buffer.writeln('- travel_pace: ${request.travelPace ?? 'Standard'}');
    buffer.writeln('- exploration_time: ${request.explorationTime ?? 'Standard'}');
    buffer.writeln('- transportation_mode: ${request.transportation}');
    buffer.writeln('');

    // ── PLANNED ORDER (when provided by the planning phase) ──────
    if (plannedOrder != null && plannedOrder.isNotEmpty) {
      buffer.writeln('PLANNED ORDER (initial place/day proposal)');
      for (var dayIdx = 0; dayIdx < (plannedOrder.keys.length); dayIdx++) {
        final ids = plannedOrder[dayIdx];
        if (ids == null || ids.isEmpty) continue;
        buffer.writeln('Day ${dayIdx + 1} places: ${ids.join(', ')}');
      }
      buffer.writeln('This is the INITIAL plan from the planning phase. '
          'Use it as your starting point. You MAY deviate from it when the '
          'schedule would otherwise violate a hard constraint: you are '
          'allowed to REORDER places, MOVE a place to another day, REMOVE a '
          'lower-priority place, or REPLACE a place with a suitable candidate '
          'from the CANDIDATES list below (the reserve pool). Prefer to keep '
          'the planned places; only deviate when necessary for feasibility.');
      buffer.writeln('');
    }

    // ── RESERVE CANDIDATES ───────────────────────────────────────
    if (reserveCandidates != null && reserveCandidates.isNotEmpty) {
      buffer.writeln('RESERVE CANDIDATES (replacement pool — not yet selected)');
      buffer.writeln('If a planned place makes a day infeasible, you may '
          'replace it with a suitable candidate below. Do NOT add reserve '
          'candidates unless needed to make the schedule feasible.');
      for (final c in reserveCandidates) {
        buffer.writeln(
          '- ${c.placeId} | ${c.name} | score=${c.finalScore.toStringAsFixed(2)} '
              '| cluster=${c.clusterId ?? '?'} | ${c.category ?? 'unknown'}',
        );
      }
      buffer.writeln('');
    }

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
    buffer.writeln('ROUTE INFORMATION (actual travel times — use these EXACT values)');
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
          '${_windowText(request.explorationTime)}.',
    );
    buffer.writeln('- Destination day allocation must be respected exactly.');
    buffer.writeln('- A verified must-visit must appear exactly once.');
    buffer.writeln(
      '- Never invent places, place IDs, coordinates, or restaurants.',
    );
    buffer.writeln(
      '- Every place in the schedule must come from the CANDIDATES above.',
    );
    buffer.writeln(
      '- Consider opening hours, visit duration, travel pace, '
          'transportation mode, weather and user interests.',
    );
    buffer.writeln('');

    buffer.writeln(
      '- Return each day\'s stops in the intended chronological sequence '
          '(stop 1 first, stop 2 second, ...). Do NOT emit a "stopOrder" field '
          '— the array ordering IS the stop order and will be assigned by the system.',
    );
    buffer.writeln('');

    // ── OUTPUT CONTRACT ──────────────────────────────────────────
    buffer.writeln(
      'Return STRICT JSON ONLY (no Markdown fences, no extra text):',
    );
    buffer.writeln(_jsonTemplate());

    return buffer.toString();
  }

  /// Build a PLANNING prompt that asks DeepSeek only for place selection
  /// and day allocation — no times, no durations, no scheduling. The
  /// output is a list of ordered placeIds per day.
  ///
  /// After this, the system computes ACTUAL routing travel times between
  /// consecutive stops, then passes those into [buildSchedulePrompt] so
  /// DeepSeek can schedule with real travel data.
  String buildPlanningPrompt({
    required TripDraft request,
    required List<AiCandidateContext> candidates,
    required List<Cluster> clusters,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('You are an expert travel itinerary PLANNER.');
    buffer.writeln('Your task is to SELECT which places to visit on which '
        'day and decide their ORDER. You do NOT schedule times, durations, '
        'or travel — you only produce a sequence of placeIds per day.');
    buffer.writeln('');

    // ── TRIP ─────────────────────────────────────────────────────
    buffer.writeln('TRIP');
    buffer.writeln('- total_days: ${request.totalDays}');
    if (request.startDate != null) {
      buffer.writeln('- start_date: ${request.startDate!.toIso8601String().split('T').first}');
    }
    if (request.endDate != null) {
      buffer.writeln('- end_date: ${request.endDate!.toIso8601String().split('T').first}');
    }
    buffer.writeln('- destinations: ${request.destinations.join(', ')}');
    buffer.writeln('- allocated_days_per_destination: '
        '${_formatDaySplit(request)}');
    buffer.writeln('- travel_pace: ${request.travelPace ?? 'Standard'}');
    buffer.writeln('- exploration_time: ${request.explorationTime ?? 'Standard'}');
    buffer.writeln('- transportation_mode: ${request.transportation}');
    buffer.writeln('- interests: ${request.interests.isEmpty ? 'none' : request.interests.join(', ')}');
    buffer.writeln('');

    // ── MUST-VISITS ──────────────────────────────────────────────
    buffer.writeln('MUST-VISITS (all mandatory — must appear EXACTLY once)');
    final mustVisits = candidates.where((c) => c.isMustVisit).toList();
    if (mustVisits.isEmpty) {
      buffer.writeln('- none');
    } else {
      for (final c in mustVisits) {
        buffer.writeln('- place_id: ${c.placeId} | name: ${c.name} | mandatory: true');
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

    // ── CONSTRAINTS ──────────────────────────────────────────────
    buffer.writeln('HARD CONSTRAINTS');
    buffer.writeln('- Every day must stay within the exploration window: '
        '${_windowText(request.explorationTime)}.');
    buffer.writeln('- Destination day allocation must be respected exactly.');
    buffer.writeln('- A verified must-visit must appear exactly once.');
    buffer.writeln('- Never invent places, place IDs, or coordinates.');
    buffer.writeln('- Every place must come from the CANDIDATES above.');
    buffer.writeln('- The number of stops per day is DYNAMIC — do not force '
        'a fixed count. Choose a reasonable number based on the day window, '
        'travel pace, and geographic proximity.');
    buffer.writeln('- Group places geographically so transitions are efficient.');
    buffer.writeln('- The array ordering of placeIds IS the stop order for that day.');
    buffer.writeln('- Do NOT include startTime, endTime, visitDurationMinutes, '
        'or travelFromPreviousMinutes — this is a PLANNING step only.');
    buffer.writeln('');

    // ── OUTPUT CONTRACT ──────────────────────────────────────────
    buffer.writeln('Return STRICT JSON ONLY (no Markdown fences, no extra text):');
    buffer.writeln(r'''
{
  "days": [
    {
      "dayIndex": 0,
      "date": "2026-08-28",
      "placeIds": ["ChIJ...", "ChIJ..."]
    }
  ]
}
''');

    return buffer.toString();
  }

  String _formatDaySplit(TripDraft request) {
    if (request.daySplit.isNotEmpty) {
      final parts = request.daySplit.entries
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      return '{ $parts }';
    }
    if (request.destinations.isEmpty || request.totalDays <= 0) {
      return 'not provided — split evenly across all destinations';
    }
    final base = request.totalDays ~/ request.destinations.length;
    final extra = request.totalDays % request.destinations.length;
    final parts = <String>[];
    for (int i = 0; i < request.destinations.length; i++) {
      final dest = request.destinations[i];
      parts.add('$dest=${base + (i < extra ? 1 : 0)}');
    }
    return '{ ${parts.join(', ')} }';
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
          "startTime": "09:00",
          "endTime": "10:00",
          "visitDurationMinutes": 60,
          "travelFromPreviousMinutes": 0,
          "reason": "Start with a cultural highlight."
        },
        {
          "placeId": "ChIJ...",
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
