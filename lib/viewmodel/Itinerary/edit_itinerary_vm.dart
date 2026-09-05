// lib/viewmodel/ItineraryModel/edit_itinerary_vm.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import '../../core/config/itinerary_constants.dart';
import '../../core/services/ai_service.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/business_logic/itinerary_service/scoring_service.dart';
import '../../model/entities/place.dart';
import '../../model/entities/weather.dart';
import '../../view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';

/// A single stop in the editable itinerary, derived from [ScheduledStop].
class EditableStop {
  final String placeId;
  final String name;
  final String address;
  final bool isMustVisit;
  final Place place;
  DateTime startTime;
  DateTime endTime;
  int travelFromPrevMinutes;

  /// Visit duration in minutes. Mutable so [setDuration] can adjust it;
  /// [endTime] is always re-derived as `startTime + durationMinutes`.
  int durationMinutes;

  EditableStop({
    required this.placeId,
    required this.name,
    required this.address,
    required this.durationMinutes,
    required this.isMustVisit,
    required this.place,
    required this.startTime,
    required this.endTime,
    this.travelFromPrevMinutes = 0,
  });

  /// Deep copy so snapshots taken before a mutation are not affected by the
  /// mutation (EditableStop's time fields are mutable).
  EditableStop copy() => EditableStop(
        placeId: placeId,
        name: name,
        address: address,
        durationMinutes: durationMinutes,
        isMustVisit: isMustVisit,
        place: place,
        startTime: startTime,
        endTime: endTime,
        travelFromPrevMinutes: travelFromPrevMinutes,
      );
}

/// ViewModel for [EditItineraryScreen].
///
/// Holds temporary editable state for a single day. Changes are validated
/// and returned as an updated [ItineraryResult] only when [applyChanges]
/// is called; the original result is never mutated in place.
class EditItineraryViewModel extends ChangeNotifier {
  final ItineraryResult _originalResult;
  final int _dayIndex;
  final DateTime _tripStartDate;
  final String _explorationTime;
  final List<String> _mustVisitPlaceIds;
  final String _title;

  List<EditableStop> _stops = [];
  String? _error;

  EditItineraryViewModel({
    required ItineraryResult result,
    required int dayIndex,
    required DateTime tripStartDate,
    required String explorationTime,
    required List<String> mustVisitPlaceIds,
    required String title,
  })  : _originalResult = result,
        _dayIndex = dayIndex,
        _tripStartDate = tripStartDate,
        _explorationTime = explorationTime,
        _mustVisitPlaceIds = mustVisitPlaceIds,
        _title = title {
    _stops = _buildStops();
  }

  // ─── Getters ────────────────────────────────────────────────

  List<EditableStop> get stops => List.unmodifiable(_stops);
  int get dayNumber => _dayIndex + 1;
  String get title => _title;
  String? get error => _error;
  bool get hasChanges => _hasChanges();

  /// The exploration window for the current travel pace.
  ExplorationWindow get window =>
      ItineraryConstants.explorationWindowFor(_explorationTime);

  /// The date of this day.
  DateTime get dayDate =>
      _tripStartDate.add(Duration(days: _dayIndex));

  /// Candidates from the original pool that are not currently used.
  List<Place> get availableCandidates {
    final pool = _originalResult.candidatePool;
    if (pool == null) return [];
    final usedIds = _stops.map((s) => s.placeId).toSet();
    return pool.all.where((p) => !usedIds.contains(p.placeId)).toList();
  }

  // ─── Editability (date AND time aware) ──────────────────────

  static const int maxDurationMinutes = 120; // hard 2-hour visit cap

  /// The temporal status of this day portion: past / ongoing / upcoming.
  ItineraryTemporalStatus get dayStatus {
    final now = DateTime.now();
    final dayStart = DateTime(dayDate.year, dayDate.month, dayDate.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    if (now.isBefore(dayStart)) return ItineraryTemporalStatus.upcoming;
    if (now.isAfter(dayEnd)) return ItineraryTemporalStatus.past;
    return ItineraryTemporalStatus.ongoing;
  }

  bool get isDayEditable => dayStatus != ItineraryTemporalStatus.past;

  /// A stop is editable when its day is not over and its scheduled time has
  /// NOT completely elapsed. Ongoing: the remaining portion stays editable.
  /// Upcoming: everything editable. Past: nothing editable.
  bool isStopEditable(int index) {
    if (!isDayEditable) return false;
    final now = DateTime.now();
    final stop = _stops[index];
    final scheduledEnd = DateTime(
      dayDate.year, dayDate.month, dayDate.day,
      stop.endTime.hour, stop.endTime.minute,
    );
    return now.isBefore(scheduledEnd);
  }

  /// Traveler-facing reason a stop is locked, or null when editable.
  String? stopLockedReason(int index) {
    if (isStopEditable(index)) return null;
    return dayStatus == ItineraryTemporalStatus.past
        ? 'This itinerary has ended and can no longer be modified.'
        : 'This stop can no longer be changed. Its scheduled time has '
            'already passed.';
  }

  // ─── Calculated edit options ────────────────────────────────

  /// Valid start-time options (30-minute slots) for [index], calculated by
  /// Dart from: previous stop end + travel, exploration window, next stop,
  /// remaining exploration time and opening hours. The traveler picks from
  /// these only — no arbitrary time entry.
  List<TimeOfDay> availableStartTimes(int index) {
    if (index < 0 || index >= _stops.length) return const [];
    final stop = _stops[index];
    final win = window;
    final winEnd = win.endMinutes;

    // Lower bound: previous stop end + travel to this stop.
    var lower = win.startMinutes;
    if (index > 0) {
      final prev = _stops[index - 1];
      final prevEnd = prev.endTime.hour * 60 + prev.endTime.minute;
      lower = prevEnd + stop.travelFromPrevMinutes;
    }

    // Opening hours (if known) further bound the start.
    final oh = stop.place.openingHours;
    if (oh != null && oh.periods.isNotEmpty) {
      final weekday = dayDate.weekday % 7;
      final dayOpens = oh.periods
          .where((p) => p.open.day == weekday)
          .map((p) => _hhmmToMinutes(p.open.time))
          .toList();
      if (dayOpens.isNotEmpty) {
        final earliestOpen = dayOpens.reduce((a, b) => a < b ? a : b);
        if (earliestOpen > lower) lower = earliestOpen;
      }
    }

    // Round up to the next 30-minute slot after [lower].
    var slot = (lower / 30).ceil() * 30;
    final options = <TimeOfDay>[];
    while (slot + stop.durationMinutes <= winEnd) {
      options.add(TimeOfDay(hour: slot ~/ 60, minute: slot % 60));
      slot += 30;
    }

    // Always include the current start so the current choice is visible.
    final current = TimeOfDay(
        hour: stop.startTime.hour, minute: stop.startTime.minute);
    if (!options.contains(current)) {
      options.add(current);
      options.sort((a, b) =>
          (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    }
    return options;
  }

  /// Feasible visit-duration options (natural travel-app choices, hard 2-hour
  /// maximum). Each option must keep the stop inside the exploration window
  /// and respect the place's closing time when hours are known.
  List<int> availableDurations(int index) {
    if (index < 0 || index >= _stops.length) return const [];
    final stop = _stops[index];
    const choices = [20, 30, 45, 60, 75, 90, 105, 120];
    final winEnd = window.endMinutes;
    final startMin = stop.startTime.hour * 60 + stop.startTime.minute;

    // Closing bound from opening hours (if known).
    var closeLimit = winEnd;
    final oh = stop.place.openingHours;
    if (oh != null && oh.periods.isNotEmpty) {
      final weekday = dayDate.weekday % 7;
      final dayCloses = oh.periods
          .where((p) => p.open.day == weekday)
          .map((p) => _hhmmToMinutes(p.close.time))
          .toList();
      if (dayCloses.isNotEmpty) {
        final latestClose = dayCloses.reduce((a, b) => a > b ? a : b);
        if (latestClose < closeLimit) closeLimit = latestClose;
      }
    }

    return choices
        .where((d) => d <= maxDurationMinutes)
        .where((d) => startMin + d <= closeLimit)
        .toList();
  }

  /// Sets a new visit duration and rechains the rest of the day. Returns
  /// `true` only when the new duration keeps the day valid; otherwise the
  /// change is reverted and [_error] carries a user-friendly reason.
  bool setDuration(int index, int minutes) {
    if (index < 0 || index >= _stops.length) return false;
    if (minutes <= 0) {
      _error = 'The selected duration is invalid.';
      notifyListeners();
      return false;
    }
    if (minutes > maxDurationMinutes) {
      _error = 'Visits are limited to 2 hours.';
      notifyListeners();
      return false;
    }

    final snapshot = _snapshotStops();
    final stop = _stops[index];
    stop.durationMinutes = minutes;
    stop.endTime = stop.startTime.add(Duration(minutes: minutes));
    _rechainSchedule();

    final errors = validate();
    if (errors.isNotEmpty) {
      _restoreStops(snapshot);
      _error = errors.first;
      notifyListeners();
      return false;
    }
    _error = null;
    notifyListeners();
    return true;
  }

  int _hhmmToMinutes(String time) {
    final h = int.tryParse(time.substring(0, 2)) ?? 0;
    final m = time.length > 2 ? (int.tryParse(time.substring(2, 4)) ?? 0) : 0;
    return h * 60 + m;
  }

  // ─── Operations ─────────────────────────────────────────────

  /// Reorders a stop. Returns `true` when the order actually changed and the
  /// resulting schedule is still valid. On an invalid reorder the change is
  /// reverted and [_error] carries a user-friendly reason. Elapsed/locked
  /// stops can never be moved.
  bool reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return false;
    if (oldIndex < 0 || oldIndex >= _stops.length) return false;

    // Locked (elapsed) stops are never rearranged.
    if (!isStopEditable(oldIndex) ||
        (newIndex >= 0 && newIndex < _stops.length && !isStopEditable(newIndex))) {
      _error = 'This stop can no longer be changed. Its scheduled time has '
          'already passed.';
      notifyListeners();
      return false;
    }

    final snapshot = _snapshotStops();
    final item = _stops.removeAt(oldIndex);
    _stops.insert(newIndex, item);
    _rechainSchedule();

    final errors = validate();
    if (errors.isNotEmpty) {
      _restoreStops(snapshot);
      _error = errors.first;
      notifyListeners();
      return false;
    }
    _error = null;
    notifyListeners();
    return true;
  }

  /// Sets a new start time for a stop and rechains the rest of the day.
  /// Returns `true` only when the new time keeps the day valid; otherwise the
  /// change is reverted and [_error] carries a user-friendly reason.
  bool setStartTime(int index, TimeOfDay newTime) {
    if (index < 0 || index >= _stops.length) return false;
    if (!isStopEditable(index)) {
      _error = stopLockedReason(index);
      notifyListeners();
      return false;
    }

    final snapshot = _snapshotStops();
    final stop = _stops[index];
    stop.startTime = DateTime(
      stop.startTime.year,
      stop.startTime.month,
      stop.startTime.day,
      newTime.hour,
      newTime.minute,
    );
    stop.endTime = stop.startTime.add(Duration(minutes: stop.durationMinutes));
    _rechainSchedule();

    final errors = validate();
    if (errors.isNotEmpty) {
      _restoreStops(snapshot);
      _error = errors.first;
      notifyListeners();
      return false;
    }
    _error = null;
    notifyListeners();
    return true;
  }

  bool removeStop(int index) {
    if (index < 0 || index >= _stops.length) return false;
    if (_stops[index].isMustVisit) {
      _error = 'This place is a must-visit and cannot be removed.';
      notifyListeners();
      return false;
    }
    // Locked (elapsed) stops cannot be removed from the record.
    if (!isStopEditable(index)) {
      _error = 'This stop can no longer be changed. Its scheduled time has '
          'already passed.';
      notifyListeners();
      return false;
    }
    _stops.removeAt(index);
    _rechainSchedule();
    _error = null;
    notifyListeners();
    return true;
  }

  bool canAddCandidate(Place candidate) {
    if (_stops.any((s) => s.placeId == candidate.placeId)) {
      _error = 'This place is already in your itinerary.';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Adds a candidate to the end of the day. Returns `true` only when the
  /// addition keeps the day valid; otherwise the addition is reverted and
  /// [_error] carries a user-friendly reason.
  bool addCandidate(Place candidate) {
    if (!canAddCandidate(candidate)) return false;

    final snapshot = _snapshotStops();
    final day = _tripStartDate.add(Duration(days: _dayIndex));
    final startTime = _stops.isNotEmpty
        ? _stops.last.endTime.add(const Duration(minutes: 15))
        : DateTime(day.year, day.month, day.day, 9, 0);
    final endTime = startTime.add(Duration(minutes: candidate.visitDurationMinutes ?? 90));
    _stops.add(EditableStop(
      placeId: candidate.placeId,
      name: candidate.placeName,
      address: candidate.placeAddress,
      durationMinutes: candidate.visitDurationMinutes ?? 90,
      isMustVisit: _mustVisitPlaceIds.contains(candidate.placeId),
      place: candidate,
      startTime: startTime,
      endTime: endTime,
      travelFromPrevMinutes: _stops.isNotEmpty ? 15 : 0,
    ));
    _rechainSchedule();

    final errors = validate();
    if (errors.isNotEmpty) {
      _restoreStops(snapshot);
      _error = errors.first;
      notifyListeners();
      return false;
    }
    _error = null;
    notifyListeners();
    return true;
  }

  /// Replaces a stop. Returns `true` only when the replacement keeps the day
  /// valid; otherwise the original stop is restored and [_error] carries a
  /// user-friendly reason.
  bool replaceStop(int index, Place candidate) {    if (index < 0 || index >= _stops.length) return false;
    if (_stops.any((s) => s.placeId == candidate.placeId && s.placeId != _stops[index].placeId)) {
      _error = 'This place is already in your itinerary.';
      notifyListeners();
      return false;
    }

    final snapshot = _snapshotStops();
    _stops[index] = EditableStop(
      placeId: candidate.placeId,
      name: candidate.placeName,
      address: candidate.placeAddress,
      durationMinutes: candidate.visitDurationMinutes ?? 90,
      isMustVisit: _mustVisitPlaceIds.contains(candidate.placeId),
      place: candidate,
      startTime: _stops[index].startTime,
      endTime: _stops[index].startTime.add(Duration(minutes: candidate.visitDurationMinutes ?? 90)),
      travelFromPrevMinutes: _stops[index].travelFromPrevMinutes,
    );
    _rechainSchedule();

    final errors = validate();
    if (errors.isNotEmpty) {
      _restoreStops(snapshot);
      _error = errors.first;
      notifyListeners();
      return false;
    }
    _error = null;
    notifyListeners();
    return true;
  }

  /// Applies a validated proposed day (from the Add Custom Place workflow)
  /// to the temporary stop list. The proposal is re-validated with the same
  /// deterministic engine; on failure the previous temporary state is
  /// restored and [_error] carries a user-friendly reason.
  bool applyProposedDay(ScheduledDay proposedDay) {
    final snapshot = _snapshotStops();
    final converted = proposedDay.stops.map((s) {
      final p = s.attraction.place;
      return EditableStop(
        placeId: p.placeId,
        name: p.placeName,
        address: p.placeAddress,
        durationMinutes: s.durationMinutes,
        isMustVisit: _mustVisitPlaceIds.contains(p.placeId),
        place: p,
        startTime: s.startTime,
        endTime: s.endTime,
        travelFromPrevMinutes: s.travelFromPreviousMinutes,
      );
    }).toList();

    _stops = converted;
    final errors = validate();
    if (errors.isNotEmpty) {
      _restoreStops(snapshot);
      _error = errors.first;
      notifyListeners();
      return false;
    }
    _error = null;
    notifyListeners();
    return true;
  }

  // ─── Validation ─────────────────────────────────────────────

  /// Returns a list of error messages. Empty list means validation passed.
  List<String> validate() {
    final errors = <String>[];
    debugPrint('[EDIT VALIDATION] Started');

    // 1. Must-visits all present.
    for (final mvId in _mustVisitPlaceIds) {
      if (!_stops.any((s) => s.placeId == mvId)) {
        errors.add('This change removes a required must-visit place.');
        break;
      }
    }
    debugPrint('[EDIT VALIDATION] Must-visits: ${errors.isEmpty ? "PASS" : "FAIL"}');

    // 2. No duplicate place IDs.
    final ids = _stops.map((s) => s.placeId).toList();
    if (ids.length != ids.toSet().length) {
      errors.add('You have duplicate stops in this day.');
    }
    debugPrint('[EDIT VALIDATION] Duplicates: ${errors.isEmpty ? "PASS" : "FAIL"}');

    if (_stops.isEmpty) {
      errors.add('Add at least one stop before finishing.');
      debugPrint('[EDIT VALIDATION] RESULT: FAIL');
      return errors;
    }

    // 3. Exploration window + chronological order.
    final win = window;
    final winStart = win.startMinutes;
    final winEnd = win.endMinutes;

    for (int i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      final startMins = s.startTime.hour * 60 + s.startTime.minute;
      final endMins = s.endTime.hour * 60 + s.endTime.minute;

      if (endMins <= startMins) {
        errors.add('Stop "${s.name}" has an invalid time sequence (end before start).');
        break;
      }
      if (startMins < winStart || endMins > winEnd) {
        errors.add('"${s.name}" is outside the available exploration time '
            '(${_fmtWin(winStart)}–${_fmtWin(winEnd)}).');
        break;
      }

      // Check chronological order between consecutive stops.
      if (i > 0) {
        final prev = _stops[i - 1];
        final prevEndMins = prev.endTime.hour * 60 + prev.endTime.minute;
        if (startMins < prevEndMins + s.travelFromPrevMinutes) {
          errors.add('The selected order requires more travel time than is available '
              'between "${prev.name}" and "${s.name}".');
          break;
        }
      }
    }
    debugPrint('[EDIT VALIDATION] Exploration time: ${errors.isEmpty ? "PASS" : "FAIL"}');
    debugPrint('[EDIT VALIDATION] Travel time: ${errors.isEmpty ? "PASS" : "FAIL"}');

    // 4. Opening hours (best-effort).
    if (errors.isEmpty) {
      for (final s in _stops) {
        final oh = s.place.openingHours;
        if (oh == null || oh.periods.isEmpty) continue;
        final dayOfWeek = (_tripStartDate.add(Duration(days: _dayIndex)).weekday) % 7;
        final matchingPeriods = oh.periods.where((p) => p.open.day == dayOfWeek);
        if (matchingPeriods.isNotEmpty) {
          final allMatch = matchingPeriods.every((p) {
            final openMin = int.parse(p.open.time.substring(0, 2)) * 60 +
                int.parse(p.open.time.substring(2, 4));
            final closeMin = int.parse(p.close.time.substring(0, 2)) * 60 +
                int.parse(p.close.time.substring(2, 4));
            final startMins = s.startTime.hour * 60 + s.startTime.minute;
            final endMins = s.endTime.hour * 60 + s.endTime.minute;
            return startMins >= openMin && endMins <= closeMin;
          });
          if (!allMatch) {
            errors.add('"${s.name}" is closed during the selected time.');
            debugPrint('[EDIT VALIDATION] Opening hours: FAIL');
            break;
          }
        }
      }
      debugPrint('[EDIT VALIDATION] Opening hours: PASS');
    }

    debugPrint('[EDIT VALIDATION] RESULT: ${errors.isEmpty ? "PASS" : "FAIL"}');
    return errors;
  }

  /// Build an updated [ItineraryResult] with the edited day replacing the
  /// original. Does NOT mutate the original.
  void applyChanges() {
    final errors = validate();
    if (errors.isNotEmpty) {
      _error = errors.first;
      notifyListeners();
      return;
    }

    final originalDays = _originalResult.scheduledDays ?? const [];
    if (_dayIndex < 0 || _dayIndex >= originalDays.length) return;

    final newDays = List<ScheduledDay>.from(originalDays);
    newDays[_dayIndex] = _buildScheduledDay();

    // Build a new result with the updated days.
    // The view will receive it via the screen's pop return.
    _appliedResult = ItineraryResult.success(
      scheduledDays: newDays,
      weather: _originalResult.weather ?? WeatherForecast(daily: []),
      criticFeedback: _originalResult.criticFeedback ??
          CriticResult(
            overallSuitable: true, score: 0, issues: [], recommendations: [], summary: ''),
      warnings: _originalResult.warnings,
      candidatePool: _originalResult.candidatePool,
      placeRegistry: _originalResult.placeRegistry,
      scoredCandidates: _originalResult.scoredCandidates,
      clusters: _originalResult.clusters,
      unretrievableMustVisits: _originalResult.unretrievableMustVisits,
    );
    _error = null;
    notifyListeners();
  }

  ItineraryResult? _appliedResult;
  ItineraryResult? get appliedResult => _appliedResult;

  // ─── Private helpers ────────────────────────────────────────

  List<EditableStop> _buildStops() {
    final days = _originalResult.scheduledDays;
    if (days == null || _dayIndex >= days.length) return [];
    final day = days[_dayIndex];
    // Identify must-visit IDs from scored candidates.
    final mustVisitIds = _mustVisitPlaceIds.toSet();
    return day.stops.map((s) {
      final p = s.attraction.place;
      return EditableStop(
        placeId: p.placeId,
        name: p.placeName,
        address: p.placeAddress,
        durationMinutes: s.durationMinutes,
        isMustVisit: mustVisitIds.contains(p.placeId) || s.attraction.isMustVisit,
        place: p,
        startTime: s.startTime,
        endTime: s.endTime,
        travelFromPrevMinutes: s.travelFromPreviousMinutes,
      );
    }).toList();
  }

  ScheduledDay _buildScheduledDay() {
    var totalDuration = 0;
    var totalTravel = 0.0;
    final day = _tripStartDate.add(Duration(days: _dayIndex));
    final scheduledStops = _stops.map((s) {
      totalDuration += s.durationMinutes;
      totalTravel += s.travelFromPrevMinutes;
      return ScheduledStop(
        attraction: _findScored(s.placeId) ??
            ScoredAttraction(place: s.place, score: 0, breakdown: const {}),
        startTime: s.startTime,
        endTime: s.endTime,
        durationMinutes: s.durationMinutes,
        travelFromPreviousMinutes: s.travelFromPrevMinutes,
        scheduleReason: '',
        weatherNote: '',
      );
    }).toList();

    return ScheduledDay(
      dayIndex: _dayIndex,
      date: day,
      stops: scheduledStops,
      totalDuration: totalDuration,
      totalTravelTime: totalTravel,
    );
  }

  ScoredAttraction? _findScored(String placeId) {
    for (final s in _originalResult.scoredCandidates ?? const <ScoredAttraction>[]) {
      if (s.place.placeId == placeId) return s;
    }
    return null;
  }

  /// Snapshot the current stop list for revert-on-invalid.
  List<EditableStop> _snapshotStops() => _stops.map((s) => s.copy()).toList();

  /// Restore stops from a snapshot and rechain the schedule.
  void _restoreStops(List<EditableStop> snapshot) {
    _stops = snapshot;
    _rechainSchedule();
  }

  /// Re-chain the schedule: recalculate start/end times sequentially from
  /// the first stop's start time, using travelFromPrevMinutes between stops.
  void _rechainSchedule() {
    if (_stops.isEmpty) return;
    for (int i = 1; i < _stops.length; i++) {
      final prev = _stops[i - 1];
      final cur = _stops[i];
      final travel = cur.travelFromPrevMinutes.clamp(0, 120);
      cur.startTime = prev.endTime.add(Duration(minutes: travel));
      cur.endTime = cur.startTime.add(Duration(minutes: cur.durationMinutes));
    }
  }

  bool _hasChanges() {
    final original = _buildStops();
    if (original.length != _stops.length) return true;
    for (int i = 0; i < _stops.length; i++) {
      if (_stops[i].placeId != original[i].placeId) return true;
      if (_stops[i].startTime.hour != original[i].startTime.hour ||
          _stops[i].startTime.minute != original[i].startTime.minute) return true;
    }
    return false;
  }

  String _fmtWin(int mins) {
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}