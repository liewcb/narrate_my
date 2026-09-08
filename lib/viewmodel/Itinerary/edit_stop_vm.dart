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
/// Edit Stop is TRAVELER TIME CONTROL — the traveler decides the times,
/// the program only manages schedule conflicts. Route feasibility,
/// distance, travel time, pace and optimization NEVER reject a
/// customization; they are computed for display/persistence only.
/// Time, duration and location edits are checked for BASIC validity only
/// (start < end, duration > 0 within the existing min/max constants,
/// the absolute daily schedule window, a valid canonical Place, the
/// place's operating hours and day-level duplicate protection).
/// If a traveler-selected time overlaps another stop, the program
/// ARRANGES the other (planned) stops around it — preserving each of
/// their durations, locations, statuses and order — so the final day
/// contains no time conflicts while the traveler's choice survives.
/// [ItineraryValidator] enforces the basic rules in customization mode;
/// full generation-time validation remains intact for every other
/// module.
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

  // ── Available (valid) dropdown options ───────────────────────
  List<DateTime> _availableStartTimes = [];
  List<DateTime> _availableEndTimes = [];
  List<int> _availableDurations = [];

  /// Predefined practical visit durations (minutes).
  static const List<int> predefinedDurations = [
    15, 30, 45, 60, 75, 90, 105, 120, 150, 180, 240,
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

      // Customization mode: the validator keeps enforcing basic place /
      // time / daily-window rules but travel distance, travel time, route
      // availability and inter-stop overlap are INFORMATION ONLY and can
      // never reject this edit.
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

  /// Set a new temporary START time (traveler decision).
  ///
  /// The traveler owns the time; previous/next stop distance, travel
  /// duration, route efficiency, traffic and pace NEVER reject it. The
  /// only limits are basic validity (duration > 0, start < end) and the
  /// existing absolute daily schedule window. If the choice creates an
  /// overlap, the OTHER stops get arranged around it on save — this
  /// pending value is preserved.
  Future<bool> setStartTime(DateTime newStart) async {
    final candidate = _combineWithDay(newStart);
    final startMin = _minutesSinceMidnight(candidate);
    final duration = _editedDurationMinutes;

    debugPrint('[EDIT_STOP_TIME] Old Start Time: ${_fmt(_editedStartTime)}');
    debugPrint('[EDIT_STOP_TIME] Traveler Selected Start Time: '
        '${_fmt(candidate)}');
    debugPrint('[EDIT_STOP_TIME] Current End Time: ${_fmt(_editedEndTime)}');
    debugPrint('[EDIT_STOP_TIME] Duration: $duration');
    debugPrint('[EDIT_STOP_TIME] Travel constraints intentionally ignored');

    if (!isEditable) {
      _error = _buildLockedMessage();
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - stop not '
          'editable (${_buildLockedMessage()})');
      notifyListeners();
      return false;
    }

    if (duration <= 0) {
      _error = 'The selected start time is invalid.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - duration must '
          'be greater than 0');
      notifyListeners();
      return false;
    }

    try {
      final itinerary = await _loadItinerary();
      final window = ItineraryConstants.explorationWindowFor(
        itinerary.explorationTime,
      );

      // Absolute daily boundary (existing application rule).
      if (startMin < window.startMinutes) {
        _error = "The start time must be within the day's available time "
            '($window).';
        debugPrint('[EDIT_STOP_TIME] REJECTED: start before the daily '
            'window start');
        notifyListeners();
        return false;
      }
      if (startMin + duration > window.endMinutes) {
        _error = "This stop must finish within the day's available time.";
        debugPrint('[EDIT_STOP_TIME] REJECTED: start + duration past the '
            'daily window end');
        notifyListeners();
        return false;
      }

      final newEnd = candidate.add(Duration(minutes: duration));
      final dayStops = await _loadDayStops();
      final updated = _buildUpdatedStop(
        startTime: candidate,
        endTime: newEnd,
        durationMinutes: duration,
      );
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == _stop.stopId) updated else s,
      ];

      // The validator remains the final authority for BASIC validity
      // (time ordering, duration consistency, daily window). Route /
      // travel / overlap checks are skipped in customization mode.
      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: window,
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        travelPace: itinerary.travelPace,
        customizationMode: true,
      );

      if (!result.isValid) {
        // Reject ONLY the requested change. The last accepted (possibly
        // already customized) pending values stay untouched — the
        // original generated schedule is never force-restored.
        _error = result.issues.first.message;
        debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - '
            '${result.issues.first.code}: ${result.issues.first.message}');
        notifyListeners();
        return false;
      }

      debugPrint('[EDIT_STOP_TIME] Conflict Check');
      final conflictPreview = _findRemainingConflict(resulting);
      if (conflictPreview != null) {
        debugPrint('[EDIT_STOP_VALIDATION] Time conflict detected');
        debugPrint('[EDIT_STOP_VALIDATION] Affected stop ID: '
            '${conflictPreview.stopId}');
        debugPrint('[EDIT_STOP_VALIDATION] Conflict with stop ID: '
            '${_stop.stopId}');
        debugPrint('[EDIT_STOP_VALIDATION] Arranging schedule to remove '
            'conflict when saving (traveler time kept as anchor)');
      } else {
        debugPrint('[EDIT_STOP_VALIDATION] No schedule conflict detected');
        debugPrint('[EDIT_STOP_VALIDATION] Traveler-selected time accepted');
      }
      _logTravelInfo(resulting);

      _editedStartTime = candidate;
      _editedEndTime = newEnd;
      _error = null;
      debugPrint('[EDIT_STOP_TIME] Start time accepted '
          '(${_fmt(candidate)} - ${_fmt(newEnd)})');
      await _refreshTimeOptions(itinerary, dayStops);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[EditStopVM] Time validation failed: $e');
      _error = 'Unable to validate the new start time. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Set a new temporary END time. The duration is recalculated
  /// as `end - start`.
  ///
  /// Traveler customization: the next stop, the route and travel times
  /// do NOT restrict the end time. Only basic rules apply: end > start,
  /// the existing minimum/maximum visit duration constants, and the
  /// absolute daily schedule window (no midnight crossing).
  Future<bool> setEndTime(DateTime newEnd) async {
    final candidate = _combineWithDay(newEnd);
    final startMin = _minutesSinceMidnight(_editedStartTime);
    final endMin = _minutesSinceMidnight(candidate);

    debugPrint('[EDIT_STOP_TIME] Old End Time: ${_fmt(_editedEndTime)}');
    debugPrint('[EDIT_STOP_TIME] Traveler Selected End Time: '
        '${_fmt(candidate)}');
    debugPrint('[EDIT_STOP_TIME] Current Start Time: '
        '${_fmt(_editedStartTime)}');
    debugPrint('[EDIT_STOP_TIME] Duration: ${endMin - startMin}');
    debugPrint('[EDIT_STOP_TIME] Travel constraints intentionally ignored');

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
    if (newDuration < ItineraryConstants.minimumVisitDurationMinutes) {
      _error = 'Visit duration must be at least '
          '${ItineraryConstants.minimumVisitDurationMinutes} minutes.';
      debugPrint('[EDIT_STOP_TIME] REJECTED: duration below the existing '
          'minimum visit duration');
      notifyListeners();
      return false;
    }
    if (newDuration > ItineraryConstants.maximumVisitDurationMinutes) {
      _error = 'Visit duration cannot exceed '
          '${ItineraryConstants.maximumVisitDurationMinutes} minutes.';
      debugPrint('[EDIT_STOP_TIME] REJECTED: duration above the existing '
          'maximum visit duration');
      notifyListeners();
      return false;
    }

    try {
      final itinerary = await _loadItinerary();
      final window = ItineraryConstants.explorationWindowFor(
        itinerary.explorationTime,
      );

      // Absolute daily boundary only — NOT the next stop.
      if (endMin > window.endMinutes) {
        _error = "This stop must finish within the day's available time.";
        debugPrint('[EDIT_STOP_TIME] REJECTED: end past the daily window '
            'end');
        notifyListeners();
        return false;
      }

      final dayStops = await _loadDayStops();
      final updated = _buildUpdatedStop(
        startTime: _editedStartTime,
        endTime: candidate,
        durationMinutes: newDuration,
      );
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == _stop.stopId) updated else s,
      ];

      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: window,
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        travelPace: itinerary.travelPace,
        customizationMode: true,
      );

      if (!result.isValid) {
        // Reject ONLY the requested change — previously accepted
        // customizations of the pending edit are preserved.
        _error = result.issues.first.message;
        debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - '
            '${result.issues.first.code}: ${result.issues.first.message}');
        notifyListeners();
        return false;
      }

      debugPrint('[EDIT_STOP_TIME] Conflict Check');
      final conflictPreview = _findRemainingConflict(resulting);
      if (conflictPreview != null) {
        debugPrint('[EDIT_STOP_VALIDATION] Time conflict detected');
        debugPrint('[EDIT_STOP_VALIDATION] Affected stop ID: '
            '${conflictPreview.stopId}');
        debugPrint('[EDIT_STOP_VALIDATION] Conflict with stop ID: '
            '${_stop.stopId}');
        debugPrint('[EDIT_STOP_VALIDATION] Arranging schedule to remove '
            'conflict when saving (traveler time kept as anchor)');
      } else {
        debugPrint('[EDIT_STOP_VALIDATION] No schedule conflict detected');
        debugPrint('[EDIT_STOP_VALIDATION] Traveler-selected time accepted');
      }
      _logTravelInfo(resulting);

      _editedEndTime = candidate;
      _editedDurationMinutes = newDuration;
      _error = null;
      debugPrint('[EDIT_STOP_TIME] End time accepted '
          '(${_fmt(_editedStartTime)} - ${_fmt(candidate)}, '
          '$newDuration minutes)');
      await _refreshTimeOptions(itinerary, dayStops);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[EditStopVM] End validation failed: $e');
      _error = 'Unable to validate the new end time. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Set a new temporary DURATION. The end time is recalculated as
  /// `start + duration`.
  ///
  /// Traveler customization: `places.visit_duration_minutes` and the
  /// original generated duration are REFERENCE ONLY and never forced;
  /// the next stop and travel times never restrict the duration. Only
  /// basic rules apply: duration > 0, the existing min/max duration
  /// constants and the absolute daily window. If the longer/shorter
  /// visit overlaps a neighbour, the other stops are arranged around
  /// the traveler's choice on save — never the reverse.
  Future<bool> setDuration(int newDurationMinutes) async {
    debugPrint('[EDIT_STOP_DURATION] Old duration: $_editedDurationMinutes');
    debugPrint('[EDIT_STOP_DURATION] New duration: $newDurationMinutes');
    debugPrint('[EDIT_STOP_DURATION] Start: ${_fmt(_editedStartTime)}');
    debugPrint('[EDIT_STOP_DURATION] Calculated end: '
        '${_fmt(_editedStartTime.add(Duration(minutes: newDurationMinutes)))}');
    debugPrint('[EDIT_STOP_DURATION] Travel constraints intentionally '
        'ignored');

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
    if (newDurationMinutes < ItineraryConstants.minimumVisitDurationMinutes) {
      _error = 'Visit duration must be at least '
          '${ItineraryConstants.minimumVisitDurationMinutes} minutes.';
      debugPrint('[EDIT_STOP_DURATION] REJECTED: below the existing '
          'minimum visit duration');
      notifyListeners();
      return false;
    }
    if (newDurationMinutes > ItineraryConstants.maximumVisitDurationMinutes) {
      _error = 'Visit duration cannot exceed '
          '${ItineraryConstants.maximumVisitDurationMinutes} minutes.';
      debugPrint('[EDIT_STOP_DURATION] REJECTED: above the existing '
          'maximum visit duration');
      notifyListeners();
      return false;
    }
    if (newDurationMinutes == _editedDurationMinutes) {
      _error = null;
      return true;
    }

    try {
      final itinerary = await _loadItinerary();
      final window = ItineraryConstants.explorationWindowFor(
        itinerary.explorationTime,
      );
      final startMin = _minutesSinceMidnight(_editedStartTime);

      // Absolute daily boundary only — never the next stop / route.
      if (startMin + newDurationMinutes > window.endMinutes) {
        _error = "This stop must finish within the day's available time.";
        debugPrint('[EDIT_STOP_DURATION] REJECTED: start + duration past '
            'the daily window end');
        notifyListeners();
        return false;
      }

      final dayStops = await _loadDayStops();
      final candidateEnd =
      _editedStartTime.add(Duration(minutes: newDurationMinutes));
      final updated = _buildUpdatedStop(
        startTime: _editedStartTime,
        endTime: candidateEnd,
        durationMinutes: newDurationMinutes,
      );
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == _stop.stopId) updated else s,
      ];

      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: window,
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
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

      debugPrint('[EDIT_STOP_TIME] Conflict Check');
      final conflictPreview = _findRemainingConflict(resulting);
      if (conflictPreview != null) {
        debugPrint('[EDIT_STOP_VALIDATION] Time conflict detected');
        debugPrint('[EDIT_STOP_VALIDATION] Affected stop ID: '
            '${conflictPreview.stopId}');
        debugPrint('[EDIT_STOP_VALIDATION] Conflict with stop ID: '
            '${_stop.stopId}');
        debugPrint('[EDIT_STOP_VALIDATION] Arranging schedule to remove '
            'conflict when saving (traveler time kept as anchor)');
      } else {
        debugPrint('[EDIT_STOP_VALIDATION] No schedule conflict detected');
        debugPrint('[EDIT_STOP_VALIDATION] Traveler-selected time accepted');
      }
      _logTravelInfo(resulting);

      _editedDurationMinutes = newDurationMinutes;
      _editedEndTime = candidateEnd;
      _error = null;
      debugPrint('[EDIT_STOP_DURATION] Duration accepted '
          '(${_fmt(_editedStartTime)} - ${_fmt(candidateEnd)})');
      await _refreshTimeOptions(itinerary, dayStops);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[EditStopVM] Duration validation failed: $e');
      _error = 'Unable to validate the new duration. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Persist the pending time changes.
  ///
  /// THE TRAVELER'S TIME IS THE ANCHOR: it is saved exactly as selected.
  /// Schedule-conflict management then shifts the OTHER planned stops in
  /// time (their durations, locations, statuses and order stay untouched)
  /// only as far as needed to remove overlaps. COMPLETED/SKIPPED stops and
  /// the absolute daily window are hard boundaries — if no conflict-free
  /// arrangement exists without touching them, nothing is persisted and
  /// the traveler is told why.
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

    // Basic validity only (never travel/route): end > start and a
    // duration consistent with the pending times.
    final pendingStartMin = _minutesSinceMidnight(_editedStartTime);
    final pendingEndMin = _minutesSinceMidnight(_editedEndTime);
    if (pendingEndMin <= pendingStartMin ||
        _editedDurationMinutes != pendingEndMin - pendingStartMin) {
      _error =
          'The selected times are inconsistent. Please choose a valid start '
          'and end time.';
      debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - invalid time '
          'ordering or duration inconsistency '
          '($pendingStartMin -> $pendingEndMin, '
          '$_editedDurationMinutes min)');
      notifyListeners();
      return false;
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
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

      final itinerary = await _loadItinerary();
      final window = ItineraryConstants.explorationWindowFor(
        itinerary.explorationTime,
      );

      debugPrint('[EDIT_STOP_TIME] Conflict Check');
      final moved = <ItineraryStop>[];
      final arranged = _arrangeDayAroundEdited(
        dayStops: resulting,
        window: window,
        movedOut: moved,
      );

      final residual = _findRemainingConflict(arranged);
      if (residual != null) {
        _error = 'That time cannot be scheduled without moving a completed '
            "stop or exceeding the day's available time. Please choose a "
            'different time.';
        debugPrint('[EDIT_STOP_VALIDATION] Result: REJECTED - no conflict-'
            'free arrangement exists (overlap at stop ${residual.stopId}); '
            'nothing was persisted');
        notifyListeners();
        return false;
      }
      debugPrint('[EDIT_STOP_VALIDATION] No schedule conflict detected '
          '(final arranged day is overlap-free)');

      final anchored = arranged.firstWhere(
        (s) => s.stopId == _stop.stopId,
        orElse: () => updated,
      );

      // The validator remains the final basic-validity authority over the
      // ARRANGED day (time ordering, duration consistency, daily window).
      // Travel/route checks stay skipped — customization mode.
      final result = await _validator.validateResultingDay(
        dayStops: arranged,
        dayDate: _dayDate(itinerary),
        window: window,
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
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
      debugPrint('[EDIT_STOP_VALIDATION] Traveler-selected time accepted');
      debugPrint('[EDIT_STOP_TIME] Final Scheduled Time: '
          '${_fmt(anchored.startTime)} - ${_fmt(anchored.endTime)}');

      debugPrint('[EDIT_STOP_SAVE] Saving edited stop');
      debugPrint('[EDIT_STOP_SAVE] Stop ID: ${anchored.stopId}');
      debugPrint('[EDIT_STOP_SAVE] Place ID: ${anchored.placeId}');
      debugPrint('[EDIT_STOP_SAVE] Start: ${_fmt(anchored.startTime)}');
      debugPrint('[EDIT_STOP_SAVE] End: ${_fmt(anchored.endTime)}');
      debugPrint('[EDIT_STOP_SAVE] Duration: ${anchored.durationMinutes}');
      debugPrint('[EDIT_STOP_SAVE] Travel from previous: '
          '${anchored.travelFromPrevMinutes} minutes');
      debugPrint('[EDIT_STOP_SAVE] Status: ${anchored.stopStatus}');

      final saved = await _repo.updateStop(anchored);
      debugPrint('[EDIT_STOP_SAVE] Save successful');

      // Persist the arranged neighbors (times only — duration, place,
      // status, order preserved by construction).
      for (final shifted in moved) {
        try {
          await _repo.updateStop(shifted);
          debugPrint('[EDIT_STOP_SAVE] Conflict arrangement: stop '
              '${shifted.stopId} moved to ${_fmt(shifted.startTime)} - '
              '${_fmt(shifted.endTime)} (duration '
              '${shifted.durationMinutes} min preserved)');
        } catch (e) {
          debugPrint('[EDIT_STOP_SAVE] Failed to persist shifted stop '
              '${shifted.stopId}: $e');
        }
      }

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

  /// SCHEDULE CONFLICT MANAGEMENT (not route optimization).
  ///
  /// The edited stop's traveler-chosen times are the ANCHOR and are kept
  /// as-is. Only PLANNED neighbours are shifted in time — never reordered,
  /// deleted, relocated or re-durationed — just enough to remove overlaps:
  ///  • following stops are pushed later (start = previous end),
  ///  • preceding stops are pulled earlier (end = next start),
  /// bounded by the absolute daily window. COMPLETED/SKIPPED stops are
  /// immutable history: if one blocks a conflict-free arrangement, the
  /// residual overlap is detected afterwards and the save is rejected
  /// (the only remaining hard-boundary rejection).
  List<ItineraryStop> _arrangeDayAroundEdited({
    required List<ItineraryStop> dayStops,
    required ExplorationWindow window,
    required List<ItineraryStop> movedOut,
  }) {
    final arranged = List<ItineraryStop>.from(dayStops)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    final idx = arranged.indexWhere((s) => s.stopId == _stop.stopId);
    if (idx < 0) return arranged;

    // ── Backward pass: pull earlier PLANNED stops before the anchor ──
    var anchorStart = _minutesSinceMidnight(arranged[idx].startTime);
    var cursorStart = anchorStart;
    for (var j = idx - 1; j >= 0; j--) {
      final stop = arranged[j];
      final endMin = _minutesSinceMidnight(stop.endTime);
      if (endMin <= cursorStart) break; // no (further) overlap
      debugPrint('[EDIT_STOP_VALIDATION] Time conflict detected');
      debugPrint('[EDIT_STOP_VALIDATION] Affected stop ID: ${stop.stopId}');
      debugPrint('[EDIT_STOP_VALIDATION] Conflict with stop ID: '
          '${_stop.stopId}');
      if (stop.stopStatus != planned) {
        // Immutable stop cannot move → the anchor is clamped after it
        // (last resort; traveler time preserved as far as possible).
        cursorStart = endMin;
        debugPrint('[EDIT_STOP_VALIDATION] Stop ${stop.stopId} is '
            '${stop.stopStatus} (immutable) — clamping the anchor after it');
        break;
      }
      debugPrint('[EDIT_STOP_VALIDATION] Arranging schedule to remove '
          'conflict');
      var newStart = cursorStart - stop.durationMinutes;
      if (newStart < window.startMinutes) {
        newStart = window.startMinutes; // absolute daily boundary
      }
      final newEnd = newStart + stop.durationMinutes;
      final shifted = _copyStopWithTimes(stop, newStart, newEnd);
      arranged[j] = shifted;
      movedOut.add(shifted);
      cursorStart = newStart;
    }
    if (cursorStart > anchorStart) {
      final clamped = _copyStopWithTimes(
        arranged[idx],
        cursorStart,
        cursorStart + arranged[idx].durationMinutes,
      );
      arranged[idx] = clamped;
    }

    // ── Forward pass: push later PLANNED stops after the anchor ──────
    var prevEnd = _minutesSinceMidnight(arranged[idx].endTime);
    for (var j = idx + 1; j < arranged.length; j++) {
      final stop = arranged[j];
      final startMin = _minutesSinceMidnight(stop.startTime);
      if (startMin >= prevEnd) break; // no (further) overlap
      debugPrint('[EDIT_STOP_VALIDATION] Time conflict detected');
      debugPrint('[EDIT_STOP_VALIDATION] Affected stop ID: ${stop.stopId}');
      debugPrint('[EDIT_STOP_VALIDATION] Conflict with stop ID: '
          '${_stop.stopId}');
      if (stop.stopStatus != planned) {
        debugPrint('[EDIT_STOP_VALIDATION] Stop ${stop.stopId} is '
            '${stop.stopStatus} (immutable) — cannot be shifted');
        prevEnd = _minutesSinceMidnight(stop.endTime);
        continue;
      }
      debugPrint('[EDIT_STOP_VALIDATION] Arranging schedule to remove '
          'conflict');
      final newEnd = prevEnd + stop.durationMinutes;
      if (newEnd > window.endMinutes) {
        // Would cross the absolute daily boundary — leave the conflict
        // in place so the residual check rejects the save.
        debugPrint('[EDIT_STOP_VALIDATION] Stop ${stop.stopId} cannot be '
            'shifted past the day window end ($window)');
        break;
      }
      final shifted = _copyStopWithTimes(stop, prevEnd, newEnd);
      arranged[j] = shifted;
      movedOut.add(shifted);
      prevEnd = newEnd;
    }
    return arranged;
  }

  /// First stop whose START is before the previous stop's END
  /// (pure time overlap — travel time is NOT part of a conflict).
  ItineraryStop? _findRemainingConflict(List<ItineraryStop> dayStops) {
    final sorted = List<ItineraryStop>.from(dayStops)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    for (var j = 1; j < sorted.length; j++) {
      if (_minutesSinceMidnight(sorted[j].startTime) <
          _minutesSinceMidnight(sorted[j - 1].endTime)) {
        return sorted[j];
      }
    }
    return null;
  }

  /// Copy of [s] with new times only — duration, place, identity, status
  /// and order preserved.
  ItineraryStop _copyStopWithTimes(ItineraryStop s, int startMin, int endMin) {
    return ItineraryStop(
      stopId: s.stopId,
      itineraryId: s.itineraryId,
      placeId: s.placeId,
      destinationId: s.destinationId,
      dayIndex: s.dayIndex,
      stopOrder: s.stopOrder,
      startTime: _atMinutes(startMin),
      endTime: _atMinutes(endMin),
      durationMinutes: endMin - startMin,
      travelFromPrevMinutes: s.travelFromPrevMinutes,
      stopStatus: s.stopStatus,
      skipReason: s.skipReason,
      weatherNote: s.weatherNote,
      place: s.place,
      createdAt: s.createdAt,
      updatedAt: DateTime.now(),
    );
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

  /// Rebuilds the dropdown options.
  ///
  /// Options are bounded ONLY by the existing absolute rules: the daily
  /// exploration window and the min/max visit duration. Previous-stop,
  /// next-stop and travel-time filtering is intentionally NOT applied —
  /// travel information must never restrict customization.
  Future<void> _refreshTimeOptions(
      Itinerary itinerary,
      List<ItineraryStop> dayStops,
      ) async {
    final window = ItineraryConstants.explorationWindowFor(
      itinerary.explorationTime,
    );

    final duration = _editedDurationMinutes;

    // ── Start times: every step slot in the daily window whose
    //    end (start + duration) also stays inside the window ────────
    final startSlots = <DateTime>[];
    for (int minutes = window.startMinutes;
    minutes + duration <= window.endMinutes;
    minutes += startTimeStepMinutes) {
      startSlots.add(_atMinutes(minutes));
    }

    // Keep an off-grid current selection visible (it passed validation).
    final currentStartMin = _minutesSinceMidnight(_editedStartTime);
    if (currentStartMin >= window.startMinutes &&
        currentStartMin + duration <= window.endMinutes &&
        !startSlots.contains(_editedStartTime)) {
      startSlots.add(_editedStartTime);
      startSlots.sort((a, b) => a.compareTo(b));
    }
    _availableStartTimes = startSlots;

    // ── End times: after start, min/max visit duration, daily window ──
    final startMin = _minutesSinceMidnight(_editedStartTime);
    final earliestEnd =
        startMin + ItineraryConstants.minimumVisitDurationMinutes;
    var latestEnd = window.endMinutes;
    final maxDurationEnd =
        startMin + ItineraryConstants.maximumVisitDurationMinutes;
    if (maxDurationEnd < latestEnd) latestEnd = maxDurationEnd;

    final endSlots = <DateTime>[];
    for (int minutes = window.startMinutes;
    minutes <= window.endMinutes;
    minutes += endTimeStepMinutes) {
      if (minutes < earliestEnd) continue;
      if (minutes > latestEnd) continue;
      endSlots.add(_atMinutes(minutes));
    }

    final currentEndMin = _minutesSinceMidnight(_editedEndTime);
    if (currentEndMin >= earliestEnd &&
        currentEndMin <= latestEnd &&
        !endSlots.contains(_editedEndTime)) {
      endSlots.add(_editedEndTime);
      endSlots.sort((a, b) => a.compareTo(b));
    }
    _availableEndTimes = endSlots;

    // ── Durations: existing min/max constants + daily window only ──
    final durationSlots = <int>[];
    final minDur = ItineraryConstants.minimumVisitDurationMinutes;
    final maxDur = ItineraryConstants.maximumVisitDurationMinutes;

    for (final d in predefinedDurations) {
      if (d < minDur || d > maxDur) continue;
      if (startMin + d > window.endMinutes) continue;
      durationSlots.add(d);
    }

    if (!durationSlots.contains(_editedDurationMinutes)) {
      durationSlots.add(_editedDurationMinutes);
      durationSlots.sort();
    }
    _availableDurations = durationSlots;

    debugPrint('[EDIT_STOP] Time options refreshed: '
        '${startSlots.length} start / ${endSlots.length} end / '
        '${durationSlots.length} duration options '
        '(travel-based filtering intentionally NOT applied)');
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