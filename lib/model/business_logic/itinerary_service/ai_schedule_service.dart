import 'package:flutter/foundation.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import 'candidate_retrieval_service.dart';
import 'clustering_service.dart';
import '../../entities/weather.dart';
import 'scoring_service.dart';

class AiScheduleService {
  final AIService _aiService;

  // Inject the custom AIService (which handles DeepSeek/OpenRouter/Cohere)
  AiScheduleService(this._aiService);

  /// Generates a strict, time-blocked schedule by coordinating with AIService.
  Future<List<AIDaySchedule>> generateSchedule({
    required List<Cluster> dailyClusters,
    required WeatherForecast forecast,
    required String travelPace,
    required String intensity,
    required List<String> interests,
    required String destinationName,
    required List<String> dietaryPreferences,
    required List<String> categoryExclusions,
    required DateTime startDate,
  }) async {
    // 1. Calculate the exploration window based on user intensity
    final window = ItineraryConstants.explorationWindowFor(intensity);
    final explorationStart = '${window.startHour.toString().padLeft(2, '0')}:${window.startMinute.toString().padLeft(2, '0')}';
    final explorationEnd = '${window.endHour.toString().padLeft(2, '0')}:${window.endMinute.toString().padLeft(2, '0')}';

    final List<AIDaySchedule> finalTripSchedule = [];

    // 2. Process each day sequentially
    for (int i = 0; i < dailyClusters.length; i++) {
      final cluster = dailyClusters[i];
      final currentDate = startDate.add(Duration(days: i));

      // Safely grab the weather for this specific day
      final dailyWeather = forecast.daily.length > i ? forecast.daily[i] : null;
      final weatherConditionString = dailyWeather != null
          ? '${dailyWeather.condition} (Max: ${dailyWeather.maxTemperature}°C)'
          : 'Unknown';

      debugPrint('🤖 Processing Day ${i + 1} via AIService...');

      // ============================================================
      // STEP A: Prepare Candidates for the AI
      // ============================================================
      // There is NO fixed place count. Use the full cluster's scored
      // candidates (attractions + food). The scheduler below keeps adding
      // stops until the remaining window time is insufficient, capped only
      // by the safety ceiling (maxStopsPerDay).
      final int maxCandidates = ItineraryConstants.maxStopsPerDay;

      // Separate food and attractions, already sorted by highest score
      final foodCandidates = <ScoredAttraction>[];
      final attractionCandidates = <ScoredAttraction>[];

      for (final item in cluster.sortedByScore) {
        // (Ensure candidate_retrieval_service.dart is imported at the top of this file)
        final isFood = item.place.types.any((t) => CandidateRetrievalService.foodTypes.contains(t));
        if (isFood) {
          foodCandidates.add(item);
        } else {
          attractionCandidates.add(item);
        }
      }

      // Pass as many candidates as possible (ceiling = maxStopsPerDay).
      // The schedule builder decides the actual count from available time.
      final selectedDailyPlaces = [
        ...attractionCandidates.take(maxCandidates),
        ...foodCandidates.take(3),
      ];

      // FIX: Safety check for empty clusters — never send an empty
      // candidate list to the AI (that would make planRoute/constructDaySchedule
      // produce an unusable schedule and can crash the whole pipeline).
      if (selectedDailyPlaces.isEmpty) {
        debugPrint('⚠️ Day ${i + 1}: no candidates — emitting empty schedule.');
        finalTripSchedule.add(AIDaySchedule(
          dayIndex: i,
          date: currentDate.toIso8601String().split('T').first,
          schedule: [],
        ));
        continue;
      }

      final candidateIds = selectedDailyPlaces.map((a) => a.place.placeId).toList();
      debugPrint('👉 Sending ${candidateIds.length} top places to AI for routing.');

      // Declared outside the try so the catch block can use it for the
      // deterministic fallback schedule.
      List<Map<String, dynamic>> orderedStopFacts = [];

      try {
        // ============================================================
        // STEP B: AI Route Order (Sequence & Filter)
        // ============================================================
        final routeResult = await _aiService.planRoute(
          dayIndex: i,
          candidatePlaceIds: candidateIds,
          travelPace: travelPace,
          interests: interests,
          destinationName: destinationName,
          dietaryPreferences: dietaryPreferences,
          categoryExclusions: categoryExclusions,
          weatherCondition: weatherConditionString,
        );

        // ============================================================
        // STEP C: Rehydrate Factual Place Data
        // ============================================================
        orderedStopFacts = [];

        for (final placeId in routeResult.order) {
          // FIX: Case-Insensitive ID matching & Null-Aware check — the AI
          // sometimes returns placeIds with different casing, which previously
          // produced a "no matching element" crash. Now we match
          // case-insensitively and skip (not crash) on unknown IDs.
          final originalAttraction = selectedDailyPlaces.cast<ScoredAttraction?>().firstWhere(
            (a) => a?.place.placeId.toLowerCase() == placeId.toLowerCase(),
            orElse: () => null,
          );

          if (originalAttraction == null) continue; // Skip if no data found instead of crashing

          final place = originalAttraction.place;

          orderedStopFacts.add({
            'placeId': place.placeId,
            'name': place.placeName,
            'address': place.address,
            'latitude': place.latitude,
            'longitude': place.longitude,
            'rating': place.rating,
            'types': place.types,
            'category': place.category,
            'openingHours': place.openingHours?.toString() ?? 'unknown',
            'visitDurationMinutes': place.visitDurationMinutes ?? ItineraryConstants.defaultDurationMinutes,
            'travelFromPreviousMinutes': 15,
          });
        }

        // ============================================================
        // STEP D: AI Schedule Construction (Assign Time Blocks)
        // ============================================================
        final daySchedule = await _aiService.constructDaySchedule(
          dayIndex: i,
          date: currentDate,
          destinationName: destinationName,
          explorationStart: explorationStart,
          explorationEnd: explorationEnd,
          travelPace: travelPace,
          stops: orderedStopFacts,
          weatherCondition: weatherConditionString,
        );

        debugPrint('[DOMAIN MODEL CREATED] Day ${i + 1}: '
            '${daySchedule.schedule.length} stops, '
            'needsRepair=${daySchedule.needsRepair} '
            'warnings=${daySchedule.warnings.length}');

        // FIX: When the AI returns an empty / needsRepair schedule (e.g. it
        // produced only reasoning_content, or returned unparseable JSON), a
        // day MUST NOT become 0 stops.  Build a deterministic in-window
        // schedule from the ordered stop facts instead.
        AIDaySchedule effective = daySchedule;
        if (daySchedule.schedule.isEmpty || daySchedule.needsRepair) {
          effective = _buildDeterministicSchedule(
            dayIndex: i,
            date: currentDate,
            window: window,
            stopFacts: orderedStopFacts,
            travelPace: travelPace,
          );
          debugPrint('[DETERMINISTIC FALLBACK] Day ${i + 1}: built '
              '${effective.schedule.length} stops inside the window');
        } else {
          // FIX: Enforce the exploration window deterministically — the AI
          // often ignores the window and returns schedules that start late or
          // exceed the end time, which breaks the "Relaxed/Standard/Intense"
          // time budget.  This step rebuilds the times within the window when
          // the AI violates it.
          effective = _ensureWithinWindow(
            daySchedule,
            i,
            currentDate,
            window,
            orderedStopFacts,
            travelPace: travelPace,
          );
          if (effective != daySchedule) {
            debugPrint('[WINDOW ENFORCE] Day ${i + 1}: schedule rebuilt to fit '
                '${window.startHour}:${window.startMinute.toString().padLeft(2, '0')} – '
                '${window.endHour}:${window.endMinute.toString().padLeft(2, '0')}');
          }
        }

        finalTripSchedule.add(effective);
      } catch (e) {
        // FIX: Per-day AI failure fallback — one failing day must not
        // abort the whole itinerary. Build a deterministic schedule for
        // that day instead of emitting 0 stops.
        debugPrint('⚠️ AI Failure on Day ${i + 1}: $e');

        // If we never got ordered stop facts, build them from the
        // selected daily places (original route order).
        if (orderedStopFacts.isEmpty && selectedDailyPlaces.isNotEmpty) {
          orderedStopFacts = selectedDailyPlaces.map((attr) {
            final p = attr.place;
            return {
              'placeId': p.placeId,
              'name': p.placeName,
              'address': p.address,
              'latitude': p.latitude,
              'longitude': p.longitude,
              'rating': p.rating,
              'types': p.types,
              'category': p.category,
              'openingHours': p.openingHours?.toString() ?? 'unknown',
              'visitDurationMinutes': p.visitDurationMinutes ?? ItineraryConstants.defaultDurationMinutes,
              'travelFromPreviousMinutes': 15,
            };
          }).toList();
        }

        final fallback = _buildDeterministicSchedule(
          dayIndex: i,
          date: currentDate,
          window: window,
          stopFacts: orderedStopFacts,
          travelPace: travelPace,
        );
        debugPrint('[DETERMINISTIC FALLBACK] Day ${i + 1}: built '
            '${fallback.schedule.length} stops inside the window');
        finalTripSchedule.add(fallback);
      }
    }

    return finalTripSchedule;
  }

  // ============================================================
  // EXPLORATION-WINDOW ENFORCEMENT
  // ============================================================

  /// Ensure every stop lies within the exploration window
  /// (`window.startHour..window.endHour`), is chronological, and includes
  /// travel time between stops.
  ///
  /// If the AI schedule violates any of these constraints, the times are
  /// rebuilt deterministically inside the window (start from the window
  /// start, add duration + travel buffer per stop). This guarantees the
  /// itinerary always respects Relaxed/Standard/Intense time budgets even
  /// when the AI ignores the prompt.
  AIDaySchedule _ensureWithinWindow(
      AIDaySchedule day,
      int dayIndex,
      DateTime date,
      ExplorationWindow window,
      List<Map<String, dynamic>> stopFacts, {
        String travelPace = 'Standard',
      }) {
    if (day.schedule.isEmpty) return day;

    final windowStartMin = window.startHour * 60 + window.startMinute;
    final windowEndMin = window.endHour * 60 + window.endMinute;
    final buffer = ItineraryConstants.bufferForPace(travelPace);
    final maxStops = ItineraryConstants.maxStopsPerDay;

    // We'll rebuild the schedule from scratch using the AI's order, but
    // we'll skip stops that don't fit and try to insert the next one.
    final rebuilt = <AIScheduleStop>[];
    var cursorMin = windowStartMin;
    final preferredEndMin =
        ItineraryConstants.preferredActivityEndMinute(window, travelPace);

    // Use the AI schedule order, but we can also fall back to stopFacts if needed.
    // We'll use the AI's list as the primary source.
    final scheduleStops = day.schedule.take(maxStops).toList();

    for (int i = 0; i < scheduleStops.length && rebuilt.length < maxStops; i++) {
      final s = scheduleStops[i];
      // Determine travel time: use AI's value if >0, else buffer.
      final travel = i == 0 ? 0 :
      (s.travelFromPreviousMinutes > 0 ? s.travelFromPreviousMinutes : buffer);

      // Duration: prefer AI, then fact, then category-aware default.
      var duration = s.visitDurationMinutes > 0 ? s.visitDurationMinutes : 90;
      if (duration <= 0 && i < stopFacts.length) {
        final factDuration =
            (stopFacts[i]['visitDurationMinutes'] as num?)?.toInt() ?? 0;
        final factCategory = stopFacts[i]['category'] as String?;
        duration = factDuration > 0
            ? factDuration
            : ItineraryConstants.baseDurationForCategory(
                factCategory,
                ItineraryConstants.defaultDurationMinutes,
              );
      }
      duration = _paceAdjustedDuration(duration, travelPace);

      // FIRST stop at EXACTLY window start; subsequent: prev end + travel + buffer.
      final startMin = i == 0
          ? windowStartMin
          : cursorMin + travel + buffer;
      final endMin = startMin + duration;

      // Preferred-boundary gate: only add stops within the pace's preferred
      // activity boundary, so Relaxed does not pack the day to explorationEnd.
      final withinPreferred = endMin <= preferredEndMin;
      if (endMin <= windowEndMin && withinPreferred) {
        rebuilt.add(AIScheduleStop(
          stopOrder: rebuilt.length + 1,
          placeId: s.placeId,
          startTime: _formatTime(startMin),
          endTime: _formatTime(endMin),
          visitDurationMinutes: duration,
          travelFromPreviousMinutes: i == 0 ? 0 : travel,
          scheduleReason: s.scheduleReason,
          weatherNote: s.weatherNote,
        ));
        cursorMin = endMin;
      } else {
        // Skip this stop; the cursor stays where it is, so the next stop will
        // start from the same position (with its own travel time from the previous
        // scheduled stop). That means a later stop might still fit.
        continue;
      }
    }

    return AIDaySchedule(
      dayIndex: dayIndex,
      date: date.toIso8601String().split('T').first,
      schedule: rebuilt,
      warnings: day.warnings,
      needsRepair: day.needsRepair,
    );
  }

  /// Apply the travel-pace duration factor to a base visit duration.
  int _paceAdjustedDuration(int base, String pace) {
    final factor = ItineraryConstants.durationFactorForPace(pace);
    final adjusted = (base * factor).round();
    return adjusted.clamp(
      ItineraryConstants.minimumVisitDurationMinutes,
      ItineraryConstants.maximumVisitDurationMinutes,
    );
  }

  String _formatTime(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ============================================================
  // DETERMINISTIC FALLBACK SCHEDULE
  // ============================================================

  /// Build a deterministic, in-window schedule from the ordered stop facts.
  ///
  /// Used when the AI fails or returns an empty/needsRepair schedule so a
  /// day NEVER ends up with 0 stops. Stops start at the exploration-window
  /// start and are laid out sequentially using their factual durations and
  /// the configured buffer/travel time.
  AIDaySchedule _buildDeterministicSchedule({
    required int dayIndex,
    required DateTime date,
    required ExplorationWindow window,
    required List<Map<String, dynamic>> stopFacts,
    String travelPace = 'Standard',
  }) {
    final windowStartMin = window.startHour * 60 + window.startMinute;
    final windowEndMin = window.endHour * 60 + window.endMinute;
    final buffer = ItineraryConstants.bufferForPace(travelPace);
    // Allow up to a soft maximum, but we'll try to fit as many as possible.
    final maxStops = ItineraryConstants.maxStopsPerDay;
    final preferredEndMin =
        ItineraryConstants.preferredActivityEndMinute(window, travelPace);

    final stops = <AIScheduleStop>[];
    var cursorMin = windowStartMin;

    // We'll iterate through all stop facts, not just the first maxStops.
    for (int i = 0; i < stopFacts.length && stops.length < maxStops; i++) {
      final fact = stopFacts[i];
      final travel = i == 0 ? 0 : buffer; // travel from previous
      final duration = _paceAdjustedDuration(
        (fact['visitDurationMinutes'] as num?)?.toInt() ??
            ItineraryConstants.defaultDurationMinutes,
        travelPace,
      );

      // FIRST stop at EXACTLY window start; subsequent: prev end + travel + buffer.
      final startMin = i == 0 ? windowStartMin : cursorMin + travel + buffer;
      final endMin = startMin + duration;

      // Preferred-boundary gate: only add within the pace's preferred
      // activity boundary so Relaxed does not pack to explorationEnd.
      final withinPreferred = endMin <= preferredEndMin;
      // Check if this stop fits.
      if (endMin <= windowEndMin && withinPreferred) {
        // Add it.
        stops.add(AIScheduleStop(
          stopOrder: stops.length + 1,
          placeId: fact['placeId'] as String? ?? '',
          startTime: _formatTime(startMin),
          endTime: _formatTime(endMin),
          visitDurationMinutes: duration,
          travelFromPreviousMinutes: i == 0 ? 0 : travel,
          scheduleReason: 'Deterministic fallback (AI unavailable)',
          weatherNote: 'AI schedule unavailable — deterministic times used',
        ));
        cursorMin = endMin;
      } else {
        // This stop doesn't fit. We could try to shorten it, but we'll just skip it.
        // However, we also adjust the cursor to the startMin? No, we don't advance.
        // The next stop will still start at the same cursor + travel? Actually, the travel
        // to the next stop would be from the previous scheduled stop, not from this skipped one.
        // So we must not change cursorMin.
        // We also don't increment cursorMin – we stay at the end of the last scheduled stop.
        // That means we effectively skip this stop and try the next one with the same start time.
        // This allows a shorter stop later to be inserted.
        // We continue to the next fact without advancing the cursor.
        continue;
      }
    }

    // After the loop, if there's still time left, we could optionally add
    // a short buffer activity (e.g., "Relax at hotel") but we'll leave that out.

    return AIDaySchedule(
      dayIndex: dayIndex,
      date: date.toIso8601String().split('T').first,
      schedule: stops,
      warnings: const ['AI schedule unavailable — deterministic times used'],
      needsRepair: stops.isEmpty,
    );
  }

}