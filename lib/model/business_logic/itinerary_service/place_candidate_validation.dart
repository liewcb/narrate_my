// lib/model/business_logic/itinerary_service/place_candidate_validation.dart
//
// CENTRAL candidate validation for the preview Edit Itinerary flow.
//
// ONE pipeline shared by Change Place, Add Place, recommendations,
// manual search and bookmarks — never a weaker copy per feature:
//
//   IDENTITY → NAME → COORDINATES → DUPLICATE → DAY/RANGE → OPENING HOURS
//
// Opening hours are always evaluated against the ITINERARY day's date
// (dayDate), never the device's current date. Missing/empty opening
// data is NOT a rejection (existing project rule); a day that is known
// to be closed IS a rejection. Multiple periods per weekday are handled
// with "any single period fully contains the visit" (plus overnight
// periods), never requiring every period to contain the visit.
//
// Travel distance / travel time are NEVER part of this pipeline —
// they are informational only (see [EDIT_ROUTE_INFO] logging in the
// caller) and must not reject a traveler customization.

import 'package:flutter/foundation.dart';

import '../../entities/coordinates.dart';
import '../../entities/place.dart';

enum CandidateIssueCode {
  identity,
  name,
  coordinates,
  duplicate,
  outsideRange,
  openingHours,
}

class CandidateValidationResult {
  final bool isValid;
  final CandidateIssueCode? code;
  final String message;

  const CandidateValidationResult.valid()
      : isValid = true,
        code = null,
        message = '';

  const CandidateValidationResult.invalid(
      CandidateIssueCode this.code, String this.message)
      : isValid = false;

  bool get isInvalid => !isValid;
}

class PlaceCandidateValidation {
  PlaceCandidateValidation._();

  /// Runs the full candidate pipeline for [candidate].
  ///
  /// [stage] labels the logs (CHANGE_PLACE / ADD_PLACE / SEARCH /
  /// BOOKMARK / RECOMMEND). [usedPlaceIds] carries the STABLE database
  /// place_id of every already-scheduled place (whole itinerary).
  /// When [visitStartMinutes]/[visitEndMinutes] are given (minutes since
  /// midnight on [dayDate]) the ENTIRE visit must fit inside one of the
  /// weekday's opening periods; otherwise only "open on this day" is
  /// checked.
  static CandidateValidationResult validate(
    Place candidate, {
    required String stage,
    required DateTime dayDate,
    required Set<String> usedPlaceIds,
    Coordinates? dayCenter,
    double? maxRadiusKm,
    int? visitStartMinutes,
    int? visitEndMinutes,
  }) {
    final id = candidate.placeId.trim();
    final name = candidate.placeName.trim();
    final dayLabel = dayDate.toIso8601String().substring(0, 10);

    // 1. Stable identity (never the name).
    if (id.isEmpty) {
      return _reject(stage, '<unknown>', dayLabel,
          CandidateIssueCode.identity, 'This place does not have a valid '
              'ID and cannot be used.');
    }

    // 2. Name.
    if (name.isEmpty) {
      return _reject(stage, id, dayLabel, CandidateIssueCode.name,
          'This place has no name and cannot be used.');
    }

    // 3. Coordinates — BEFORE any routing/distance use.
    if (!hasValidCoordinates(candidate)) {
      return _reject(stage, id, dayLabel, CandidateIssueCode.coordinates,
          'This place cannot be selected because its location data is '
              'invalid.');
    }

    // 4. Duplicate — stable place_id against everything already scheduled.
    if (usedPlaceIds.contains(id)) {
      return _reject(stage, id, dayLabel, CandidateIssueCode.duplicate,
          'This place is already in your itinerary.');
    }

    // 5. Destination / day geographic compatibility (only when the
    //    caller has a center — never invented otherwise).
    if (dayCenter != null && maxRadiusKm != null && maxRadiusKm > 0) {
      final km = dayCenter.distanceTo(candidate.coordinates);
      if (km > maxRadiusKm) {
        return _reject(stage, id, dayLabel, CandidateIssueCode.outsideRange,
            'This place (${'${km.toStringAsFixed(1)}'} km) is outside the '
                'selected day\'s area.');
      }
    }

    // 6. Opening hours on the ITINERARY day's date.
    final hours = candidate.openingHours;
    if (hours != null && hours.periods.isNotEmpty) {
      final weekday = dayDate.weekday % 7; // OpeningHours: Sunday = 0
      if (!hours.isOpenOnDay(dayDate.weekday)) {
        return _reject(stage, id, dayLabel, CandidateIssueCode.openingHours,
            'This place is closed on $dayLabel.');
      }
      if (visitStartMinutes != null && visitEndMinutes != null) {
        if (!isOpenForVisit(candidate, dayDate, visitStartMinutes,
            visitEndMinutes)) {
          final periods = hours.periods
              .where((p) => p.open.day == weekday)
              .map((p) => '${p.open.time}–${p.close.time}')
              .join(', ');
          debugPrint('[EDIT_OPENING_HOURS] stage=$stage dayDate=$dayLabel '
              'place=$id($name) '
              'visit=${_fmtM(visitStartMinutes)}-${_fmtM(visitEndMinutes)} '
              'opening=[$periods] result=REJECT');
          return const CandidateValidationResult.invalid(
            CandidateIssueCode.openingHours,
            'This place is closed during the selected visit time.',
          );
        }
      }
    }

    debugPrint('[EDIT_CANDIDATE_VALIDATE] stage=$stage dayDate=$dayLabel '
        'place=$id($name) result=PASS');
    return const CandidateValidationResult.valid();
  }

  static CandidateValidationResult _reject(
    String stage,
    String id,
    String dayLabel,
    CandidateIssueCode code,
    String message,
  ) {
    debugPrint('[EDIT_CANDIDATE_VALIDATE] stage=$stage dayDate=$dayLabel '
        'place=$id result=REJECT reason=${code.name}: $message');
    return CandidateValidationResult.invalid(code, message);
  }

  /// NaN / Infinity / out-of-range / (0,0)-placeholder are all invalid.
  static bool hasValidCoordinates(Place place) {
    final lat = place.placeLatitude;
    final lng = place.placeLongitude;
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) {
      debugPrint('[EDIT_COORDINATE_VALIDATE] place=${place.placeId} '
          'result=REJECT reason=NaN_or_Infinite '
          'lat=$lat lng=$lng');
      return false;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      debugPrint('[EDIT_COORDINATE_VALIDATE] place=${place.placeId} '
          'result=REJECT reason=out_of_range lat=$lat lng=$lng');
      return false;
    }
    if (lat == 0 && lng == 0) {
      debugPrint('[EDIT_COORDINATE_VALIDATE] place=${place.placeId} '
          'result=REJECT reason=0_0_placeholder');
      return false;
    }
    return true;
  }

  /// True when AT LEAST ONE opening period of [place]'s weekday fully
  /// contains the visit (handles multiple periods and overnight spans).
  /// Unknown/missing hours data → treated as open (existing project rule).
  static bool isOpenForVisit(
    Place place,
    DateTime dayDate,
    int visitStartMinutes,
    int visitEndMinutes,
  ) {
    final hours = place.openingHours;
    if (hours == null || hours.periods.isEmpty) return true;

    final weekday = dayDate.weekday % 7; // Sunday = 0
    final periods =
        hours.periods.where((p) => p.open.day == weekday).toList();
    if (periods.isEmpty) return false; // known hours, closed this weekday

    for (final p in periods) {
      final openMin = _hhmmToMinutes(p.open.time);
      var closeMin = _hhmmToMinutes(p.close.time);
      var start = visitStartMinutes;
      var end = visitEndMinutes;
      if (closeMin <= openMin) {
        // Overnight period (e.g. 22:00 → 02:00).
        closeMin += 1440;
        if (start < openMin) {
          start += 1440;
          end += 1440;
        }
      }
      if (start >= openMin && end <= closeMin) return true;
    }
    return false;
  }

  static int _hhmmToMinutes(String time) {
    final h = int.tryParse(time.substring(0, 2)) ?? 0;
    final m =
        time.length > 2 ? (int.tryParse(time.substring(2, 4)) ?? 0) : 0;
    return h * 60 + m;
  }

  static String _fmtM(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
