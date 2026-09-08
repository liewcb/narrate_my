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
      buffer.writeln(
          '- start_date: ${request.startDate!.toIso8601String().split('T').first}');
    }
    if (request.endDate != null) {
      buffer.writeln(
          '- end_date: ${request.endDate!.toIso8601String().split('T').first}');
    }
    buffer.writeln('- destinations: ${request.destinationNames.join(', ')}');
    buffer.writeln('- allocated_days_per_destination: '
        '${_formatDaySplit(request)}');
    buffer.writeln('- travel_type: ${request.travelType ?? 'Solo'}');
    buffer.writeln(
        '- interests: ${request.interests.isEmpty ? 'none' : request.interests.join(', ')}');
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

  /// Builds the compact DeepSeek planning prompt.
  ///
  /// [mustVisitIds] are the verified must-visit place IDs. [candidates] is the
  /// reduced (~10-14) high-quality pool and [clusters] the geographic groups -
  /// both already produced by the Dart scoring/clustering pipeline.
  ///
  /// Prompt length is optimized for the 1,050 token budget (GLM-5.3-Flash).
  String buildCompactPlanPrompt({
    required TripDraft request,
    required List<AiCandidateContext> candidates,
    required List<Cluster> clusters,
    required List<String> mustVisitIds,
  }) {
    final pace = request.pace ?? 'Standard';
    final totalDays = request.totalDays;
    final buffer = StringBuffer();

    // Target stops per day
    int targetStopsPerDay;
    switch (pace) {
      case 'Slow':
        targetStopsPerDay = 3;
        break;
      case 'Fast':
        targetStopsPerDay = 5;
        break;
      default:
        targetStopsPerDay = 4;
    }
    targetStopsPerDay = targetStopsPerDay.clamp(2, 5);

    final mustSet = mustVisitIds.toSet();
    final foodCount = candidates.where(_isFoodCandidate).length;
    final categories = candidates
        .map((c) => (c.category ?? 'attraction').trim())
        .where((c) => c.isNotEmpty)
        .toSet();

    // -- Compact instructions ------------------------------------
    buffer.writeln('Plan $totalDays-day itinerary from candidates. '
        '0-based dayIndex. Use only given placeIds. '
        'MUST places exactly once. Max 15 places total. '
        'Aim ~$targetStopsPerDay stops/day, mix categories, include food if available. '
        'Keep cluster places together. JSON output only.');

    // -- Trip info (short) ---------------------------------------
    buffer.writeln('Dests: ${request.destinationNames.join(",")}. '
        'Split: ${_formatDaySplit(request)}. '
        'Window: ${_windowText(request.exploration)}. '
        'Pace: $pace. Transport: ${request.transportation}. '
        'Interests: ${request.interests.isEmpty ? "none" : request.interests.join(",")}. '
        'Food count: $foodCount.');

    // -- Candidates as compact JSON array ------------------------
    buffer.writeln('CANDIDATES:');
    final candidatesJson = candidates.map((c) {
      final flags = <String>[];
      if (c.isMustVisit || mustSet.contains(c.placeId)) flags.add('M');
      if (_isFoodCandidate(c)) flags.add('F');
      return {
        'id': c.placeId,
        'n': c.name,
        'cat': c.category ?? 'attraction',
        'c': c.clusterId,
        'flags': flags.join(','),
      };
    }).toList();
    // Minify JSON to reduce chars
    buffer.writeln(jsonEncode(candidatesJson));

    // -- Output template (short) ---------------------------------
    buffer.writeln('OUTPUT: {"days":[{"dayIndex":0,"placeIds":["id1","id2"]}]}');

    return buffer.toString();
  }

  /// Whether a candidate reads as a food/dining place.
  ///
  /// Mirrors the category convention in `ScoringService._isFoodPlace` so the
  /// prompt's FOOD flag and the pipeline's food reservation agree on what
  /// counts as a meal stop.
  bool _isFoodCandidate(AiCandidateContext c) {
    final category = (c.category ?? '').toLowerCase();
    return category.contains('restaurant') ||
        category.contains('food') ||
        category.contains('cafe') ||
        category.contains('bakery') ||
        category.contains('dining');
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

  /// Fixed JSON schema representation for full schedule generation.
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