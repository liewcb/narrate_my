// lib/viewmodel/ItineraryModel/edit_stop_vm.dart
import 'package:flutter/foundation.dart';

import '../../model/entities/itinerary_stop.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';

/// Traveler progress for a single itinerary stop.
///
/// Only the traveler's progress note (status + optional skip reason) is
/// mutated here. The scheduled start/end time, duration, stop order,
/// day index, route and travel times are NEVER changed.
class EditStopViewModel extends ChangeNotifier {
  static const String planned = 'PLANNED';
  static const String completed = 'COMPLETED';
  static const String skipped = 'SKIPPED';

  final ItineraryStopRepositoryImpl _repo = ItineraryStopRepositoryImpl();

  late ItineraryStop _stop;
  final DateTime _itineraryStartDate;
  final bool _isReadOnly;

  bool _isSaving = false;
  String? _error;

  EditStopViewModel({
    required ItineraryStop stop,
    required DateTime itineraryStartDate,
    bool isReadOnly = false,
  })  : _stop = stop,
        _itineraryStartDate = itineraryStartDate,
        _isReadOnly = isReadOnly;

  // ─── Getters ────────────────────────────────────────────────

  ItineraryStop get stop => _stop;
  bool get isSaving => _isSaving;
  String? get error => _error;
  String get status => _stop.stopStatus;
  bool get isCompleted => _stop.stopStatus == completed;
  bool get isSkipped => _stop.stopStatus == skipped;

  /// Whether progress can be modified (Past itineraries are read-only).
  bool get isReadOnly => _isReadOnly;

  /// The actual scheduled start date+time of this stop: the itinerary
  /// start date shifted to this stop's day, combined with the stop's
  /// scheduled clock time.
  DateTime get scheduledStartDateTime {
    final dayDate =
        _itineraryStartDate.add(Duration(days: _stop.dayIndex - 1));
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      _stop.startTime.hour,
      _stop.startTime.minute,
      _stop.startTime.second,
    );
  }

  /// A future stop may not be marked Completed before its scheduled time.
  bool get canCompleteNow => !DateTime.now().isBefore(scheduledStartDateTime);

  /// Whether a transition to [newStatus] is allowed under the progress rules.
  ///
  /// Supported transitions:
  ///   Planned → Completed (only once the scheduled time has arrived)
  ///   Planned → Skipped
  ///   Completed → Planned
  ///   Skipped → Planned
  ///
  /// No direct Completed ↔ Skipped.
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

  // ─── Actions ────────────────────────────────────────────────

  /// Attempt to change this stop's status. Returns `true` on success.
  ///
  /// On failure the previous status is kept and [_error] is populated so
  /// the UI can show a message and let the traveler retry.
  Future<bool> updateStatus(String newStatus, {String? skipReason}) async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }

    if (newStatus == _stop.stopStatus) {
      _error = null;
      return true; // No change requested (idempotent).
    }

    if (isCompleted) {
      // Completed cannot be re-completed; must revert to Planned first.
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

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      // Build the updated stop preserving ALL scheduling/planning fields.
      final updated = ItineraryStop(
        stopId: _stop.stopId,
        itineraryId: _stop.itineraryId,
        placeId: _stop.placeId,
        dayIndex: _stop.dayIndex,
        stopOrder: _stop.stopOrder,
        startTime: _stop.startTime,
        endTime: _stop.endTime,
        durationMinutes: _stop.durationMinutes,
        travelFromPrevMinutes: _stop.travelFromPrevMinutes,
        stopStatus: newStatus,
        skipReason:
            newStatus == skipped ? (skipReason ?? _stop.skipReason) : null,
        weatherNote: _stop.weatherNote,
        place: _stop.place,
        createdAt: _stop.createdAt,
        updatedAt: DateTime.now(),
      );

      final saved = await _repo.updateStop(updated);
      _stop = saved.copyWith(place: _stop.place);
      notifyListeners();
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

  /// Persist only the skip reason/note (traveler note, not scheduling).
  /// Does not change the status and never touches the schedule.
  Future<bool> saveSkipReason(String? reason) async {
    if (reason == _stop.skipReason) return true;

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = ItineraryStop(
        stopId: _stop.stopId,
        itineraryId: _stop.itineraryId,
        placeId: _stop.placeId,
        dayIndex: _stop.dayIndex,
        stopOrder: _stop.stopOrder,
        startTime: _stop.startTime,
        endTime: _stop.endTime,
        durationMinutes: _stop.durationMinutes,
        travelFromPrevMinutes: _stop.travelFromPrevMinutes,
        stopStatus: _stop.stopStatus,
        skipReason: reason,
        weatherNote: _stop.weatherNote,
        place: _stop.place,
        createdAt: _stop.createdAt,
        updatedAt: DateTime.now(),
      );

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

  /// Persist only the skip reason/note (traveler note, not scheduling).
  /// Does not change the status and never touches the schedule.
  Future<bool> deleteStop() async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }
    if (_stop.stopId == 0) return false;

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      await _repo.deleteStop(_stop.stopId);
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
}
