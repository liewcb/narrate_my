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
/// Edit Stop is TRAVELER CUSTOMIZATION — the traveler is the owner of
/// this stop's schedule; the generated day is only the initial values.
/// Time, duration and location edits are checked for DATA validity only
/// (end after start, duration > 0, a valid canonical Place, day-level
/// duplicate protection and the place's operating hours evaluated on
/// the itinerary day's date).
///
/// NEVER a rejection reason in Edit Stop: previous/next stop times,
/// travel time, distance, route feasibility/optimization, traffic,
/// travel pace, the exploration window, schedule overlaps, the
/// min/max duration constants or the original generated schedule.
/// Overlaps are logged informationally ([EDIT_STOP_CONFLICT]) and are
/// ALLOWED — no stop is ever moved, reordered or adjusted automatically.
/// Route data is calculated/saved as information only
/// ([EDIT_STOP_ROUTE_INFO]). [ItineraryValidator] runs solely in
/// customization mode for this flow (no route/travel/inter-stop/window
/// validation); full generation-time validation remains intact for every
/// other module via the default mode.
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
    _editedStartTime = stop.startTime;
    _editedEndTime = stop.endTime;
    _editedDurationMinutes = stop.durationMinutes;
    _availableStartTimes = [stop.startTime];
    _availableEndTimes = [stop.endTime];
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
  /// Editable only if not read-only AND status is PLANNED.
  bool get isEditable => !_isReadOnly && _stop.stopStatus == planned && !isTimeOver;

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

  /// Replace THIS stop's location with a canonical, database-backed [Place].
  ///
  /// LOCATION CUSTOMIZATION, NOT ROUTE OPTIMIZATION: distance, travel
  /// time and route feasibility are calculated and PERSISTED as
  /// INFORMATION ONLY. They never reject the traveler's choice. Only
  /// genuine/basic rules block a change: an incomplete/invalid Place
  /// record, a duplicate of a place already scheduled in the day, and
  /// the place's own operating hours vs. the scheduled visit (existing
  /// explicit business rules).
  ///
  /// Only THIS stop changes. stopId / itineraryId / dayIndex / stopOrder
  /// / status / times / duration are preserved. No other stop is ever
  /// read as a restriction, moved, or written.
  Future<bool> changePlace(Place newPlace) async {
    debugPrint('[EDIT_STOP_LOCATION] Starting location change');
    debugPrint('[EDIT_STOP_LOCATION] Stop ID: ${_stop.stopId}');
    debugPrint('[EDIT_STOP_LOCATION] Old place ID: ${_stop.placeId}');
    final oldPlace = _stop.place;
    if (oldPlace != null) {
      debugPrint('[EDIT_STOP_LOCATION] Old place name: ${oldPlace.placeName}');
    }
    debugPrint('[EDIT_STOP_LOCATION] New place ID: ${newPlace.placeId}');
    debugPrint('[EDIT_STOP_LOCATION] New place name: ${newPlace.placeName}');
    debugPrint('[EDIT_STOP_LOCATION] New coordinates: '
        '${newPlace.placeLatitude}, ${newPlace.placeLongitude}');

    if (!isEditable) {
      _error = _buildLockedMessage();
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - stop not editable '
          '(${_buildLockedMessage()})');
      notifyListeners();
      return false;
    }
    // A usable canonical database Place: identity, name and real
    // coordinates are required (basic data validity, NOT route validity).
    if (newPlace.placeId.trim().isEmpty ||
        newPlace.placeName.trim().isEmpty ||
        (newPlace.placeLatitude == 0 && newPlace.placeLongitude == 0)) {
      _error = 'This place does not have enough information to be used in '
          'the itinerary.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - invalid place '
          'record (missing id/name/coordinates)');
      notifyListeners();
      return false;
    }
    if (newPlace.placeId.trim() == _stop.placeId.trim()) {
      debugPrint('[EDIT_STOP_VALIDATION] Result: SKIPPED - same place as '
          'current stop');
      _error = null;
      return true;
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = _buildUpdatedStop(
        placeId: newPlace.placeId,
        place: newPlace,
      );

      final dayStops = await _loadDayStops();
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == _stop.stopId) updated else s,
      ];

      final itinerary = await _loadItinerary();
      final index = resulting.indexWhere((s) => s.stopId == _stop.stopId);

      // Customization mode: the validator enforces only genuine data /
      // business rules — completed-stop protection, duplicate place_id,
      // valid coordinates, operating hours on the itinerary day. Route
      // distance, travel time, route feasibility, inter-stop overlap and
      // the daily exploration window are NEVER rejection reasons.
      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        candidatePlace: newPlace,
        travelPace: itinerary.travelPace,
        customizationMode: true,
      );

      if (!result.isValid) {
        _error = result.issues.first.message;
        debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - '
            '${result.issues.first.code}: ${result.issues.first.message}');
        notifyListeners();
        return false;
      }
      debugPrint('[EDIT_STOP_VALIDATION] Result: VALID');

      // Recalculate THIS stop's inbound travel time (previous → new).
      // Informational + displayed; never a rejection reason.
      var toSave = updated;
      if (index > 0) {
        final prev = resulting[index - 1];
        final prevPlace = prev.place;
        if (prevPlace != null) {
          final distanceKm =
          prevPlace.coordinates.distanceTo(newPlace.coordinates);
          debugPrint('[EDIT_STOP_ROUTE_INFO] Previous → New Place distance: '
              '${distanceKm.toStringAsFixed(1)} km');
          final routed = await _validator.travelMinutesBetween(
            prevPlace.coordinates,
            newPlace.coordinates,
            itinerary.transportationMode,
          );
          debugPrint('[EDIT_STOP_ROUTE_INFO] Previous → New Place travel '
              'time: ${routed ?? 'unknown'} minutes');
          debugPrint('[EDIT_STOP_ROUTE_INFO] Travel time is INFORMATION '
              'ONLY; it will NOT block location customization.');
          if (routed != null) {
            toSave = toSave.copyWith(travelFromPrevMinutes: routed);
          }
        }
      } else {
        toSave = toSave.copyWith(travelFromPrevMinutes: 0);
        debugPrint('[EDIT_STOP_ROUTE_INFO] First stop - no previous place; '
            'travelFromPrevMinutes set to 0 (information only)');
      }

      // ONLY this stop is written. The next stop is never modified.
      debugPrint('[EDIT_STOP_SAVE] Saving edited stop');
      debugPrint('[EDIT_STOP_SAVE] Stop ID: ${toSave.stopId}');
      debugPrint('[EDIT_STOP_SAVE] Place ID: ${toSave.placeId}');
      debugPrint('[EDIT_STOP_SAVE] Start: ${_fmt(toSave.startTime)}');
      debugPrint('[EDIT_STOP_SAVE] End: ${_fmt(toSave.endTime)}');
      debugPrint('[EDIT_STOP_SAVE] Duration: ${toSave.durationMinutes}');
      debugPrint('[EDIT_STOP_SAVE] Travel from previous: '
          '${toSave.travelFromPrevMinutes} minutes');
      final saved = await _repo.updateStop(toSave);
      debugPrint('[EDIT_STOP_SAVE] Save successful');

      _stop = saved.copyWith(place: newPlace);
      _dayStopsWithPlaces = null;
      _error = null;
      await refreshTimeOptions();
      notifyListeners();
      debugPrint('[EDIT_STOP] Location changed to ${newPlace.placeName} '
          '(${newPlace.placeId})');
      return true;
    } catch (e) {
      _error = 'Unable to update the place. Please try again.';
      debugPrint('[EDIT_STOP_SAVE] Save failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Previous stop → [newPlace] distance / travel time for the
  /// change-location confirmation dialog. INFORMATION ONLY — nothing
  /// here can or should block the traveler's customization.
  /// Returns `null` when there is no previous stop or places are
  /// unavailable (first stop / missing data).
  Future<({double distanceKm, int? travelMinutes})?> travelInfoToPlace(
      Place newPlace,
      ) async {
    try {
      final dayStops = await _loadDayStops();
      final idx = dayStops.indexWhere((s) => s.stopId == _stop.stopId);
      if (idx <= 0) return null;
      final prevPlace = dayStops[idx - 1].place;
      if (prevPlace == null) return null;
      final itinerary = await _loadItinerary();
      final distanceKm =
      prevPlace.coordinates.distanceTo(newPlace.coordinates);
      final travelMinutes = await _validator.travelMinutesBetween(
        prevPlace.coordinates,
        newPlace.coordinates,
        itinerary.transportationMode,
      );
      debugPrint('[EDIT_STOP_ROUTE_INFO] Previous → New Place distance: '
          '${distanceKm.toStringAsFixed(1)} km');
      debugPrint('[EDIT_STOP_ROUTE_INFO] Previous → New Place travel time: '
          '${travelMinutes ?? 'unknown'} minutes');
      debugPrint('[EDIT_STOP_ROUTE_INFO] Travel time is INFORMATION ONLY; '
          'it will NOT block location customization.');
      return (distanceKm: distanceKm, travelMinutes: travelMinutes);
    } catch (e) {
      debugPrint('[EDIT_STOP_ROUTE_INFO] Travel info unavailable: $e');
      return null;
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
  /// them. No arrangement, no normalization back to the generated
  /// schedule, no exploration-window / travel / neighbor validation.
  /// Basic data checks only (end after start, duration > 0, internally
  /// consistent); overlaps with other stops are logged informationally
  /// and are ALLOWED — no other stop is ever moved.
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

    // Basic data validity of the pending triple (never schedule/route).
    if (!_editedEndTime.isAfter(_editedStartTime)) {
      _error = 'End time must be after start time.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - end must be '
          'after start');
      notifyListeners();
      return false;
    }
    final consistentDuration =
        _editedEndTime.difference(_editedStartTime).inMinutes;
    if (consistentDuration <= 0 ||
        _editedDurationMinutes != consistentDuration) {
      _error =
      'The selected times are inconsistent. Please choose a valid start '
          'and end time.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - duration '
          'inconsistent with times ($_editedDurationMinutes vs '
          '$consistentDuration)');
      notifyListeners();
      return false;
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final itinerary = await _loadItinerary();
      final dayStops = await _loadDayStops();
      final updated = _buildUpdatedStop(
        startTime: _editedStartTime,
        endTime: _editedEndTime,
        durationMinutes: _editedDurationMinutes,
      );
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == _stop.stopId) updated else s,
      ];

      debugPrint('[EDIT_STOP_TIME] Conflict Check (information only)');
      _logOverlapInfo(resulting);

      // The validator remains the final authority for BASIC DATA
      // consistency only. Customization mode means: no route validation,
      // no travel-time validation, no inter-stop schedule validation, no
      // daily exploration-window rejection, no schedule optimization.
      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        travelPace: itinerary.travelPace,
        customizationMode: true,
      );

      if (!result.isValid) {
        _error = result.issues.first.message;
        debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - basic data '
            'inconsistency: ${result.issues.first.code}: '
            '${result.issues.first.message}');
        notifyListeners();
        return false;
      }
      debugPrint('[EDIT_STOP_VALIDATION] Result: VALID');
      debugPrint('[EDIT_STOP_VALIDATION] Traveler-selected time accepted');
      debugPrint('[EDIT_STOP_TIME] Final Scheduled Time: '
          '${_fmt(updated.startTime)} - ${_fmt(updated.endTime)}');

      debugPrint('[EDIT_STOP_SAVE] Saving edited stop');
      debugPrint('[EDIT_STOP_SAVE] stopId=${updated.stopId}');
      debugPrint('[EDIT_STOP_SAVE] start=${_fmt(updated.startTime)}');
      debugPrint('[EDIT_STOP_SAVE] end=${_fmt(updated.endTime)}');
      debugPrint('[EDIT_STOP_SAVE] duration=${updated.durationMinutes}');
      debugPrint('[EDIT_STOP_SAVE] schedule constraints=IGNORED');
      debugPrint('[EDIT_STOP_SAVE] Travel from previous: '
          '${updated.travelFromPrevMinutes} minutes (unchanged)');
      debugPrint('[EDIT_STOP_SAVE] Status: ${updated.stopStatus}');

      // ONLY this stop is written. No neighbor stop is touched.
      final saved = await _repo.updateStop(updated);
      debugPrint('[EDIT_STOP_SAVE] Save successful');

      _stop = saved.copyWith(place: _stop.place);
      _editedStartTime = _stop.startTime;
      _editedEndTime = _stop.endTime;
      _editedDurationMinutes = _stop.durationMinutes;
      _dayStopsWithPlaces = null;
      _error = null;
      await _refreshTimeOptions(itinerary, dayStops);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Unable to update the stop. Please try again.';
      debugPrint('[EDIT_STOP_SAVE] Save failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Informational schedule context for the pending edit: neighbors,
  /// overlaps and route data. LOGGING ONLY — in customization mode an
  /// overlap NEVER rejects the change, NEVER alters the selected time and
  /// NEVER moves another stop.
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
      _logTravelInfo(dayStops);
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

  /// Logs the stop's route context from ALREADY PERSISTED data
  /// (distance + stored travel time). Purely informational — no network
  /// call, no validation, never blocks anything.
  void _logTravelInfo(List<ItineraryStop> dayStops) {
    final sorted = List<ItineraryStop>.from(dayStops)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    final idx = sorted.indexWhere((s) => s.stopId == _stop.stopId);
    if (idx <= 0) return;
    final prev = sorted[idx - 1];
    final prevPlace = prev.place;
    final curPlace = _stop.place;
    if (prevPlace == null || curPlace == null) return;
    final distanceKm = prevPlace.coordinates.distanceTo(curPlace.coordinates);
    final travelMinutes = _stop.travelFromPrevMinutes ?? 0;
    debugPrint('[EDIT_STOP_ROUTE_INFO] Previous stop ID: ${prev.stopId}');
    debugPrint('[EDIT_STOP_ROUTE_INFO] Current stop ID: ${_stop.stopId}');
    debugPrint('[EDIT_STOP_ROUTE_INFO] Travel information only. '
        'Distance=${distanceKm.toStringAsFixed(1)}km, '
        'TravelTime=${travelMinutes}min. '
        'Route feasibility will NOT block traveler customization.');
  }

  void resetTimeEdits() {
    _editedStartTime = _stop.startTime;
    _editedEndTime = _stop.endTime;
    _editedDurationMinutes = _stop.durationMinutes;
    _error = null;
    notifyListeners();
  }

  // ✅ ADD THIS: Calculate the exact end time of the stop
  DateTime get scheduledEndDateTime {
    final dayDate = _itineraryStartDate.add(Duration(days: _stop.dayIndex - 1));
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      _stop.endTime.hour,
      _stop.endTime.minute,
      _stop.endTime.second,
    );
  }

  // ✅ ADD THIS: Check if the current time is past the stop's end time
  bool get isTimeOver {
    return DateTime.now().isAfter(scheduledEndDateTime);
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
    } else if (isTimeOver) { // ✅ ADD THIS CONDITION
      return 'The scheduled time for this stop has passed. You can no longer change its location or schedule, but you can still update its status.';
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