// lib/bin/run_pipeline.dart
//
// Standalone driver for the new ItineraryGenerationPipeline.
// Run via: flutter test test/run_pipeline_test.dart
// (dart run does not resolve flutter packages.)

import 'package:flutter/foundation.dart';

import '../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../model/entities/coordinates.dart';
import '../model/entities/trip_draft.dart';

/// Static mock Google Place IDs for Melaka must-visit places.
class MockTestData {
  static const List<String> mustVisitIds = [
    'ChIJ308630g3zDER6r6vHh6v1AI', // Stadthuys
    'ChIJgU_8wEQ3zDERiJzE-zXwZ60', // Taming Sari Tower
    'ChIJwWvVl0M3zDERU-5eB0Y8c-8', // Baba Nyonya Heritage Museum
  ];
}

/// Run the complete new pipeline and print results.
Future<ItineraryResult> runItineraryPipeline() async {
  final tripRequest = TripDraft(
    destinations: ['Melaka'],
    destinationCoordinates: {
      'Melaka': const Coordinates(latitude: 2.1896, longitude: 102.2501),
    },
    title: 'Melaka Must Visit Test',
    startDate: DateTime(2026, 9, 1),
    endDate: DateTime(2026, 9, 2),
    explorationTime: 'Moderate',
    travelPace: 'Moderate',
    travelType: 'Solo',
    transportation: 'Driving',
    interests: [
      'Culture & History',
      'Shopping',
      'Food & Culinary',
    ],
    mustVisitPlaceIds: MockTestData.mustVisitIds,
    daySplit: {'Melaka': 2},
  );

  debugPrint('═══════════════════════════════════════════');
  debugPrint('🚀 NEW PIPELINE — Melaka Must-Visit Test');
  debugPrint('═══════════════════════════════════════════');

  final pipeline = ItineraryGenerationPipeline();

  final result = await pipeline.generate(
    request: tripRequest,
    onProgress: (stage) => debugPrint('[PROGRESS] $stage'),
  );

  debugPrint('═══════════════════════════════════════════');
  if (result.success) {
    debugPrint('✅ PIPELINE SUCCEEDED');
  } else {
    debugPrint('❌ PIPELINE FAILED: ${result.message}');
    for (final e in result.errors ?? []) {
      debugPrint('   ${e.type}: ${e.message}');
    }
  }
  debugPrint('═══════════════════════════════════════════');

  // ── Print final scheduled days ────────────────────────────────
  if (result.success && result.scheduledDays != null) {
    final days = result.scheduledDays!;
    debugPrint('🎯 SCHEDULE: ${days.length} day(s)');
    for (final day in days) {
      debugPrint('');
      debugPrint('── DAY ${day.dayIndex + 1} (${day.date.toIso8601String().split('T').first}) ──');
      debugPrint('   Duration: ${day.totalDuration}m | Travel: ${day.totalTravelTime}m');
      for (final stop in day.stops) {
        final p = stop.attraction.place;
        debugPrint(
          '   ${stop.startTime.hour.toString().padLeft(2, '0')}:'
          '${stop.startTime.minute.toString().padLeft(2, '0')} — '
          '${stop.endTime.hour.toString().padLeft(2, '0')}:'
          '${stop.endTime.minute.toString().padLeft(2, '0')}  '
          '${p.placeName} '
          '(${(stop.durationMinutes)}m, '
          'travel: ${stop.travelFromPreviousMinutes}m)',
        );
      }
    }
  }

  // ── Must-visit summary ─────────────────────────────────────────
  if (result.unretrievableMustVisits.isNotEmpty) {
    debugPrint('⚠️ UNRETRIEVABLE MUST-VISITS: ${result.unretrievableMustVisits}');
  }

  // ── Weather ────────────────────────────────────────────────────
  if (result.weather != null) {
    debugPrint('🌤️ WEATHER: ${result.weather!.daily.length} day(s) forecasted');
  }

  // ── Critic feedback ────────────────────────────────────────────
  if (result.criticFeedback != null) {
    final c = result.criticFeedback!;
    debugPrint('🧠 CRITIC: score=${c.score} suitable=${c.overallSuitable}');
    if (c.issues.isNotEmpty) {
      for (final issue in c.issues) {
        debugPrint('   ⚠️ $issue');
      }
    }
    if (c.recommendations.isNotEmpty) {
      for (final rec in c.recommendations) {
        debugPrint('   💡 $rec');
      }
    }
  }

  // ── Candidate pool summary ─────────────────────────────────────
  if (result.candidatePool != null) {
    final pool = result.candidatePool!;
    debugPrint('📦 POOL: ${pool.attractionCount} attractions, '
        '${pool.foodCount} food');
  }

  debugPrint('═══════════════════════════════════════════');
  debugPrint('🏁 DONE');
  debugPrint('═══════════════════════════════════════════');

  return result;
}

void main() async {
  debugPrint('Starting pipeline from main()...');
  final result = await runItineraryPipeline();
  debugPrint('Exit code: ${result.success ? 0 : 1}');
}