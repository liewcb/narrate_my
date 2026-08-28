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
    buffer.writeln('- destinations: ${request.destinations.join(', ')}');
    buffer.writeln('- allocated_days_per_destination: '
        '${_formatDaySplit(request)}');
    buffer.writeln('- travel_type: ${request.travelType ?? 'Solo'}');
    buffer.writeln('- interests: ${request.interests.isEmpty ? 'none' : request.interests.join(', ')}');
    buffer.writeln('- travel_pace: ${request.travelPace ?? 'Standard'}');
    buffer.writeln('- exploration_time: ${request.explorationTime ?? 'Standard'}');
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
