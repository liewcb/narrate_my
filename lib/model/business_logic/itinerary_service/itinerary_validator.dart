// lib/model/business_logic/itinerary_service/itinerary_validator.dart
//
// Deterministic authority for "Manage Itinerary → Edit Stop" validation.
//
// The validator NEVER decides a result with AI. Every decision is derived
// from concrete inputs:
//   - actual coordinates
//   - actual Google routing travel times (reused from GoogleMapsService)
//   - place opening hours resolved against the real itinerary date
//   - visit durations
//   - the day exploration window (Relaxed / Standard / Intense)
//   - the resulting schedule (conflicts, chronological order)
//   - stop status (Completed stops are immutable)
//   - a stable placeId duplicate check
//   - optional base/hotel location travel (when the itinerary defines one)
//
// The same input always yields the same validation result.

import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/google_maps_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/itinerary_stop.dart';
import '../../entities/openning_hours.dart';
import '../../entities/place.dart';

/// Deterministic error codes produced by [ItineraryValidator].
abstract final class ItineraryValidationCodes {
  static const String invalidLocation = 'INVALID_LOCATION';
  static const String routeUnavailable = 'ROUTE_UNAVAILABLE';
  static const String travelTimeExceeded = 'TRAVEL_TIME_EXCEEDED';
  static const String visitDurationInvalid = 'VISIT_DURATION_INVALID';
  static const String dayWindowExceeded = 'DAY_WINDOW_EXCEEDED';
  static const String placeClosed = 'PLACE_CLOSED';
  static const String outsideOpeningHours = 'OUTSIDE_OPENING_HOURS';
  static const String scheduleConflict = 'SCHEDULE_CONFLICT';
  static const String completedStop = 'COMPLETED_STOP';
  static const String duplicatePlace = 'DUPLICATE_PLACE';
  static const String baseTravelInvalid = 'BASE_TRAVEL_INVALID';
}

/// A single deterministic validation issue for an itinerary edit.
class ItineraryValidationIssue {
  final String code;
  final String message;
  final String? stopId;
  final String? placeId;

  const ItineraryValidationIssue({
    required this.code,
    required this.message,
    this.stopId,
    this.placeId,
  });
}

/// Result of validating a resulting itinerary day.
class ItineraryValidationResult {
  final bool isValid;
  final List<ItineraryValidationIssue> issues;

  const ItineraryValidationResult({
    required this.isValid,
    required this.issues,
  });

  factory ItineraryValidationResult.valid() =>
      const ItineraryValidationResult(isValid: true, issues: []);

  factory ItineraryValidationResult.invalid(
    List<ItineraryValidationIssue> issues,
  ) =>
      ItineraryValidationResult(isValid: false, issues: issues);
}

/// Deterministic validator for the resulting itinerary after an Edit Stop
/// operation (location change, time change, or stop removal).
class ItineraryValidator {
  final GoogleMapsService _maps;

  ItineraryValidator({GoogleMapsService? mapsService})
      : _maps = mapsService ?? GoogleMapsService();

  static const String completedStatus = 'COMPLETED';

  /// Validates the complete resulting day after an edit.
  ///
  /// [dayStops] must be the day's stops AFTER the edit has been applied
  /// (candidate substituted / stop removed), in no particular order (they
  /// are sorted by [ItineraryStop.stopOrder] internally).
  ///
  /// [rerouteLegIndices] marks 1-based leg indices (the leg inbound to
  /// `dayStops[i]`, `i >= 1`) whose travel time must be freshly routed
  /// because an endpoint changed (location replacement / removal). Legs not
  /// marked reuse the persisted `travelFromPrevMinutes`.
  Future<ItineraryValidationResult> validateResultingDay({
    required List<ItineraryStop> dayStops,
    required DateTime dayDate,
    required ExplorationWindow window,
    required String transportMode,
    Set<int> rerouteLegIndices = const {},
    ItineraryStop? focusStop,
    Place? candidatePlace,
    Coordinates? baseLocation,
    String travelPace = 'Standard',
  }) async {
    final stops = List<ItineraryStop>.from(dayStops)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

    // An empty day (e.g. removing the last stop) is always feasible.
    if (stops.isEmpty) return ItineraryValidationResult.valid();

    final dayLabel = 'Day ${stops.first.dayIndex}';
    final issues = <ItineraryValidationIssue>[];

    // ── 1. Completed stops are historical and cannot be modified. ──────
    if (focusStop != null && focusStop.stopStatus == completedStatus) {
      return ItineraryValidationResult.invalid([
        const ItineraryValidationIssue(
          code: ItineraryValidationCodes.completedStop,
          message:
              'This stop has already been completed and cannot be modified.',
        ),
      ]);
    }

    // ── 2. Invalid coordinates + duplicate placeId (stable id). ────────
    for (final stop in stops) {
      final place = stop.place;
      if (place == null) continue;

      if (candidatePlace != null &&
          candidatePlace.placeId == place.placeId &&
          stop.stopId != focusStop?.stopId) {
        issues.add(ItineraryValidationIssue(
          code: ItineraryValidationCodes.duplicatePlace,
          message: '${place.placeName} is already included in $dayLabel.',
          stopId: stop.stopId.toString(),
          placeId: place.placeId,
        ));
      }

      if (_isInvalidCoordinates(place)) {
        issues.add(ItineraryValidationIssue(
          code: ItineraryValidationCodes.invalidLocation,
          message:
              '${place.placeName} has invalid coordinates and cannot be scheduled.',
          stopId: stop.stopId.toString(),
          placeId: place.placeId,
        ));
      }
    }
    if (issues.isNotEmpty) return ItineraryValidationResult.invalid(issues);

    // ── 3. Opening hours for the candidate on the actual itinerary date. ─
    if (candidatePlace != null) {
      final hours = candidatePlace.openingHours;
      if (hours != null && hours.periods.isNotEmpty) {
        final visit = _candidateVisitWindow(stops, focusStop);
        if (visit != null) {
          final openingIssue = _validateOpeningHours(
            place: candidatePlace,
            hours: hours,
            dayOfWeek: dayDate.weekday,
            visitStart: visit.$1,
            visitEnd: visit.$2,
            dayLabel: dayLabel,
          );
          if (openingIssue != null) issues.add(openingIssue);
        }
      }
    }
    if (issues.isNotEmpty) return ItineraryValidationResult.invalid(issues);

    // ── 4. Per-stop schedule / travel / window. ─────────────────────────
    final buffer = ItineraryConstants.bufferForPace(travelPace);
    var visitTotal = 0;
    var travelTotal = 0;
    var prevEndMin = window.startMinutes;

    for (var i = 0; i < stops.length; i++) {
      final stop = stops[i];
      final place = stop.place;
      final startMin = _toMinutes(stop.startTime);
      final endMin = _toMinutes(stop.endTime);
      final duration = stop.durationMinutes;

      if (endMin <= startMin || duration != endMin - startMin) {
        issues.add(ItineraryValidationIssue(
          code: ItineraryValidationCodes.visitDurationInvalid,
          message:
              '${place?.placeName ?? stop.placeId} has an invalid visit duration.',
          stopId: stop.stopId.toString(),
          placeId: stop.placeId,
        ));
        continue;
      }

      visitTotal += duration;

      if (startMin < window.startMinutes || endMin > window.endMinutes) {
        issues.add(ItineraryValidationIssue(
          code: ItineraryValidationCodes.dayWindowExceeded,
          message: 'This change makes $dayLabel exceed the available schedule. '
              'Please choose another location, change the time, or remove a stop.',
          stopId: stop.stopId.toString(),
          placeId: stop.placeId,
        ));
      }

      if (i > 0) {
        final travel = await _resolveTravel(
          stops: stops,
          leg: i,
          rerouteLegIndices: rerouteLegIndices,
          transportMode: transportMode,
        );

        if (travel == null) {
          issues.add(ItineraryValidationIssue(
            code: ItineraryValidationCodes.routeUnavailable,
            message: 'Unable to calculate a route between the selected '
                'locations. Please try another location.',
            stopId: stop.stopId.toString(),
            placeId: stop.placeId,
          ));
          continue;
        }

        travelTotal += travel;

        if (travel > ItineraryConstants.hardMaxTravelMinutes) {
          issues.add(ItineraryValidationIssue(
            code: ItineraryValidationCodes.travelTimeExceeded,
            message: '${place?.placeName ?? 'This location'} cannot fit after '
                '${stops[i - 1].place?.placeName ?? 'the previous stop'} '
                'because the travel time is too long.',
            stopId: stop.stopId.toString(),
            placeId: stop.placeId,
          ));
        }

        if (startMin < prevEndMin + travel) {
          issues.add(ItineraryValidationIssue(
            code: ItineraryValidationCodes.scheduleConflict,
            message: 'This change conflicts with the scheduled time of '
                '${place?.placeName ?? stop.placeId}.',
            stopId: stop.stopId.toString(),
            placeId: stop.placeId,
          ));
        }
      }

      prevEndMin = endMin;
    }

    // ── 5. Complete day duration vs. the exploration window. ────────────
    final requiredMinutes =
        visitTotal + travelTotal + buffer * (stops.length - 1);
    if (requiredMinutes > window.totalMinutes) {
      final excess = requiredMinutes - window.totalMinutes;
      issues.add(ItineraryValidationIssue(
        code: ItineraryValidationCodes.dayWindowExceeded,
        message: 'This change makes $dayLabel exceed the available schedule '
            'by $excess minutes. Please choose another location, change the '
            'time, or remove a stop.',
      ));
    }

    // ── 6. Base / hotel / start location travel (when defined). ─────────
    if (baseLocation != null) {
      issues.addAll(await _validateBaseTravel(
        stops: stops,
        baseLocation: baseLocation,
        window: window,
        transportMode: transportMode,
      ));
    }

    if (issues.isNotEmpty) return ItineraryValidationResult.invalid(issues);
    return ItineraryValidationResult.valid();
  }

  /// Actual routed travel minutes between two coordinates, or `null` when
  /// the route cannot be calculated. Reused by the ViewModel so the value
  /// persisted for the edited stop matches the validation routing.
  Future<int?> travelMinutesBetween(
    Coordinates origin,
    Coordinates destination,
    String transportMode,
  ) async {
    try {
      final info = await _maps.getTravelTime(
        origin: origin,
        destination: destination,
        mode: transportMode,
      );
      return info.durationMinutes.ceil();
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────── Internals ───────────────────────────────

  /// Travel time for the leg inbound to `stops[leg]`.
  ///
  /// Uses the persisted `travelFromPrevMinutes` when the leg was untouched
  /// by the edit and the value exists; otherwise routes freshly with the
  /// real Google Directions API.
  Future<int?> _resolveTravel({
    required List<ItineraryStop> stops,
    required int leg,
    required Set<int> rerouteLegIndices,
    required String transportMode,
  }) async {
    final to = stops[leg];
    final from = stops[leg - 1];

    if (!rerouteLegIndices.contains(leg) && to.travelFromPrevMinutes != null) {
      return to.travelFromPrevMinutes;
    }

    final fromPlace = from.place;
    final toPlace = to.place;
    if (fromPlace == null || toPlace == null) return null;
    if (_isInvalidCoordinates(fromPlace) || _isInvalidCoordinates(toPlace)) {
      return null;
    }

    return travelMinutesBetween(
      fromPlace.coordinates,
      toPlace.coordinates,
      transportMode,
    );
  }

  (int, int)? _candidateVisitWindow(
    List<ItineraryStop> stops,
    ItineraryStop? focusStop,
  ) {
    if (focusStop == null) return null;
    for (final stop in stops) {
      if (stop.stopId == focusStop.stopId) {
        return (_toMinutes(stop.startTime), _toMinutes(stop.endTime));
      }
    }
    return null;
  }

  ItineraryValidationIssue? _validateOpeningHours({
    required Place place,
    required OpeningHours hours,
    required int dayOfWeek,
    required int visitStart,
    required int visitEnd,
    required String dayLabel,
  }) {
    // OpeningHours.isOpenOnDay uses the same 1→1, 7→0 mapping.
    final weekday = dayOfWeek % 7;
    final dayPeriods =
        hours.periods.where((p) => p.open.day == weekday).toList();

    if (dayPeriods.isEmpty) {
      return ItineraryValidationIssue(
        code: ItineraryValidationCodes.placeClosed,
        message: '${place.placeName} is closed on ${_weekdayName(dayOfWeek)}.',
        placeId: place.placeId,
      );
    }

    for (final period in dayPeriods) {
      final openMin = _hhmmToMinutes(period.open.time);
      var closeMin = _hhmmToMinutes(period.close.time);
      var start = visitStart;
      var end = visitEnd;

      // Handle overnight periods (e.g. 22:00 → 02:00).
      if (closeMin <= openMin) {
        closeMin += 1440;
        if (start < openMin) {
          start += 1440;
          end += 1440;
        }
      }

      if (start >= openMin && end <= closeMin) return null;
    }

    final first = dayPeriods.first;
    return ItineraryValidationIssue(
      code: ItineraryValidationCodes.outsideOpeningHours,
      message: '${place.placeName} is not open during the planned visit time. '
          'It is open from ${_fmtMinutes(_hhmmToMinutes(first.open.time))} to '
          '${_fmtMinutes(_hhmmToMinutes(first.close.time))}.',
      placeId: place.placeId,
    );
  }

  Future<List<ItineraryValidationIssue>> _validateBaseTravel({
    required List<ItineraryStop> stops,
    required Coordinates baseLocation,
    required ExplorationWindow window,
    required String transportMode,
  }) async {
    final issues = <ItineraryValidationIssue>[];
    final first = stops.first;
    final last = stops.last;
    final firstPlace = first.place;
    final lastPlace = last.place;

    // Base → first stop.
    if (firstPlace != null && !_isInvalidCoordinates(firstPlace)) {
      final toFirst = await travelMinutesBetween(
        baseLocation,
        firstPlace.coordinates,
        transportMode,
      );
      if (toFirst == null) {
        issues.add(const ItineraryValidationIssue(
          code: ItineraryValidationCodes.routeUnavailable,
          message: 'Unable to calculate a route between the selected '
              'locations. Please try another location.',
        ));
      } else if (window.startMinutes + toFirst > _toMinutes(first.startTime)) {
        issues.add(ItineraryValidationIssue(
          code: ItineraryValidationCodes.baseTravelInvalid,
          message: "The first stop cannot be reached in time from the day's "
              'starting location.',
          stopId: first.stopId.toString(),
          placeId: first.placeId,
        ));
      }
    }

    // Last stop → base.
    if (lastPlace != null && !_isInvalidCoordinates(lastPlace)) {
      final toBase = await travelMinutesBetween(
        lastPlace.coordinates,
        baseLocation,
        transportMode,
      );
      if (toBase == null) {
        issues.add(const ItineraryValidationIssue(
          code: ItineraryValidationCodes.routeUnavailable,
          message: 'Unable to calculate a route between the selected '
              'locations. Please try another location.',
        ));
      } else if (_toMinutes(last.endTime) + toBase > window.endMinutes) {
        issues.add(ItineraryValidationIssue(
          code: ItineraryValidationCodes.baseTravelInvalid,
          message: 'The final stop cannot be completed with enough time to '
              "return to the day's starting location.",
          stopId: last.stopId.toString(),
          placeId: last.placeId,
        ));
      }
    }

    return issues;
  }

  bool _isInvalidCoordinates(Place place) =>
      place.placeLatitude == 0 && place.placeLongitude == 0;

  int _toMinutes(DateTime t) => t.hour * 60 + t.minute;

  int _hhmmToMinutes(String time) {
    final h = int.tryParse(time.substring(0, 2)) ?? 0;
    final m = time.length > 2 ? (int.tryParse(time.substring(2, 4)) ?? 0) : 0;
    return h * 60 + m;
  }

  String _fmtMinutes(int minutes) {
    final h = (minutes ~/ 60).clamp(0, 23).toString().padLeft(2, '0');
    final m = (minutes % 60).clamp(0, 59).toString().padLeft(2, '0');
    return '$h:$m';
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
