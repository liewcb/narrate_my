// lib/viewmodel/Itinerary/edit_stop_vm.dart
import 'package:flutter/foundation.dart';

import '../../core/config/itinerary_constants.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/itinerary_validator.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/itinerary_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';

/// Traveler progress for a single itinerary stop.
///
/// The traveler may edit the stop's scheduled START TIME, END TIME,
/// the progress status, the LOCATION (place), or remove the stop entirely.
/// Place identity (stopId, itineraryId, dayIndex, stopOrder) is preserved
/// when the location changes — the same stop slot keeps its scheduling context.
///
/// Every edit is validated deterministically against the RESULTING itinerary
/// day via [ItineraryValidator] BEFORE anything is persisted. An invalid edit
/// never modifies the original itinerary and never reaches the database.
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

  Future<bool> changePlace(Place newPlace) async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }
    if (newPlace.placeId == _stop.placeId) {
      _error = null;
      return true;
    }
    if (_stop.stopStatus == completed) {
      _error = 'This stop has already been completed and cannot be modified.';
      notifyListeners();
      return false;
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
      final reroute = <int>{
        if (index > 0) index,
        if (index < resulting.length - 1) index + 1,
      };

      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        rerouteLegIndices: reroute,
        focusStop: _stop,
        candidatePlace: newPlace,
        travelPace: itinerary.travelPace,
      );

      if (!result.isValid) {
        _error = result.issues.first.message;
        notifyListeners();
        return false;
      }

      var toSave = updated;
      if (index > 0) {
        final prev = resulting[index - 1];
        final prevPlace = prev.place;
        if (prevPlace != null) {
          final routed = await _validator.travelMinutesBetween(
            prevPlace.coordinates,
            newPlace.coordinates,
            itinerary.transportationMode,
          );
          if (routed != null) {
            toSave = toSave.copyWith(travelFromPrevMinutes: routed);
          }
        }
      } else {
        toSave = toSave.copyWith(travelFromPrevMinutes: 0);
      }

      final saved = await _repo.updateStop(toSave);
      _stop = saved.copyWith(place: newPlace);
      _dayStopsWithPlaces = null;
      _error = null;
      await refreshTimeOptions();
      notifyListeners();
      debugPrint('[EDIT STOP] Location changed to ${newPlace.placeName} '
          '(${newPlace.placeId})');
      return true;
    } catch (e) {
      _error = 'Unable to update the place. Please try again.';
      debugPrint('[EditStopVM] Change place failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // ─── Time editing ───────────────────────────────────────────

  /// Set a new temporary START time. The end time is recalculated
  /// based on the current duration. Validates the resulting day.
  Future<bool> setStartTime(DateTime newStart) async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }

    final candidate = DateTime(
      _editedStartTime.year,
      _editedStartTime.month,
      _editedStartTime.day,
      newStart.hour,
      newStart.minute,
      newStart.second,
    );
    final newEnd = candidate.add(Duration(minutes: _editedDurationMinutes));

    if (!newEnd.isAfter(candidate)) {
      _error = 'The selected start time is invalid.';
      notifyListeners();
      return false;
    }

    debugPrint('[EDIT STOP] Start selected');
    debugPrint('[EDIT STOP] Original: ${_fmt(_stop.startTime)} - ${_fmt(_stop.endTime)}');
    debugPrint('[EDIT STOP] New: ${_fmt(candidate)} - ${_fmt(newEnd)}');
    debugPrint('[EDIT STOP] Duration: $_editedDurationMinutes minutes');

    try {
      final dayStops = await _loadDayStops();
      final updated = _buildUpdatedStop(
        startTime: candidate,
        endTime: newEnd,
        durationMinutes: _editedDurationMinutes,
      );
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == _stop.stopId) updated else s,
      ];

      final itinerary = await _loadItinerary();
      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        travelPace: itinerary.travelPace,
      );

      if (!result.isValid) {
        _editedStartTime = _stop.startTime;
        _editedEndTime = _stop.endTime;
        _error = result.issues.first.message;
        notifyListeners();
        return false;
      }

      _editedStartTime = candidate;
      _editedEndTime = newEnd;
      _error = null;
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
  /// as `end - start`. Validates the resulting day.
  Future<bool> setEndTime(DateTime newEnd) async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }

    final candidate = DateTime(
      _editedEndTime.year,
      _editedEndTime.month,
      _editedEndTime.day,
      newEnd.hour,
      newEnd.minute,
      newEnd.second,
    );

    if (!candidate.isAfter(_editedStartTime)) {
      _error = 'End time must be after start time.';
      notifyListeners();
      return false;
    }

    final newDuration = candidate.difference(_editedStartTime).inMinutes;
    if (newDuration < ItineraryConstants.minimumVisitDurationMinutes) {
      _error = 'Visit duration must be at least '
          '${ItineraryConstants.minimumVisitDurationMinutes} minutes.';
      notifyListeners();
      return false;
    }
    if (newDuration > ItineraryConstants.maximumVisitDurationMinutes) {
      _error = 'Visit duration cannot exceed '
          '${ItineraryConstants.maximumVisitDurationMinutes} minutes.';
      notifyListeners();
      return false;
    }

    debugPrint('[EDIT STOP] End selected');
    debugPrint('[EDIT STOP] Original: ${_fmt(_stop.startTime)} - ${_fmt(_stop.endTime)}');
    debugPrint('[EDIT STOP] New: ${_fmt(_editedStartTime)} - ${_fmt(candidate)}');
    debugPrint('[EDIT STOP] Duration: $newDuration minutes');

    try {
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

      final itinerary = await _loadItinerary();
      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        travelPace: itinerary.travelPace,
      );

      if (!result.isValid) {
        _editedEndTime = _stop.endTime;
        _editedDurationMinutes = _stop.durationMinutes;
        _error = result.issues.first.message;
        notifyListeners();
        return false;
      }

      _editedEndTime = candidate;
      _editedDurationMinutes = newDuration;
      _error = null;
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

  /// Set a new temporary DURATION. The end time is recalculated.
  Future<bool> setDuration(int newDurationMinutes) async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }
    if (newDurationMinutes <= 0) {
      _error = 'The selected duration is invalid.';
      notifyListeners();
      return false;
    }
    if (newDurationMinutes == _editedDurationMinutes) {
      _error = null;
      return true;
    }

    final candidateEnd =
    _editedStartTime.add(Duration(minutes: newDurationMinutes));
    if (!candidateEnd.isAfter(_editedStartTime)) {
      _error = 'The selected duration is invalid.';
      notifyListeners();
      return false;
    }

    debugPrint('[EDIT STOP] Duration selected');
    debugPrint('[EDIT STOP] Original: ${_stop.durationMinutes} minutes');
    debugPrint('[EDIT STOP] New: $newDurationMinutes minutes');
    debugPrint('[EDIT STOP] Start: ${_fmt(_editedStartTime)}');
    debugPrint('[EDIT STOP] End: ${_fmt(candidateEnd)}');

    try {
      final dayStops = await _loadDayStops();
      final updated = _buildUpdatedStop(
        startTime: _editedStartTime,
        endTime: candidateEnd,
        durationMinutes: newDurationMinutes,
      );
      final resulting = <ItineraryStop>[
        for (final s in dayStops)
          if (s.stopId == _stop.stopId) updated else s,
      ];

      final itinerary = await _loadItinerary();
      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        travelPace: itinerary.travelPace,
      );

      if (!result.isValid) {
        _error = result.issues.first.message;
        notifyListeners();
        return false;
      }

      _editedDurationMinutes = newDurationMinutes;
      _editedEndTime = candidateEnd;
      _error = null;
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

  /// Persist the pending time changes (start/end/duration) in a single
  /// repository update.
  Future<bool> saveTimeChanges() async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }
    if (!hasUnsavedChanges) {
      _error = null;
      return true;
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
      final result = await _validator.validateResultingDay(
        dayStops: resulting,
        dayDate: _dayDate(itinerary),
        window: ItineraryConstants.explorationWindowFor(
          itinerary.explorationTime,
        ),
        transportMode: itinerary.transportationMode,
        focusStop: _stop,
        travelPace: itinerary.travelPace,
      );

      if (!result.isValid) {
        _error = result.issues.first.message;
        notifyListeners();
        return false;
      }

      debugPrint('[EDIT STOP] Updating stop');
      debugPrint('[EDIT STOP] Stop ID: ${updated.stopId}');
      debugPrint('[EDIT STOP] Start: ${_fmt(updated.startTime)}');
      debugPrint('[EDIT STOP] End: ${_fmt(updated.endTime)}');
      debugPrint('[EDIT STOP] Duration: ${updated.durationMinutes} min');
      debugPrint('[EDIT STOP] Status: ${updated.stopStatus}');

      final saved = await _repo.updateStop(updated);
      _stop = saved.copyWith(place: _stop.place);
      _editedStartTime = _stop.startTime;
      _editedEndTime = _stop.endTime;
      _editedDurationMinutes = _stop.durationMinutes;
      _dayStopsWithPlaces = null;
      _error = null;
      await _refreshTimeOptions(itinerary, dayStops);
      notifyListeners();
      debugPrint('[EDIT STOP] Stop updated successfully');
      return true;
    } catch (e) {
      _error = 'Unable to update the stop. Please try again.';
      debugPrint('[EDIT STOP] Stop update failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
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
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }
    if (_stop.stopId == 0) return false;
    if (_stop.stopStatus == completed) {
      _error = 'This stop has already been completed and cannot be modified.';
      notifyListeners();
      return false;
    }

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

  Future<void> _refreshTimeOptions(
      Itinerary itinerary,
      List<ItineraryStop> dayStops,
      ) async {
    final window = ItineraryConstants.explorationWindowFor(
      itinerary.explorationTime,
    );

    final sorted = List<ItineraryStop>.from(dayStops)
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    final idx = sorted.indexWhere((s) => s.stopId == _stop.stopId);
    final prev = idx > 0 ? sorted[idx - 1] : null;
    final next =
    idx >= 0 && idx < sorted.length - 1 ? sorted[idx + 1] : null;

    final windowStart = window.startHour * 60 + window.startMinute;
    final windowEnd = window.endHour * 60 + window.endMinute;

    // ── Start times ──────────────────────────────────────────────
    final startSlots = <DateTime>[];
    final duration = _editedDurationMinutes;

    for (int minutes = windowStart;
    minutes + duration <= windowEnd;
    minutes += startTimeStepMinutes) {
      final candidate = _atMinutes(minutes);

      if (prev != null) {
        final prevEnd = prev.endTime;
        final travel = prev.travelFromPrevMinutes ?? 0;
        if (candidate.isBefore(
            prevEnd.add(Duration(minutes: travel)))) {
          continue;
        }
      }

      final candidateEnd = candidate.add(Duration(minutes: duration));
      if (next != null) {
        final nextTravel = next.travelFromPrevMinutes ?? 0;
        if (candidateEnd.isAfter(
            next.startTime.subtract(Duration(minutes: nextTravel)))) {
          continue;
        }
      }

      startSlots.add(candidate);
    }

    if (!startSlots.contains(_editedStartTime)) {
      startSlots.add(_editedStartTime);
      startSlots.sort((a, b) => a.compareTo(b));
    }
    _availableStartTimes = startSlots;

    // ── End times ────────────────────────────────────────────────
    final endSlots = <DateTime>[];

    for (int minutes = windowStart + duration;
    minutes <= windowEnd;
    minutes += endTimeStepMinutes) {
      final candidate = _atMinutes(minutes);

      // Must be after start + duration
      final minEnd = _editedStartTime.add(Duration(minutes: duration));
      if (candidate.isBefore(minEnd)) continue;

      // Must allow enough time for the next stop
      if (next != null) {
        final nextTravel = next.travelFromPrevMinutes ?? 0;
        if (candidate.isAfter(
            next.startTime.subtract(Duration(minutes: nextTravel)))) {
          continue;
        }
      }

      endSlots.add(candidate);
    }

    // Include current edited end time
    if (!endSlots.contains(_editedEndTime)) {
      endSlots.add(_editedEndTime);
      endSlots.sort((a, b) => a.compareTo(b));
    }
    _availableEndTimes = endSlots;

    // ── Durations (unchanged but recomputed) ────────────────────
    final durationSlots = <int>[];
    final minDur = ItineraryConstants.minimumVisitDurationMinutes;
    final maxDur = ItineraryConstants.maximumVisitDurationMinutes;

    for (final d in predefinedDurations) {
      if (d < minDur || d > maxDur) continue;

      final end = _editedStartTime.add(Duration(minutes: d));
      if (end.isAfter(_atMinutes(windowEnd))) continue;

      if (next != null) {
        final nextTravel = next.travelFromPrevMinutes ?? 0;
        if (end.isAfter(
            next.startTime.subtract(Duration(minutes: nextTravel)))) {
          continue;
        }
      }

      if (prev != null) {
        final prevEnd = prev.endTime;
        final travel = prev.travelFromPrevMinutes ?? 0;
        if (_editedStartTime.isBefore(
            prevEnd.add(Duration(minutes: travel)))) {
          continue;
        }
      }

      durationSlots.add(d);
    }

    if (!durationSlots.contains(_editedDurationMinutes)) {
      durationSlots.add(_editedDurationMinutes);
      durationSlots.sort();
    }
    _availableDurations = durationSlots;
  }

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