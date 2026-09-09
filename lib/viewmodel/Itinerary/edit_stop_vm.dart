
// lib/viewmodel/Itinerary/edit_stop_vm.dart
import 'package:flutter/foundation.dart';

import '../../core/config/itinerary_constants.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/itinerary_validator.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/itinerary/itinerary_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary/place_repository_adapter.dart';

/// Traveler progress for a single itinerary stop.
///
/// The traveler may edit the stop's scheduled START TIME, END TIME,
/// the progress status, the LOCATION (place), or remove the stop entirely.
/// Place identity (stopId, itineraryId, dayIndex, stopOrder) is preserved
/// when the location changes — the same stop slot keeps its scheduling context.
///
/// Edit Stop is DIRECT RECORD CUSTOMIZATION for ONE itinerary_stops row
/// (identified by stop_id) — not itinerary regeneration and not route
/// optimization. The traveler is the owner of this stop's schedule; the
/// generated day only provides the initial values.
///
/// Time/duration edits perform only basic data checks (end after start,
/// duration > 0); a location edit only requires valid place DATA
/// (place_id, name, coordinates). NOTHING here ever runs a route /
/// travel-time calculation (no travelMinutesBetween, no distance
/// computation) before or during a save, and travel_from_prev_minutes
/// is PRESERVED, never recalculated. Previous/next stop times, route
/// feasibility, traffic, pace, the exploration window, schedule
/// overlaps, duration constants and the original generated schedule are
/// NEVER rejection reasons. Overlaps are logged informationally
/// ([EDIT_STOP_CONFLICT]) and are ALLOWED — no other stop is ever read
/// as a restriction, moved, or written, and only this stop's row is
/// updated through _repo.updateStop(...).
class EditStopViewModel extends ChangeNotifier {
  static const String planned = 'PLANNED';
  static const String completed = 'COMPLETED';
  static const String skipped = 'SKIPPED';

  final ItineraryStopRepositoryImpl _repo = DatabaseManager().itineraryStopRepository;
  final ItineraryRepositoryImpl _itineraryRepo = DatabaseManager().itineraryRepository;
  final PlaceRepositoryAdapter _placeRepo = DatabaseManager().placeRepository;
  final ItineraryValidator _validator = ItineraryValidator();

  late ItineraryStop _stop;
  final DateTime _itineraryStartDate;
  final bool _isReadOnly;

  Itinerary? _itinerary;
  List<ItineraryStop>? _dayStopsWithPlaces;

  bool _isSaving = false;
  String? _error;

  // ── Temporary (uncommitted) time editing state ──────────────
  late DateTime _editedStartTime;
  late DateTime _editedEndTime;
  late int _editedDurationMinutes;

  // ── Dropdown options (full-day traveler choices) ─────────────
  List<DateTime> _availableStartTimes = [];
  List<DateTime> _availableEndTimes = [];
  List<int> _availableDurations = [];

  /// Practical visit-duration choices for the traveler. Edit Stop does
  /// NOT enforce a minimum/maximum here — anything > 0 is accepted.
  static const List<int> predefinedDurations = [
    10, 15, 30, 45, 60, 75, 90, 105, 120, 150, 180, 240, 270, 300, 360,
  ];

  /// Interval (minutes) between consecutive selectable start times.
  static const int startTimeStepMinutes = 30;

  /// Interval (minutes) between consecutive selectable end times.
  static const int endTimeStepMinutes = 30;

  EditStopViewModel({
    required ItineraryStop stop,
    required DateTime itineraryStartDate,
    bool isReadOnly = false,
  })  : _stop = stop,
        _itineraryStartDate = itineraryStartDate,
        _isReadOnly = isReadOnly {
    // The repository stores start/end as TIME-of-day (parsed onto an epoch
    // date). Pending edits are kept on the SAME itinerary-day basis as the
    // option grid so the dropdowns always show the stop's real current
    // time (display uses hour/minute only; persistence is unchanged).
    _editedStartTime = _combineWithDay(stop.startTime);
    _editedEndTime = _combineWithDay(stop.endTime);
    _editedDurationMinutes = stop.durationMinutes;
    _availableStartTimes = [_editedStartTime];
    _availableEndTimes = [_editedEndTime];
    _availableDurations = [stop.durationMinutes];
  }

  // ─── Getters ────────────────────────────────────────────────

  ItineraryStop get stop => _stop;
  bool get isSaving => _isSaving;
  String? get error => _error;
  String get status => _stop.stopStatus;
  bool get isCompleted => _stop.stopStatus == completed;
  bool get isSkipped => _stop.stopStatus == skipped;
  bool get isReadOnly => _isReadOnly;

  DateTime get editedStartTime => _editedStartTime;
  DateTime get editedEndTime => _editedEndTime;
  int get editedDurationMinutes => _editedDurationMinutes;

  bool get hasTimeChanges {
    return _editedStartTime.hour != _stop.startTime.hour ||
        _editedStartTime.minute != _stop.startTime.minute;
  }

  bool get hasEndTimeChanges {
    return _editedEndTime.hour != _stop.endTime.hour ||
        _editedEndTime.minute != _stop.endTime.minute;
  }

  bool get hasDurationChanges =>
      _editedDurationMinutes != _stop.durationMinutes;

  bool get hasUnsavedChanges =>
      hasTimeChanges || hasEndTimeChanges || hasDurationChanges;

  List<DateTime> get availableStartTimes =>
      List.unmodifiable(_availableStartTimes);

  List<DateTime> get availableEndTimes =>
      List.unmodifiable(_availableEndTimes);

  List<int> get availableDurations => List.unmodifiable(_availableDurations);

  DateTime get scheduledStartDateTime {
    final dayDate = _itineraryStartDate.add(Duration(days: _stop.dayIndex - 1));
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      _stop.startTime.hour,
      _stop.startTime.minute,
      _stop.startTime.second,
    );
  }

  bool get canCompleteNow => !DateTime.now().isBefore(scheduledStartDateTime);

  bool get isToday {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final stopDay = _itineraryStartDate.add(Duration(days: _stop.dayIndex - 1));
    final stopDayStart = DateTime(stopDay.year, stopDay.month, stopDay.day);
    return now.isAfter(stopDayStart) && now.isBefore(dayEnd);
  }

  /// Whether the stop can be edited (time, location, removal).
  /// A PLANNED stop is always editable — the fact that the originally
  /// scheduled time has passed does NOT lock customization of a planned
  /// stop. Only read-only itineraries and COMPLETED/SKIPPED stops lock.
  bool get isEditable =>
      !_isReadOnly && _stop.stopStatus.toUpperCase() == planned;

  /// Whether the stop can be reset to PLANNED (only if today and status not PLANNED).
  bool get canReset => isToday && _stop.stopStatus != planned;

  bool canTransitionTo(String newStatus) {
    final current = _stop.stopStatus;
    switch (newStatus) {
      case completed:
        return current == planned && canCompleteNow;
      case skipped:
        return current == planned;
      case planned:
        return current == completed || current == skipped;
      default:
        return false;
    }
  }

  // ─── Location change ─────────────────────────────────────────

  /// Replace THIS stop's location with a canonical, database-backed
  /// [Place] — a DIRECT record customization on ONE `itinerary_stops`
  /// row (by `stop_id`).
  ///
  /// Only `place_id` (and the in-memory Place) change. stopId,
  /// itineraryId, destinationId, dayIndex, stopOrder, start_time,
  /// end_time, duration_minutes, travel_from_prev_minutes, stop_status,
  /// skip_reason, weather_note and createdAt are all preserved.
  ///
  /// NO route calculation happens before or during the save (no
  /// travelMinutesBetween, no distance computation, no rerouting, no
  /// day/neighbor validation, no regeneration). The location change can
  /// therefore never fail because routing is unavailable — only invalid
  /// place DATA (missing id/name/coordinates) is rejected. No other stop
  /// is read as a restriction, moved, or written.
  Future<bool> changePlace(Place newPlace) async {
    debugPrint('[EDIT_STOP_LOCATION] Starting location change');
    debugPrint('[EDIT_STOP_LOCATION] Stop ID: ${_stop.stopId}');
    debugPrint('[EDIT_STOP_LOCATION] Old place ID: ${_stop.placeId}');
    debugPrint('[EDIT_STOP_LOCATION] New place ID: ${newPlace.placeId}');
    debugPrint('[EDIT_STOP_LOCATION] New place name: ${newPlace.placeName}');

    if (!isEditable) {
      _error = _buildLockedMessage();
      notifyListeners();
      return false;
    }

    // Basic place validation only.
    if (newPlace.placeId.trim().isEmpty ||
        newPlace.placeName.trim().isEmpty ||
        (newPlace.placeLatitude == 0 &&
            newPlace.placeLongitude == 0)) {
      _error = 'This place does not have enough information to be used in '
          'the itinerary.';
      notifyListeners();
      return false;
    }

    // Do nothing if the user selected the current place.
    if (newPlace.placeId.trim() == _stop.placeId.trim()) {
      _error = null;
      return true;
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      // Build a copy of ONLY THIS stop.
      //
      // Important:
      // - Same stopId
      // - Same itineraryId
      // - Same dayIndex
      // - Same stopOrder
      // - Same time
      // - Same duration
      // - Same status
      // - ONLY placeId/place are changed
      final updated = _buildUpdatedStop(
        placeId: newPlace.placeId,
        place: newPlace,
      );

      debugPrint('[EDIT_STOP_LOCATION] Updating database');
      debugPrint('[EDIT_STOP_LOCATION] stopId=${updated.stopId}');
      debugPrint('[EDIT_STOP_LOCATION] oldPlaceId=${_stop.placeId}');
      debugPrint('[EDIT_STOP_LOCATION] newPlaceId=${updated.placeId}');

      // ONLY database update.
      //
      // NO:
      // - route calculation
      // - travelMinutesBetween()
      // - validator route check
      // - rerouting
      // - updating other stops
      final saved = await _repo.updateStop(updated);

      debugPrint('[EDIT_STOP_LOCATION] Database update successful');

      // Update the ViewModel with the saved stop.
      _stop = saved.copyWith(place: newPlace);

      // Clear cached day data so the next read gets the updated place.
      _dayStopsWithPlaces = null;

      _error = null;
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Unable to update the stop. Please try again.';
      debugPrint('[EDIT_STOP_LOCATION] Database update failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // ─── Time editing ───────────────────────────────────────────

  /// Set a new temporary START time — the traveler's decision.
  ///
  /// ANY time of day is accepted (08:00, 13:30, 22:00 …). Previous /
  /// next stops, travel time, route feasibility, traffic, pace, the
  /// exploration window, duration constants and schedule conflicts are
  /// NEVER rejection reasons for Edit Stop customization. The end time is
  /// re-derived as start + duration so the triple stays consistent, and
  /// no other stop is ever moved.
  Future<bool> setStartTime(DateTime newStart) async {
    final candidate = _combineWithDay(newStart);
    final duration = _editedDurationMinutes;

    debugPrint('[EDIT_STOP_TIME] Old Start Time: ${_fmt(_editedStartTime)}');
    debugPrint('[EDIT_STOP_TIME] Traveler Selected Start Time: '
        '${_fmt(candidate)}');
    debugPrint('[EDIT_STOP_TIME] Current End Time: ${_fmt(_editedEndTime)}');
    debugPrint('[EDIT_STOP_TIME] Duration: $duration');
    debugPrint('[EDIT_STOP_TIME] Schedule validation bypassed in '
        'customization mode');

    if (!isEditable) {
      _error = _buildLockedMessage();
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - stop not '
          'editable (${_buildLockedMessage()})');
      notifyListeners();
      return false;
    }

    if (duration <= 0) {
      _error = 'The selected duration is invalid.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - duration must '
          'be greater than 0');
      notifyListeners();
      return false;
    }

    final newEnd = candidate.add(Duration(minutes: duration));
    _editedStartTime = candidate;
    _editedEndTime = newEnd;
    _error = null;
    debugPrint('[EDIT_STOP_TIME] Traveler time accepted '
        '(${_fmt(candidate)} - ${_fmt(newEnd)})');
    await _logScheduleContext();
    await refreshTimeOptions();
    notifyListeners();
    return true;
  }

  /// Set a new temporary END time — the traveler's decision.
  /// The duration is re-derived as end − start. The only relationship
  /// kept is End Time after Start Time; the next stop, the exploration
  /// window and the original duration never restrict the choice.
  Future<bool> setEndTime(DateTime newEnd) async {
    final candidate = _combineWithDay(newEnd);
    final startMin = _minutesSinceMidnight(_editedStartTime);
    final endMin = _minutesSinceMidnight(candidate);

    debugPrint('[EDIT_STOP_TIME] Old End Time: ${_fmt(_editedEndTime)}');
    debugPrint('[EDIT_STOP_TIME] Traveler Selected End Time: '
        '${_fmt(candidate)}');
    debugPrint('[EDIT_STOP_TIME] Current Start Time: '
        '${_fmt(_editedStartTime)}');
    debugPrint('[EDIT_STOP_TIME] Schedule validation bypassed in '
        'customization mode');

    if (!isEditable) {
      _error = _buildLockedMessage();
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - stop not '
          'editable (${_buildLockedMessage()})');
      notifyListeners();
      return false;
    }

    if (endMin <= startMin) {
      _error = 'End time must be after start time.';
      debugPrint('[EDIT_STOP_TIME] REJECTED: start time must be before '
          'end time');
      notifyListeners();
      return false;
    }

    final newDuration = endMin - startMin;
    _editedEndTime = candidate;
    _editedDurationMinutes = newDuration;
    _error = null;
    debugPrint('[EDIT_STOP_TIME] Traveler time accepted '
        '(${_fmt(_editedStartTime)} - ${_fmt(candidate)}, $newDuration '
        'minutes)');
    await _logScheduleContext();
    await refreshTimeOptions();
    notifyListeners();
    return true;
  }

  /// Set a new temporary DURATION — the traveler's decision.
  /// Only rule: duration > 0. `places.visit_duration_minutes`, the
  /// generated duration and the min/max duration constants are NOT
  /// applied to Edit Stop customization (10 or 300 minutes both pass).
  /// End is re-derived as start + duration; other stops are never moved.
  Future<bool> setDuration(int newDurationMinutes) async {
    debugPrint('[EDIT_STOP_DURATION] Old duration: $_editedDurationMinutes');
    debugPrint('[EDIT_STOP_DURATION] New duration: $newDurationMinutes');
    debugPrint('[EDIT_STOP_DURATION] Start: ${_fmt(_editedStartTime)}');
    debugPrint('[EDIT_STOP_DURATION] Calculated end: '
        '${_fmt(_editedStartTime.add(Duration(minutes: newDurationMinutes)))}');
    debugPrint('[EDIT_STOP_DURATION] Schedule validation bypassed in '
        'customization mode');

    if (!isEditable) {
      _error = _buildLockedMessage();
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - stop not '
          'editable (${_buildLockedMessage()})');
      notifyListeners();
      return false;
    }
    if (newDurationMinutes <= 0) {
      _error = 'The selected duration is invalid.';
      debugPrint('[EDIT_STOP_DURATION] REJECTED: duration must be greater '
          'than 0');
      notifyListeners();
      return false;
    }
    if (newDurationMinutes == _editedDurationMinutes) {
      _error = null;
      return true;
    }

    final candidateEnd =
    _editedStartTime.add(Duration(minutes: newDurationMinutes));
    _editedDurationMinutes = newDurationMinutes;
    _editedEndTime = candidateEnd;
    _error = null;
    debugPrint('[EDIT_STOP_DURATION] Duration accepted '
        '(${_fmt(_editedStartTime)} - ${_fmt(candidateEnd)})');
    await _logScheduleContext();
    await refreshTimeOptions();
    notifyListeners();
    return true;
  }

  /// Persist the pending time changes EXACTLY as the traveler selected
  /// them, updating ONLY this itinerary_stops row (by stop_id).
  ///
  /// Basic checks only — end after start and a positive duration. NO
  /// ItineraryValidator / day / route / travel / neighbor validation runs
  /// for a time edit, and no other stop is read, moved or written.
  Future<bool> saveTimeChanges() async {
    if (!isEditable) {
      _error = _buildLockedMessage();
      notifyListeners();
      return false;
    }
    if (!hasUnsavedChanges) {
      _error = null;
      return true;
    }

    final start = _combineWithDay(_editedStartTime);
    final end = _combineWithDay(_editedEndTime);

    // ── Basic data validity ONLY (end_time > start_time, duration > 0) ──
    if (!end.isAfter(start)) {
      _error = 'End time must be after start time.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - end time must '
          'be after start time');
      notifyListeners();
      return false;
    }

    final durationMinutes = end.difference(start).inMinutes;
    if (durationMinutes <= 0) {
      _error = 'The selected time must have a valid duration.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - duration must '
          'be greater than 0');
      notifyListeners();
      return false;
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      // Same stopId / itineraryId / destinationId / dayIndex / stopOrder /
      // travelFromPrevMinutes / status / skipReason / weatherNote /
      // createdAt — only the times change.
      final updatedStop = _buildUpdatedStop(
        startTime: start,
        endTime: end,
        durationMinutes: durationMinutes,
      );

      debugPrint('[EDIT_STOP_SAVE] Saving edited stop');
      debugPrint('[EDIT_STOP_SAVE] stopId=${updatedStop.stopId}');
      debugPrint('[EDIT_STOP_SAVE] start=${_fmt(start)}');
      debugPrint('[EDIT_STOP_SAVE] end=${_fmt(end)}');
      debugPrint('[EDIT_STOP_SAVE] duration=$durationMinutes');
      debugPrint('[EDIT_STOP_SAVE] schedule constraints=IGNORED '
          '(traveler customization — no route/day validation)');

      // ONE row, by stop_id, through the existing repository.
      final saved = await _repo.updateStop(updatedStop);

      // Adopt the returned DB record; drop the cached day list so the
      // next read reflects the new value.
      _stop = saved.copyWith(place: _stop.place);
      _editedStartTime = _combineWithDay(saved.startTime);
      _editedEndTime = _combineWithDay(saved.endTime);
      _editedDurationMinutes = saved.durationMinutes;
      _dayStopsWithPlaces = null;
      _error = null;

      debugPrint('[EDIT_STOP_SAVE] Save successful');
      await _logScheduleContext();
      await refreshTimeOptions();
      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      // Failure: the ViewModel keeps the ORIGINAL stop untouched.
      _error = 'Unable to update the stop. Please try again.';
      debugPrint('[EDIT_STOP_SAVE] Save failed: $e');
      debugPrint('[EDIT_STOP_SAVE] $stackTrace');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Informational schedule context for the pending edit: neighbors and
  /// overlaps. LOGGING ONLY — an overlap NEVER rejects the change,
  /// NEVER alters the selected time and NEVER moves another stop.
  Future<void> _logScheduleContext() async {
    try {
      final dayStops = await _loadDayStops();
      _logOverlapInfo([
        for (final s in dayStops)
          if (s.stopId == _stop.stopId)
            _buildUpdatedStop(
              startTime: _editedStartTime,
              endTime: _editedEndTime,
              durationMinutes: _editedDurationMinutes,
            )
          else
            s,
      ]);
    } catch (e) {
      debugPrint('[EDIT_STOP_CONFLICT] schedule context unavailable: $e');
    }
  }

  /// Logs overlaps between the (pending) edited stop and its neighbours.
  /// Overlaps are ALLOWED in customization mode — this method only
  /// reports; it never rejects and never adjusts any stop's time.
  void _logOverlapInfo(List<ItineraryStop> dayStops) {
    final sorted = List<ItineraryStop>.from(dayStops)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    final idx = sorted.indexWhere((s) => s.stopId == _stop.stopId);
    if (idx < 0) return;
    final cur = sorted[idx];
    var overlapped = false;

    if (idx > 0) {
      final prev = sorted[idx - 1];
      debugPrint('[EDIT_STOP_TIME] Existing previous stop=${prev.stopId} '
          'ends ${_fmt(prev.endTime)}');
      if (cur.startTime.isBefore(prev.endTime)) {
        overlapped = true;
        debugPrint('[EDIT_STOP_CONFLICT] Time overlap detected');
        debugPrint('[EDIT_STOP_CONFLICT] Conflict detected with '
            'stopId=${prev.stopId} — informational only');
      }
    }
    if (idx < sorted.length - 1) {
      final next = sorted[idx + 1];
      debugPrint('[EDIT_STOP_TIME] Existing next stop=${next.stopId} '
          'starts ${_fmt(next.startTime)}');
      if (cur.endTime.isAfter(next.startTime)) {
        overlapped = true;
        debugPrint('[EDIT_STOP_CONFLICT] Time overlap detected');
        debugPrint('[EDIT_STOP_CONFLICT] Conflict detected with '
            'stopId=${next.stopId} — informational only');
      }
    }

    if (overlapped) {
      debugPrint('[EDIT_STOP_CONFLICT] Overlap is allowed in customization '
          'mode — traveler-selected time preserved');
      debugPrint('[EDIT_STOP_CONFLICT] No automatic schedule adjustment');
    } else {
      debugPrint('[EDIT_STOP_CONFLICT] No time overlap with neighboring '
          'stops; nothing to adjust');
    }
  }

  void resetTimeEdits() {
    _editedStartTime = _stop.startTime;
    _editedEndTime = _stop.endTime;
    _editedDurationMinutes = _stop.durationMinutes;
    _error = null;
    notifyListeners();
  }

  // ─── Status ─────────────────────────────────────────────────

  Future<bool> updateStatus(String newStatus, {String? skipReason}) async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }

    if (newStatus == _stop.stopStatus) {
      _error = null;
      return true;
    }

    if (isCompleted) {
      _error = 'This stop is already completed.';
      notifyListeners();
      return false;
    }

    if (!canTransitionTo(newStatus)) {
      if (newStatus == completed && !canCompleteNow) {
        _error = 'This stop cannot be completed yet.\n'
            'Please wait until its scheduled time.';
      } else {
        _error = 'Cannot change from ${_stop.stopStatus} to $newStatus '
            'directly. Please go back to Planned first.';
      }
      notifyListeners();
      return false;
    }

    debugPrint('[EDIT STOP] Status change confirmed');
    debugPrint('[EDIT STOP] From: ${_stop.stopStatus}');
    debugPrint('[EDIT STOP] To: $newStatus');

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = _buildUpdatedStop(
        stopStatus: newStatus,
        skipReason:
        newStatus == skipped ? (skipReason ?? _stop.skipReason) : null,
      );

      final saved = await _repo.updateStop(updated);
      _stop = saved.copyWith(place: _stop.place);
      notifyListeners();
      debugPrint('[EDIT STOP] Status updated successfully');
      return true;
    } catch (e) {
      _error = 'Unable to update the stop status. Please try again.';
      debugPrint('[EditStopVM] Status update failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Reset status to PLANNED – only allowed if the stop is today and status is not PLANNED.
  Future<bool> resetStatus() async {
    if (!canReset) {
      _error = 'Status can only be reset on today\'s stops.';
      notifyListeners();
      return false;
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = _buildUpdatedStop(
        stopStatus: planned,
        skipReason: null,
        clearSkipReason: true,
      );

      final saved = await _repo.updateStop(updated);
      _stop = saved.copyWith(place: _stop.place);
      _error = null;
      notifyListeners();
      debugPrint('[EDIT STOP] Status reset to PLANNED');
      return true;
    } catch (e) {
      _error = 'Unable to reset status. Please try again.';
      debugPrint('[EditStopVM] Reset status failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> saveSkipReason(String? reason) async {
    if (reason == _stop.skipReason) return true;

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = _buildUpdatedStop(skipReason: reason);

      final saved = await _repo.updateStop(updated);
      _stop = saved.copyWith(place: _stop.place);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Unable to update the stop note. Please try again.';
      debugPrint('[EditStopVM] Skip reason save failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteStop() async {
    if (!isEditable) {
      _error = _buildLockedMessage();
      notifyListeners();
      return false;
    }
    if (_stop.stopId == 0) return false;

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final dayStops = await _loadDayStops();
      final removedIndex =
      dayStops.indexWhere((s) => s.stopId == _stop.stopId);
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId != _stop.stopId) s,
      ];

      final itinerary = await _loadItinerary();
      final reroute = <int>{
        if (removedIndex > 0 && removedIndex < resulting.length) removedIndex,
      };

      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        rerouteLegIndices: reroute,
        travelPace: itinerary.travelPace,
      );

      if (!result.isValid) {
        _error = result.issues.first.message;
        notifyListeners();
        return false;
      }

      await _repo.deleteStop(_stop.stopId);
      _dayStopsWithPlaces = null;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Unable to remove the stop. Please try again.';
      debugPrint('[EditStopVM] Stop delete failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // ─── Helpers ────────────────────────────────────────────────

  String _buildLockedMessage() {
    if (_stop.stopStatus == completed) {
      return 'This stop has already been completed and cannot be modified.';
    } else if (_stop.stopStatus == skipped) {
      return 'This stop has been skipped and cannot be modified.';
    } else if (_isReadOnly) {
      return 'This itinerary is in the past and cannot be modified.';
    } else {
      return 'This stop cannot be modified at this time.';
    }
  }

  Future<Itinerary> _loadItinerary() async {
    return _itinerary ??= await _itineraryRepo.getItinerary(_stop.itineraryId);
  }

  Future<List<ItineraryStop>> _loadDayStops() async {
    final cached = _dayStopsWithPlaces;
    if (cached != null) return cached;

    final all = await _repo.getStopsForItinerary(_stop.itineraryId);
    final dayStops = all.where((s) => s.dayIndex == _stop.dayIndex).toList()
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

    final joined = <ItineraryStop>[];
    for (final stop in dayStops) {
      var place = stop.place;
      if (place == null) {
        try {
          place = await _placeRepo.getPlace(stop.placeId);
        } catch (e) {
          debugPrint('[EditStopVM] Place join failed for '
              '${stop.placeId}: $e');
        }
      }
      joined.add(stop.copyWith(place: place));
    }

    _dayStopsWithPlaces = joined;
    return joined;
  }

  DateTime _dayDate(Itinerary itinerary) =>
      itinerary.startDate.add(Duration(days: _stop.dayIndex - 1));

  ItineraryStop _buildUpdatedStop({
    DateTime? startTime,
    DateTime? endTime,
    int? durationMinutes,
    String? stopStatus,
    String? skipReason,
    String? placeId,
    Place? place,
    bool clearSkipReason = false,
  }) {
    return ItineraryStop(
      stopId: _stop.stopId,
      itineraryId: _stop.itineraryId,
      placeId: placeId ?? _stop.placeId,
      destinationId: _stop.destinationId,
      dayIndex: _stop.dayIndex,
      stopOrder: _stop.stopOrder,
      startTime: startTime ?? _stop.startTime,
      endTime: endTime ?? _stop.endTime,
      durationMinutes: durationMinutes ?? _stop.durationMinutes,
      travelFromPrevMinutes: _stop.travelFromPrevMinutes,
      stopStatus: stopStatus ?? _stop.stopStatus,
      skipReason: clearSkipReason
          ? null
          : (skipReason ?? _stop.skipReason),
      weatherNote: _stop.weatherNote,
      place: place ?? _stop.place,
      createdAt: _stop.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  // ─── Option refresh ─────────────────────────────────────────

  Future<void> refreshTimeOptions() async {
    try {
      final itinerary = await _loadItinerary();
      final dayStops = await _loadDayStops();
      await _refreshTimeOptions(itinerary, dayStops);
    } catch (e) {
      debugPrint('[EditStopVM] Could not refresh options: $e');
    }
    notifyListeners();
  }

  /// Rebuilds the dropdown options as the TRAVELER's full customization
  /// choices: every step slot of the 24-hour day for start and end, and
  /// the whole duration list — never filtered by previous/next stops,
  /// travel, route, conflicts, the exploration window or the min/max
  /// duration constants. The currently selected (even off-grid/custom)
  /// value is always preserved in the list so the UI never silently
  /// replaces the traveler's choice.
  Future<void> _refreshTimeOptions(
      Itinerary itinerary,
      List<ItineraryStop> dayStops,
      ) async {
    // ── Start times: full 24-hour day at the existing step ──────────
    final startSlots = <DateTime>[];
    for (int minutes = 0; minutes < 24 * 60; minutes += startTimeStepMinutes) {
      startSlots.add(_atMinutes(minutes));
    }
    if (!startSlots.any((t) =>
    t.hour == _editedStartTime.hour &&
        t.minute == _editedStartTime.minute)) {
      startSlots.add(_editedStartTime);
    }
    startSlots.sort((a, b) => a.compareTo(b));
    _availableStartTimes = startSlots;

    // ── End times: full 24-hour day (end > start is enforced by
    //    setEndTime, not by hiding choices) ──────────────────────────
    final endSlots = <DateTime>[];
    for (int minutes = 0; minutes < 24 * 60; minutes += endTimeStepMinutes) {
      endSlots.add(_atMinutes(minutes));
    }
    if (!endSlots.any((t) =>
    t.hour == _editedEndTime.hour &&
        t.minute == _editedEndTime.minute)) {
      endSlots.add(_editedEndTime);
    }
    endSlots.sort((a, b) => a.compareTo(b));
    _availableEndTimes = endSlots;

    // ── Durations: every positive predefined choice + current ──────
    final durationSlots = <int>[];
    for (final d in predefinedDurations) {
      if (d > 0) durationSlots.add(d);
    }
    if (_editedDurationMinutes > 0 &&
        !durationSlots.contains(_editedDurationMinutes)) {
      durationSlots.add(_editedDurationMinutes);
    }
    durationSlots.sort();
    _availableDurations = durationSlots;

    debugPrint('[EDIT_STOP] Time options refreshed: '
        '${startSlots.length} start / ${endSlots.length} end / '
        '${durationSlots.length} duration options — full-day '
        'customization choices (schedule-based filtering NOT applied)');
  }

  // ─── Basic time helpers ───────────────────────────────────────

  /// Normalize [t] onto the itinerary day of this stop, keeping only
  /// hour/minute. Avoids comparisons across different DateTime dates.
  DateTime _combineWithDay(DateTime timeOfDay) {
    final dayDate = _itineraryStartDate.add(Duration(days: _stop.dayIndex - 1));
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
  }

  /// Minutes since midnight — the unit all time-validity comparisons use.
  int _minutesSinceMidnight(DateTime t) => t.hour * 60 + t.minute;

  DateTime _atMinutes(int minutes) {
    final dayDate =
    _itineraryStartDate.add(Duration(days: _stop.dayIndex - 1));
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      minutes ~/ 60,
      minutes % 60,
    );
  }

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
