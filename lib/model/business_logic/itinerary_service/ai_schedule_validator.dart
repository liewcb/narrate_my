// lib/model/business_logic/itinerary_service/ai_schedule_validator.dart
//
// Validates DeepSeek's AI schedule output BEFORE it is saved as the final
// itinerary. Validation is Flutter's responsibility — it is the hard
// constraint gate between DeepSeek and persistence.

import 'dart:convert';

import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../entities/openning_hours.dart';
import '../../entities/place.dart';

/// A single validation error, formatted for regeneration feedback.
class AiValidationIssue {
  final String type;
  final String message;
  final int? dayIndex;
  final String? placeId;

  const AiValidationIssue({
    required this.type,
    required this.message,
    this.dayIndex,
    this.placeId,
  });

  @override
  String toString() {
    final day = dayIndex != null ? 'Day ${dayIndex! + 1}: ' : '';
    final place = placeId != null ? '[$placeId] ' : '';
    return 'ERROR: $day$place$message';
  }
}

/// Result of AI schedule validation.
class AiValidationResult {
  final bool passed;
  final List<AiValidationIssue> issues;

  const AiValidationResult({required this.passed, required this.issues});

  /// A formatted block of errors used to build the regeneration prompt.
  String get feedbackText {
    if (issues.isEmpty) return '';
    return issues.map((i) => i.toString()).join('\n');
  }
}

/// Validates DeepSeek output against the full schedule contract.
class AiScheduleValidator {
  /// Validate the parsed AI schedule (list of days) against hard rules.
  ///
  /// [knownPlaceIds] is the full set of candidate placeIds (registry).
  /// [mustVisitIds] are verified must-visits that MUST appear exactly once.
  /// [destinationOrder] lists the destination names in travel order.
  /// [allocatedDaysPerDestination] maps destination name → allocated days.
  /// [placeIdToDestination] maps each candidate placeId to its destination
  /// name (used to verify per-day destination allocation).
  /// [routeMatrix] may carry `"A→B" → "N min"` when available.
  /// [placeLookup] maps placeId → full [Place] so the validator can perform
  /// deterministic opening-hours checks and produce place-named messages.
  /// [travelPace] drives the transition buffer used for day-capacity checks.
  AiValidationResult validate({
    required List<AIDaySchedule> days,
    required Set<String> knownPlaceIds,
    required List<String> mustVisitIds,
    required int totalDays,
    required String explorationTime,
    List<String>? destinationOrder,
    Map<String, int>? allocatedDaysPerDestination,
    Map<String, String>? placeIdToDestination,
    Map<String, String>? routeMatrix,
    Map<String, Place>? placeLookup,
    String travelPace = 'Standard',
  }) {
    final issues = <AiValidationIssue>[];

    // ── 1. Empty / structurally missing schedule ─────────────────
    if (days.isEmpty) {
      return const AiValidationResult(
        passed: false,
        issues: [
          AiValidationIssue(
            type: 'json_structure',
            message: 'AI returned no days.',
          ),
        ],
      );
    }

    // ── 2 + 16. Day index within trip duration & valid dates ─────
    final usedDayIndexes = <int>{};
    for (final day in days) {
      if (day.dayIndex < 0 || day.dayIndex >= totalDays) {
        issues.add(AiValidationIssue(
          type: 'day_index',
          message:
              'Day index ${day.dayIndex} is out of range (0–${totalDays - 1}).',
          dayIndex: day.dayIndex,
        ));
        continue;
      }
      usedDayIndexes.add(day.dayIndex);

      final parsedDate = DateTime.tryParse(day.date);
      if (parsedDate == null) {
        issues.add(AiValidationIssue(
          type: 'invalid_date',
          message: 'Invalid date "${day.date}".',
          dayIndex: day.dayIndex,
        ));
      }
    }

    // Every day index must be covered exactly once.
    for (int i = 0; i < totalDays; i++) {
      if (!usedDayIndexes.contains(i)) {
        issues.add(AiValidationIssue(
          type: 'day_index',
          message: 'Day $i is missing from the schedule.',
          dayIndex: i,
        ));
      }
    }

    final seenPlaceIds = <String>{};
    final seenMustVisitIds = <String>{};

    for (final day in days) {
      final dayStops = day.schedule;
      final dayDate = DateTime.tryParse(day.date);

      // Exploration window (computed once per day for all stops + capacity).
      final window = ItineraryConstants.explorationWindows[explorationTime] ??
          ItineraryConstants.explorationWindows['Standard']!;
      final windowStart = window.startHour * 60 + window.startMinute;
      final windowEnd = window.endHour * 60 + window.endMinute;

      // Day-level totals for the capacity check (Task 5 rule 24).
      var dayVisitTotal = 0;
      var dayTravelTotal = 0;

      // ── 17. Duplicate stop order ───────────────────────────────
      final orders = <int>{};
      for (final stop in dayStops) {
        if (!orders.add(stop.stopOrder)) {
          issues.add(AiValidationIssue(
            type: 'duplicate_stop_order',
            message: 'Duplicate stopOrder ${stop.stopOrder}.',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
        }
      }

      for (var i = 0; i < dayStops.length; i++) {
        final stop = dayStops[i];
        // ── 3. No invented places ────────────────────────────────
        if (!knownPlaceIds.contains(stop.placeId)) {
          issues.add(AiValidationIssue(
            type: 'unknown_place_id',
            message: 'AI returned unknown place_id "${stop.placeId}".',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
          continue;
        }

        // ── 4. No duplicate place IDs (GLOBAL across all days) ──
        if (!seenPlaceIds.add(stop.placeId)) {
          final name = placeLookup?[stop.placeId]?.placeName ?? '';
          final namePart = name.isNotEmpty ? ' ($name)' : '';
          issues.add(AiValidationIssue(
            type: 'duplicate_place',
            message: 'Place "${stop.placeId}"$namePart appears more than '
                'once in the generated itinerary.',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
        }

        if (mustVisitIds.contains(stop.placeId)) {
          seenMustVisitIds.add(stop.placeId);
        }

        // ── 9. start time < end time ─────────────────────────────
        final start = _parseHHmm(stop.startTime);
        final end = _parseHHmm(stop.endTime);
        if (start == null || end == null) {
          issues.add(AiValidationIssue(
            type: 'invalid_time',
            message:
                'Invalid time "start=${stop.startTime} end=${stop.endTime}".',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
          continue;
        }
        if (end <= start) {
          issues.add(AiValidationIssue(
            type: 'time_order',
            message: 'endTime ${stop.endTime} is not after startTime '
                '${stop.startTime}.',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
        }

        // ── 10. Duration is positive ─────────────────────────────
        if (stop.visitDurationMinutes <= 0) {
          issues.add(AiValidationIssue(
            type: 'duration',
            message: 'visitDurationMinutes ${stop.visitDurationMinutes} '
                'must be positive.',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
        }

        // ── 11. Fits exploration time ────────────────────────────
        if (start < windowStart || end > windowEnd) {
          issues.add(AiValidationIssue(
            type: 'window',
            message:
                'Stop ${stop.startTime}–${stop.endTime} is outside the '
                'exploration window '
                '(${_hhmm(windowStart)}–${_hhmm(windowEnd)}).',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
        }

        // ── 17. endTime == startTime + visitDuration ─────────────
        if (end - start != stop.visitDurationMinutes) {
          issues.add(AiValidationIssue(
            type: 'duration_mismatch',
            message: 'visitDurationMinutes ${stop.visitDurationMinutes} does '
                'not match scheduled span '
                '(${stop.startTime}–${stop.endTime}).',
            dayIndex: day.dayIndex,
            placeId: stop.placeId,
          ));
        }

        // ── 18/19. Travel time can fit between consecutive stops ─
        if (dayStops.indexOf(stop) > 0) {
          final prevStop = dayStops[dayStops.indexOf(stop) - 1];
          final prevEnd = _parseHHmm(prevStop.endTime);
          if (prevEnd != null && start < prevEnd + stop.travelFromPreviousMinutes) {
            issues.add(AiValidationIssue(
              type: 'travel_time',
              message: 'Stop ${stop.startTime} starts before the previous '
                  'stop ends plus ${stop.travelFromPreviousMinutes} min of '
                  'travel.',
              dayIndex: day.dayIndex,
              placeId: stop.placeId,
            ));
          }
        }

        // ── 21/22/23. Opening hours on the actual day ────────────
        final place = placeLookup?[stop.placeId];
        if (place != null && dayDate != null) {
          final hours = place.openingHours;
          if (hours != null && hours.periods.isNotEmpty) {
            final openingIssue = _validateOpeningHours(
              place: place,
              hours: hours,
              dayDate: dayDate,
              start: start,
              end: end,
            );
            if (openingIssue != null) {
              issues.add(AiValidationIssue(
                type: 'opening_hours',
                message: openingIssue,
                dayIndex: day.dayIndex,
                placeId: stop.placeId,
              ));
            }
          }
        }

        dayVisitTotal += stop.visitDurationMinutes;
        dayTravelTotal += stop.travelFromPreviousMinutes;
      }

      // ── 24. Day total duration exceeds available time ─────────
      if (dayStops.isNotEmpty) {
        final buffer = ItineraryConstants.bufferForPace(travelPace);
        final required =
            dayVisitTotal + dayTravelTotal + buffer * (dayStops.length - 1);
        if (required > window.totalMinutes) {
          final excess = required - window.totalMinutes;
          issues.add(AiValidationIssue(
            type: 'day_capacity',
            message: 'Day ${day.dayIndex + 1} total schedule ($required min) '
                'exceeds the exploration window '
                '(${window.totalMinutes} min) by $excess minutes.',
            dayIndex: day.dayIndex,
          ));
        }
      }
    }

    // ── 5 + 6. All verified must-visits included, exactly once ──
    for (final mustId in mustVisitIds) {
      if (mustId.isEmpty) continue;
      if (!seenMustVisitIds.contains(mustId)) {
        issues.add(AiValidationIssue(
          type: 'must_visit',
          message: 'Must-visit "$mustId" is missing from the itinerary.',
        ));
      }
    }

    // ── 8. Destination allocation respected ─────────────────────
    _validateDestinationAllocation(
      issues: issues,
      days: days,
      destinationOrder: destinationOrder,
      allocatedDaysPerDestination: allocatedDaysPerDestination,
      placeIdToDestination: placeIdToDestination,
    );

    // ── 13/14. Travel time / route jumps (when hard data exists) ─
    _validateRouteFeasibility(
      issues: issues,
      days: days,
      routeMatrix: routeMatrix,
      placeLookup: placeLookup,
    );

    return AiValidationResult(
      passed: issues.isEmpty,
      issues: issues,
    );
  }

  // ============================================================
  // Destination allocation check
  // ============================================================

  void _validateDestinationAllocation({
    required List<AiValidationIssue> issues,
    required List<AIDaySchedule> days,
    List<String>? destinationOrder,
    Map<String, int>? allocatedDaysPerDestination,
    Map<String, String>? placeIdToDestination,
  }) {
    if (destinationOrder == null || allocatedDaysPerDestination == null) return;
    if (destinationOrder.isEmpty || allocatedDaysPerDestination.isEmpty) return;

    // Build expected day → destination (sequential fill by travel order).
    final expectedDayDest = <int, String>{};
    var dayCounter = 0;
    for (final dest in destinationOrder) {
      final allocated = allocatedDaysPerDestination[dest] ?? 1;
      for (int d = 0; d < allocated; d++) {
        expectedDayDest[dayCounter++] = dest;
      }
    }

    for (final day in days) {
      final expected = expectedDayDest[day.dayIndex];
      if (expected == null) continue;

      // When the place→destination map is provided, every stop in a day
      // must belong to the destination allocated for that day. A mismatch
      // means the AI scheduled a candidate outside its destination's days.
      if (placeIdToDestination != null) {
        for (final stop in day.schedule) {
          final stopDest = placeIdToDestination[stop.placeId];
          if (stopDest == null) continue;
          if (stopDest != expected) {
            issues.add(AiValidationIssue(
              type: 'destination_allocation',
              message: 'Stop "${stop.placeId}" is in $stopDest but Day '
                  '${day.dayIndex + 1} is allocated to $expected.',
              dayIndex: day.dayIndex,
              placeId: stop.placeId,
            ));
          }
        }
      }
    }
  }

  // ============================================================
  // Route feasibility check (only when hard data exists)
  // ============================================================

  void _validateRouteFeasibility({
    required List<AiValidationIssue> issues,
    required List<AIDaySchedule> days,
    Map<String, String>? routeMatrix,
    Map<String, Place>? placeLookup,
  }) {
    if (routeMatrix == null || routeMatrix.isEmpty) return;
    final hardMax = ItineraryConstants.hardMaxTravelMinutes;

    for (final day in days) {
      final stops = day.schedule;
      for (int i = 1; i < stops.length; i++) {
        final from = stops[i - 1].placeId;
        final to = stops[i].placeId;
        final key = '$from→$to';
        final minutes = _parseMinutes(routeMatrix[key]);
        if (minutes == null) continue;
        if (minutes > hardMax) {
          final fromName = placeLookup?[from]?.placeName ?? from;
          final toName = placeLookup?[to]?.placeName ?? to;
          issues.add(AiValidationIssue(
            type: 'route_jump',
            message: 'Travel from $fromName to $toName requires $minutes '
                'minutes, exceeding the configured hard travel limit '
                '($hardMax minutes).',
            dayIndex: day.dayIndex,
            placeId: to,
          ));
        }
      }
    }
  }

  // ── Opening hours validation ──────────────────────────────────

  String? _validateOpeningHours({
    required Place place,
    required OpeningHours hours,
    required DateTime dayDate,
    required int start,
    required int end,
  }) {
    final weekday = dayDate.weekday % 7;
    final dayPeriods =
        hours.periods.where((p) => p.open.day == weekday).toList();

    if (dayPeriods.isEmpty) {
      return '${place.placeName} is closed on ${_weekdayName(dayDate.weekday)}.';
    }

    for (final period in dayPeriods) {
      final openMin = _hhmmToMinutes(period.open.time);
      var closeMin = _hhmmToMinutes(period.close.time);
      var s = start;
      var e = end;
      if (closeMin <= openMin) {
        closeMin += 1440;
        if (s < openMin) {
          s += 1440;
          e += 1440;
        }
      }
      if (s >= openMin && e <= closeMin) return null;
    }

    final first = dayPeriods.first;
    return '${place.placeName} is not open during the planned visit time. '
        'It is open from ${_hhmm(_hhmmToMinutes(first.open.time))} to '
        '${_hhmm(_hhmmToMinutes(first.close.time))} (scheduled: '
        '${_hhmm(start)}–${_hhmm(end)}).';
  }

  // ── Helpers ───────────────────────────────────────────────────

  int? _parseHHmm(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  int? _parseMinutes(String? value) {
    if (value == null) return null;
    final match = RegExp(r'\d+').firstMatch(value);
    return match != null ? int.tryParse(match.group(0)!) : null;
  }

  String _hhmm(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _hhmmToMinutes(String time) {
    final h = time.length >= 2 ? (int.tryParse(time.substring(0, 2)) ?? 0) : 0;
    final m =
        time.length >= 4 ? (int.tryParse(time.substring(2, 4)) ?? 0) : 0;
    return h * 60 + m;
  }

  String _weekdayName(int dartWeekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[dartWeekday - 1];
  }
}

/// Parses raw DeepSeek JSON into a list of [AIDaySchedule].
///
/// Throws a [FormatException] when the JSON is structurally invalid so the
/// pipeline can treat it as a regeneration trigger.
///
/// The model returns each day's stops in chronological array order; the
/// `stopOrder` field is assigned sequentially here (1, 2, 3, ...) so the
/// final ordering is deterministic and owned by Dart — an AI-supplied
/// `stopOrder` is never trusted.
List<AIDaySchedule> parseAiScheduleJson(String rawJson) {
  final data = jsonDecode(rawJson) as Map<String, dynamic>;
  final rawDays = data['days'];
  if (rawDays is! List) {
    throw const FormatException('AI output has no "days" array.');
  }

  final days = <AIDaySchedule>[];
  for (final rawDay in rawDays) {
    final map = rawDay as Map<String, dynamic>;
    final rawSchedule = map['schedule'];
    final schedule = <AIScheduleStop>[];
    var order = 1;
    if (rawSchedule is List) {
      for (final rawStop in rawSchedule) {
        final s = rawStop as Map<String, dynamic>;
        schedule.add(AIScheduleStop(
          stopOrder: order++,
          placeId: s['placeId'] as String? ?? '',
          startTime: s['startTime'] as String? ?? '',
          endTime: s['endTime'] as String? ?? '',
          visitDurationMinutes:
              (s['visitDurationMinutes'] as num?)?.toInt() ?? 0,
          travelFromPreviousMinutes:
              (s['travelFromPreviousMinutes'] as num?)?.toInt() ?? 0,
          scheduleReason: s['reason'] as String? ?? '',
        ));
      }
    }
    days.add(AIDaySchedule(
      dayIndex: (map['dayIndex'] as num?)?.toInt() ?? -1,
      date: map['date'] as String? ?? '',
      schedule: schedule,
    ));
  }
  return days;
}
