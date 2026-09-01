// lib/model/business_logic/itinerary_service/add_place_to_day_service.dart
//
// Deterministic Add Place validation for the ManageEditItineraryScreen.
// No AI involvement — all hard constraints are evaluated in Dart against the
// ACTUAL scheduled times of the existing stops in the selected day:
//   - place id validity
//   - duplicate check (same day + optional whole-itinerary)
//   - coordinate validity
//   - geographic reasonableness (detour)
//   - visit duration
//   - opening hours (by the actual itinerary date, full visit window)
//   - daily exploration window
//   - travel from the previous stop (actual routing)
//   - travel to the next stop (actual routing)
//   - insertion position selection (least-disruption)
//   - total day capacity
//   - transport mode awareness
//
// The existing itinerary is NEVER modified by validation. If validation
// fails, nothing is inserted.

import 'package:flutter/foundation.dart';

import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/google_maps_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/openning_hours.dart';
import '../../entities/place.dart';

/// A stop that already exists in the day, carrying its scheduled times so
/// insertion validation can be done against the ACTUAL itinerary schedule
/// (not a rebuilt approximation).
class AddPlaceExistingStop {
  final Place place;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;

  const AddPlaceExistingStop({
    required this.place,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
  });

  String get placeId => place.placeId;
  Coordinates get coordinates => place.coordinates;
  int get startMinutes => startTime.hour * 60 + startTime.minute;
  int get endMinutes => endTime.hour * 60 + endTime.minute;
}

/// Context for a single day where a place will be inserted.
class AddPlaceDayContext {
  final int dayNumber;
  final DateTime date;
  final List<AddPlaceExistingStop> existingStops;
  final Set<String> allDayPlaceIds;
  final ExplorationWindow window;
  final String transportMode;

  const AddPlaceDayContext({
    required this.dayNumber,
    required this.date,
    required this.existingStops,
    this.allDayPlaceIds = const {},
    required this.window,
    this.transportMode = 'walking',
  });
}

/// Structured result of validating a candidate place for insertion.
class AddPlaceValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? warningMessage;
  final int insertionIndex;
  final String? previousPlaceId;
  final String? nextPlaceId;
  final int travelFromPreviousMinutes;
  final int travelToNextMinutes;
  final int visitDurationMinutes;
  final String? scheduledStartTime;
  final String? scheduledEndTime;
  final bool openingHoursVerified;
  final bool fitsExplorationWindow;
  final bool geographicallyReasonable;
  final double? detourScore;
  final bool routingVerified;

  const AddPlaceValidationResult({
    required this.isValid,
    this.errorMessage,
    this.warningMessage,
    this.insertionIndex = 0,
    this.previousPlaceId,
    this.nextPlaceId,
    this.travelFromPreviousMinutes = 0,
    this.travelToNextMinutes = 0,
    this.visitDurationMinutes = 0,
    this.scheduledStartTime,
    this.scheduledEndTime,
    this.openingHoursVerified = false,
    this.fitsExplorationWindow = false,
    this.geographicallyReasonable = false,
    this.detourScore,
    this.routingVerified = false,
  });
}

/// Deterministic service for the "Add Place to Day" workflow.
///
/// Responsibilities:
///   - Search Google Places by free-text query.
///   - Validate a candidate against the specific day context using the
///     existing stops' ACTUAL scheduled times.
///   - Select the best (least-disruption) insertion position.
///   - Build a proposed schedule derived from actual itinerary data.
///   - NO AI involvement for hard constraints.
class AddPlaceToDayService {
  final GoogleMapsService _maps;

  AddPlaceToDayService({GoogleMapsService? mapsService})
      : _maps = mapsService ?? GoogleMapsService();

  // ─── Search ─────────────────────────────────────────────────

  /// Search Google Places by the user's free-text query.
  Future<List<Place>> searchPlaces(
    String query, {
    Coordinates? locationBias,
  }) async {
    if (query.trim().isEmpty) return [];
    return await _maps.searchTextPlaces(
      query: query.trim(),
      latitude: locationBias?.latitude,
      longitude: locationBias?.longitude,
    );
  }

  // ─── Validation ─────────────────────────────────────────────

  /// Validate a candidate against the specific day context and return the
  /// best (least-disruption) valid insertion position.
  ///
  /// [requestedStartTime] (HH:mm) is optional: when the UI already has a
  /// proposed start it is validated against the required travel; when absent
  /// the earliest feasible start is computed from the actual schedule.
  Future<AddPlaceValidationResult> evaluateInsertion({
    required AddPlaceDayContext context,
    required Place candidate,
    String? requestedStartTime,
  }) async {
    debugPrint('[ADD_PLACE]');
    debugPrint('Day: ${context.dayNumber}');
    debugPrint('Date: ${context.date.toIso8601String().split('T').first}');
    debugPrint('Place: ${candidate.placeName}');
    debugPrint('Place ID: ${candidate.placeId}');

    // ── CRITERION 1 — PLACE ID VALIDITY ─────────────────────────
    if (candidate.placeId.isEmpty) {
      return const AddPlaceValidationResult(
        isValid: false,
        errorMessage:
            'Unable to add this place because its location information is '
            'unavailable.',
      );
    }

    // ── CRITERION 3 — LOCATION VALIDITY ─────────────────────────
    if (!_hasValidCoordinates(candidate)) {
      return const AddPlaceValidationResult(
        isValid: false,
        errorMessage: 'The selected place does not have a valid location.',
      );
    }

    // ── CRITERION 2 — DUPLICATE PLACE ───────────────────────────
    for (final stop in context.existingStops) {
      if (stop.placeId == candidate.placeId) {
        return AddPlaceValidationResult(
          isValid: false,
          errorMessage:
              'This place is already included in Day ${context.dayNumber}.',
        );
      }
    }
    if (context.allDayPlaceIds.contains(candidate.placeId)) {
      return AddPlaceValidationResult(
        isValid: false,
        errorMessage:
            'This place is already included elsewhere in the itinerary.',
      );
    }

    // ── CRITERION 5 — VISIT DURATION ────────────────────────────
    final visitMinutes = candidate.visitDurationMinutes ??
        ItineraryConstants.defaultDurationMinutes;
    if (visitMinutes <= 0) {
      return const AddPlaceValidationResult(
        isValid: false,
        errorMessage:
            'Unable to add this place because the visit duration is invalid.',
      );
    }

    // ── CRITERION 6 — CLOSED ON THE SELECTED DAY (position-independent,
    //    highest-priority opening-hours failure) ────────────────
    final hours = candidate.placeRegularOpeningHours;
    if (hours != null &&
        hours.periods.isNotEmpty &&
        !hours.isOpenOnDay(context.date.weekday)) {
      return AddPlaceValidationResult(
        isValid: false,
        errorMessage: 'This place is closed on Day ${context.dayNumber}.',
      );
    }

    debugPrint('[ADD_PLACE VALIDATION]');
    debugPrint('Existing stops: ${context.existingStops.length}');
    debugPrint('Candidate insertion positions: '
        '${context.existingStops.length + 1}');

    // ── CRITERION 10 — EVALUATE EVERY INSERTION POSITION ────────
    final n = context.existingStops.length;
    AddPlaceValidationResult? bestResult;
    double bestDetour = double.infinity;
    final positionErrors = <String>[];

    for (int pos = 0; pos <= n; pos++) {
      final result = await _evaluatePosition(
        context: context,
        candidate: candidate,
        position: pos,
        visitMinutes: visitMinutes,
        requestedStartTime: requestedStartTime,
      );
      if (result.isValid) {
        final detour = result.detourScore ?? double.infinity;
        if (detour < bestDetour) {
          bestDetour = detour;
          bestResult = result;
        }
      } else if (result.errorMessage != null) {
        positionErrors.add(result.errorMessage!);
      }
    }

    if (bestResult != null) {
      debugPrint('[ADD_PLACE VALIDATION]');
      debugPrint('Result: VALID');
      debugPrint('Insertion index: ${bestResult.insertionIndex}');
      return bestResult;
    }

    // ── No valid position — return the most actionable reason ──
    final reason = _mostActionableFailure(
      context: context,
      positionErrors: positionErrors,
      visitMinutes: visitMinutes,
    );
    debugPrint('[ADD_PLACE VALIDATION]');
    debugPrint('Result: INVALID');
    debugPrint('Reason: $reason');
    return AddPlaceValidationResult(
      isValid: false,
      errorMessage: reason,
      visitDurationMinutes: visitMinutes,
    );
  }

  /// Evaluate a single insertion position against the ACTUAL schedule.
  Future<AddPlaceValidationResult> _evaluatePosition({
    required AddPlaceDayContext context,
    required Place candidate,
    required int position,
    required int visitMinutes,
    String? requestedStartTime,
  }) async {
    final existing = context.existingStops;
    final n = existing.length;

    final prev = position > 0 ? existing[position - 1] : null;
    final next = position < n ? existing[position] : null;

    final prevName = prev?.place.placeName ?? 'Start';
    final nextName = next?.place.placeName ?? 'End';
    debugPrint('[INSERTION CHECK]');
    debugPrint('Position: $position');
    debugPrint('Previous: $prevName');
    debugPrint('Next: $nextName');

    // ── CRITERION 8 + 9 — ACTUAL TRAVEL (never a fixed number) ──
    final int? travelFromPrev;
    if (prev != null) {
      travelFromPrev =
          await _getTravelMinutes(prev.coordinates, candidate.coordinates,
              context.transportMode);
      debugPrint('Travel previous → candidate: '
          '${travelFromPrev == null ? 'UNKNOWN' : '$travelFromPrev min'}');
    } else {
      travelFromPrev = 0;
      debugPrint('Travel previous → candidate: 0 min (first stop)');
    }

    final int? travelToNext;
    if (next != null) {
      travelToNext =
          await _getTravelMinutes(candidate.coordinates, next.coordinates,
              context.transportMode);
      debugPrint('Travel candidate → next: '
          '${travelToNext == null ? 'UNKNOWN' : '$travelToNext min'}');
    } else {
      travelToNext = 0;
      debugPrint('Travel candidate → next: 0 min (last stop)');
    }

    // ── CRITERION 14 — ROUTING FAILURE IS A CONTROLLED ERROR ───
    if (travelFromPrev == null || travelToNext == null) {
      return AddPlaceValidationResult(
        isValid: false,
        errorMessage:
            'Unable to verify travel time between these locations. '
            'Please try again.',
        insertionIndex: position,
        visitDurationMinutes: visitMinutes,
        routingVerified: false,
      );
    }

    debugPrint('Visit duration: $visitMinutes min');

    // ── Compute the proposed start / end from the real schedule ──
    final requestedStartMin = requestedStartTime != null
        ? _parseHHmm(requestedStartTime)
        : null;
    final int proposedStartMin;
    if (requestedStartMin != null) {
      proposedStartMin = requestedStartMin;
    } else if (prev != null) {
      proposedStartMin = prev.endMinutes + travelFromPrev;
    } else {
      proposedStartMin = context.window.startMinutes;
    }
    final proposedEndMin = proposedStartMin + visitMinutes;

    // ── CRITERION 6 — OPENING HOURS WINDOW (per-position, must be
    //    checked before travel/window per spec priority §5) ───────
    final hours = candidate.placeRegularOpeningHours;
    bool openingHoursVerified = false;
    if (hours != null && hours.periods.isNotEmpty) {
      final openingResult = _checkOpeningHours(
        place: candidate,
        hours: hours,
        dayDate: context.date,
        startMin: proposedStartMin,
        endMin: proposedEndMin,
        dayNumber: context.dayNumber,
      );
      if (!openingResult.isOpen) {
        return AddPlaceValidationResult(
          isValid: false,
          errorMessage: openingResult.message,
          insertionIndex: position,
          visitDurationMinutes: visitMinutes,
          travelFromPreviousMinutes: travelFromPrev,
          travelToNextMinutes: travelToNext,
        );
      }
      openingHoursVerified = true;
      debugPrint('[OPENING HOURS]');
      debugPrint('Day: ${openingResult.weekdayName}');
      debugPrint('Opening: ${openingResult.openingText}');
      debugPrint('Proposed: ${_minToHHmm(proposedStartMin)}–'
          '${_minToHHmm(proposedEndMin)}');
      debugPrint('Result: PASS');
    }

    // ── CRITERION 8 — TRAVEL FROM PREVIOUS STOP ─────────────────
    if (prev != null && proposedStartMin < prev.endMinutes + travelFromPrev) {
      final available = proposedStartMin - prev.endMinutes;
      return AddPlaceValidationResult(
        isValid: false,
        errorMessage: 'Not enough travel time from $prevName to '
            '${candidate.placeName}. Required: $travelFromPrev minutes, '
            'available: $available minutes.',
        insertionIndex: position,
        visitDurationMinutes: visitMinutes,
        travelFromPreviousMinutes: travelFromPrev,
        travelToNextMinutes: travelToNext,
      );
    }

    // ── CRITERION 7 — DAILY TIME WINDOW ─────────────────────────
    if (proposedStartMin < context.window.startMinutes ||
        proposedEndMin > context.window.endMinutes) {
      return AddPlaceValidationResult(
        isValid: false,
        errorMessage: 'There is not enough time remaining on Day '
            '${context.dayNumber} to visit this place.',
        insertionIndex: position,
        visitDurationMinutes: visitMinutes,
        travelFromPreviousMinutes: travelFromPrev,
        travelToNextMinutes: travelToNext,
      );
    }

    // ── CRITERION 9 — TRAVEL TO NEXT STOP (VERY IMPORTANT) ─────
    if (next != null &&
        proposedEndMin + travelToNext > next.startMinutes) {
      return AddPlaceValidationResult(
        isValid: false,
        errorMessage: 'Adding this place would make the next stop '
            'unreachable in time. Required travel time to $nextName: '
            '$travelToNext minutes.',
        insertionIndex: position,
        visitDurationMinutes: visitMinutes,
        travelFromPreviousMinutes: travelFromPrev,
        travelToNextMinutes: travelToNext,
      );
    }

    // ── CRITERION 12 — TOTAL DAY CAPACITY ───────────────────────
    final buffer = ItineraryConstants.bufferForPace('Standard');
    final totalVisit = existing.fold<int>(
            0, (sum, s) => sum + s.durationMinutes) +
        visitMinutes;
    var totalTravel = travelFromPrev + travelToNext;
    // Existing adjacent pairs (travel not persisted in Place) are estimated
    // with the pace buffer, consistent with the pipeline's day-capacity rule.
    if (existing.length > 1) {
      totalTravel += (existing.length - 1) * buffer;
    }
    final required = totalVisit + totalTravel + buffer * (existing.length);
    debugPrint('[DAY CAPACITY]');
    debugPrint('Available: ${context.window.totalMinutes} min');
    debugPrint('Required: $required min');
    if (required > context.window.totalMinutes) {
      debugPrint('Result: FAIL');
      return AddPlaceValidationResult(
        isValid: false,
        errorMessage: 'Day ${context.dayNumber} does not have enough '
            'available time for this place.',
        insertionIndex: position,
        visitDurationMinutes: visitMinutes,
        travelFromPreviousMinutes: travelFromPrev,
        travelToNextMinutes: travelToNext,
      );
    }
    debugPrint('Result: PASS');

    // ── CRITERION 13 + 4 — GEOGRAPHIC REASONABLENESS (warning) ─
    double detourScore = 0;
    bool geographicallyReasonable = true;
    if (prev != null && next != null) {
      final directKm = prev.coordinates.distanceTo(next.coordinates);
      final viaKm = prev.coordinates.distanceTo(candidate.coordinates) +
          candidate.coordinates.distanceTo(next.coordinates);
      detourScore = viaKm - directKm;
      if (detourScore > 10.0) {
        geographicallyReasonable = false;
      }
    } else if (prev != null) {
      detourScore = prev.coordinates.distanceTo(candidate.coordinates);
      if (detourScore > 20.0) geographicallyReasonable = false;
    } else if (next != null) {
      detourScore = candidate.coordinates.distanceTo(next.coordinates);
      if (detourScore > 20.0) geographicallyReasonable = false;
    }

    final result = AddPlaceValidationResult(
      isValid: true,
      insertionIndex: position,
      previousPlaceId: prev?.placeId,
      nextPlaceId: next?.placeId,
      travelFromPreviousMinutes: travelFromPrev,
      travelToNextMinutes: travelToNext,
      visitDurationMinutes: visitMinutes,
      scheduledStartTime: _minToHHmm(proposedStartMin),
      scheduledEndTime: _minToHHmm(proposedEndMin),
      openingHoursVerified: openingHoursVerified,
      fitsExplorationWindow: true,
      geographicallyReasonable: geographicallyReasonable,
      detourScore: detourScore,
      routingVerified: true,
    );
    if (!geographicallyReasonable) {
      return AddPlaceValidationResult(
        isValid: true,
        errorMessage: null,
        warningMessage:
            'This place is outside the usual route and will add travel time. '
            'It is still scheduled because it fits the available time.',
        insertionIndex: position,
        previousPlaceId: prev?.placeId,
        nextPlaceId: next?.placeId,
        travelFromPreviousMinutes: travelFromPrev,
        travelToNextMinutes: travelToNext,
        visitDurationMinutes: visitMinutes,
        scheduledStartTime: result.scheduledStartTime,
        scheduledEndTime: result.scheduledEndTime,
        openingHoursVerified: openingHoursVerified,
        fitsExplorationWindow: true,
        geographicallyReasonable: false,
        detourScore: detourScore,
        routingVerified: true,
      );
    }
    return result;
  }

  // ─── Failure reason selection ────────────────────────────────

  String _mostActionableFailure({
    required AddPlaceDayContext context,
    required List<String> positionErrors,
    required int visitMinutes,
  }) {
    if (positionErrors.isEmpty) {
      return 'Day ${context.dayNumber} does not have enough available time '
          'for this place.';
    }
    // Prefer the most specific / actionable message seen at any position.
    // Order follows the spec's error priority (§5): invalid place, duplicate,
    // invalid coords, closed on day, invalid opening hours, no valid
    // insertion position, insufficient travel, day time exceeded, then other.
    const priorities = [
      'This place is closed on Day',
      'closes before the proposed visit ends',
      'is not open during the planned visit',
      'Not enough travel time from',
      'Adding this place would make the next stop unreachable',
      'There is not enough time remaining on Day',
      'Day does not have enough available time',
      'Unable to verify travel time',
    ];
    for (final keyword in priorities) {
      for (final error in positionErrors) {
        if (error.contains(keyword)) return error;
      }
    }
    return positionErrors.first;
  }

  // ─── Opening hours helper ────────────────────────────────────

  _OpeningHoursResult _checkOpeningHours({
    required Place place,
    required OpeningHours hours,
    required DateTime dayDate,
    required int startMin,
    required int endMin,
    required int dayNumber,
  }) {
    final weekday = dayDate.weekday % 7;
    final dayPeriods =
        hours.periods.where((p) => p.open.day == weekday).toList();

    if (dayPeriods.isEmpty) {
      return _OpeningHoursResult(
        isOpen: false,
        message: 'This place is closed on Day $dayNumber.',
        weekdayName: _weekdayName(dayDate.weekday),
        openingText: 'Closed',
      );
    }

    for (final period in dayPeriods) {
      final openMin = _hhmmToMinutes(period.open.time);
      var closeMin = _hhmmToMinutes(period.close.time);
      var s = startMin;
      var e = endMin;
      if (closeMin <= openMin) {
        closeMin += 1440;
        if (s < openMin) {
          s += 1440;
          e += 1440;
        }
      }
      if (s >= openMin && e <= closeMin) {
        return _OpeningHoursResult(
          isOpen: true,
          message: null,
          weekdayName: _weekdayName(dayDate.weekday),
          openingText:
              '${_minToHHmm(openMin)}–${_minToHHmm(closeMin)}',
        );
      }
    }

    final first = dayPeriods.first;
    return _OpeningHoursResult(
      isOpen: false,
      message: 'This place closes before the proposed visit ends. '
          'Opening hours: ${_minToHHmm(_hhmmToMinutes(first.open.time))}–'
          '${_minToHHmm(_hhmmToMinutes(first.close.time))}; proposed: '
          '${_minToHHmm(startMin)}–${_minToHHmm(endMin)}.',
      weekdayName: _weekdayName(dayDate.weekday),
      openingText:
          '${_minToHHmm(_hhmmToMinutes(first.open.time))}–'
          '${_minToHHmm(_hhmmToMinutes(first.close.time))}',
    );
  }

  // ─── Travel helper ───────────────────────────────────────────

  /// Get actual travel time (minutes) between two coordinates.
  /// Returns `null` when the route cannot be obtained (NEVER assumed 0).
  Future<int?> _getTravelMinutes(
    Coordinates origin,
    Coordinates destination,
    String mode,
  ) async {
    try {
      final info = await _maps.getTravelTime(
        origin: origin,
        destination: destination,
        mode: mode,
      );
      return info.durationMinutes.ceil();
    } catch (e) {
      debugPrint('[ADD_PLACE] Routing failed: $e');
      return null;
    }
  }

  // ─── Coordinate helper ───────────────────────────────────────

  bool _hasValidCoordinates(Place place) {
    final latOk = place.placeLatitude >= -90 && place.placeLatitude <= 90;
    final lngOk = place.placeLongitude >= -180 && place.placeLongitude <= 180;
    return latOk &&
        lngOk &&
        !(place.placeLatitude == 0 && place.placeLongitude == 0);
  }

  // ─── Time helpers ────────────────────────────────────────────

  int? _parseHHmm(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  int _hhmmToMinutes(String time) {
    final h = time.length >= 2 ? (int.tryParse(time.substring(0, 2)) ?? 0) : 0;
    final m =
        time.length >= 4 ? (int.tryParse(time.substring(2, 4)) ?? 0) : 0;
    return h * 60 + m;
  }

  String _minToHHmm(int minutes) {
    final h = (minutes ~/ 60).clamp(0, 23);
    final m = (minutes % 60).clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
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

/// Result of the deterministic opening-hours check.
class _OpeningHoursResult {
  final bool isOpen;
  final String? message;
  final String weekdayName;
  final String openingText;

  const _OpeningHoursResult({
    required this.isOpen,
    required this.message,
    required this.weekdayName,
    required this.openingText,
  });
}
