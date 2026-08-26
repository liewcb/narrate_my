// lib/model/business_logic/itinerary_service/schedule_repair_service.dart
import 'package:flutter/foundation.dart';

import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';

/// Validates and repairs AI-generated day schedules so they always fit
/// inside the configured exploration window.
///
/// The window is the "Relaxed / Standard / Intense" time budget set by the
/// traveler.  The AI often ignores this constraint; this service ensures
/// the schedule is clamped deterministically.
class ScheduleRepairService {
  ScheduleRepairService._();

  // ============================================================
  // VALIDATION
  // ============================================================

  /// Returns `true` when every stop in [stops] is inside [window], is
  /// chronological, and respects the travel buffer between consecutive
  /// stops.
  static bool isValid({
    required List<AIScheduleStop> stops,
    required ExplorationWindow window,
  }) {
    if (stops.isEmpty) return false;

    final winStart = window.startHour * 60 + window.startMinute;
    final winEnd = window.endHour * 60 + window.endMinute;

    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final startMin = _toMinutes(s.startTime);
      final endMin = _toMinutes(s.endTime);

      // Every stop must be entirely inside the window.
      if (startMin < winStart || endMin > winEnd) return false;
      if (endMin <= startMin) return false;

      if (i > 0) {
        final prev = stops[i - 1];
        final prevEnd = _toMinutes(prev.endTime);
        final travel = s.travelFromPreviousMinutes > 0
            ? s.travelFromPreviousMinutes
            : ItineraryConstants.bufferMinutes;
        // The next stop must start after the previous ends + travel.
        if (startMin < prevEnd + travel) return false;
      }
    }
    return true;
  }

  // ============================================================
  // REPAIR
  // ============================================================

  /// Build a schedule that is guaranteed to fit inside [window].
  ///
  /// When [stops] is non-empty it is used as the base (times are
  /// overwritten).  When [stops] is empty, the schedule is built entirely
  /// from the ground-truth [stopFacts] (deterministic path).
  ///
  /// Slack is redistributed evenly across stops so the repaired schedule
  /// ends at the exploration end instead of finishing early.
  static List<AIScheduleStop> repairSchedule({
    required List<AIScheduleStop> stops,
    required ExplorationWindow window,
    required List<Map<String, dynamic>> stopFacts,
  }) {
    final winStart = window.startHour * 60 + window.startMinute;
    final winEnd = window.endHour * 60 + window.endMinute;
    final span = winEnd - winStart;

    // Determine the ordered list of (placeId, baseVisit, travel).
    final entries = <({String placeId, int baseVisit, int travel})>[];
    final count = stops.isNotEmpty ? stops.length : stopFacts.length;
    for (var i = 0; i < count; i++) {
      final stop = stops.isNotEmpty ? stops[i] : null;
      final fact = i < stopFacts.length ? stopFacts[i] : null;
      final baseVisit = stop?.visitDurationMinutes ??
          (fact?['visitDurationMinutes'] as int?) ??
          ItineraryConstants.defaultDurationMinutes;
      final travel = i == 0
          ? 0
          : (stop?.travelFromPreviousMinutes ??
              ItineraryConstants.bufferMinutes);
      entries.add((
        placeId: stop?.placeId ?? (fact?['placeId'] as String? ?? ''),
        baseVisit: baseVisit,
        travel: travel,
      ));
    }

    if (entries.isEmpty) return [];

    // Forward pass with buffer (fixed per pace — default Standard 15).
    final buffer = ItineraryConstants.bufferForPace('Standard');
    final starts = <int>[];
    final ends = <int>[];
    var cursor = winStart;
    for (var i = 0; i < entries.length; i++) {
      final start = i == 0 ? winStart : cursor + entries[i].travel + buffer;
      final end = start + entries[i].baseVisit;
      starts.add(start);
      ends.add(end);
      cursor = end;
    }

    // Redistribute slack (only when positive; overflow handled by caller).
    final used = ends.last - winStart;
    final slack = span - used;
    final adjVisit = List<int>.from(entries.map((e) => e.baseVisit));
    if (slack > 0 && entries.isNotEmpty) {
      final perStop = slack ~/ entries.length;
      final remainder = slack - (perStop * entries.length);
      for (var i = 0; i < entries.length; i++) {
        adjVisit[i] += perStop;
      }
      adjVisit[entries.length - 1] += remainder;
    }

    // Rebuild times with adjusted visits.
    final repaired = <AIScheduleStop>[];
    cursor = winStart;
    for (var i = 0; i < entries.length; i++) {
      final start = i == 0 ? winStart : cursor + entries[i].travel + buffer;
      final end = start + adjVisit[i];
      repaired.add(AIScheduleStop(
        stopOrder: i + 1,
        placeId: entries[i].placeId,
        startTime: _formatTime(start),
        endTime: _formatTime(end),
        visitDurationMinutes: adjVisit[i],
        travelFromPreviousMinutes: i == 0 ? 0 : entries[i].travel,
        scheduleReason:
            stops.isNotEmpty && i < stops.length ? stops[i].scheduleReason : 'Repaired schedule',
        weatherNote: stops.isNotEmpty && i < stops.length ? stops[i].weatherNote : '',
      ));
      cursor = end;
    }

    return repaired;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static int _toMinutes(String time) {
    final parts = time.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return h * 60 + m;
  }

  static String _formatTime(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).clamp(0, 23).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).clamp(0, 59).toString().padLeft(2, '0');
    return '$h:$m';
  }
}