// lib/viewmodel/ItineraryModel/edit_stop_vm.dart
import 'package:flutter/foundation.dart';

import '../../model/entities/itinerary_stop.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';

/// Traveler progress for a single itinerary stop.
///
/// The traveler may edit the stop's scheduled START TIME (end time is
/// derived from the existing duration) and the progress status. Place,
/// day index, stop order, duration, route and travel times are NEVER
/// changed by this feature.
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

  // ── Temporary (uncommitted) time editing state ──────────────
  // The persisted stop is never mutated until the change is confirmed
  // and the repository update succeeds.
  late DateTime _editedStartTime;
  late DateTime _editedEndTime;

  EditStopViewModel({
    required ItineraryStop stop,
    required DateTime itineraryStartDate,
    bool isReadOnly = false,
  })  : _stop = stop,
        _itineraryStartDate = itineraryStartDate,
        _isReadOnly = isReadOnly {
    _editedStartTime = stop.startTime;
    _editedEndTime = stop.endTime;
  }

  // ─── Getters ────────────────────────────────────────────────

  ItineraryStop get stop => _stop;
  bool get isSaving => _isSaving;
  String? get error => _error;
  String get status => _stop.stopStatus;
  bool get isCompleted => _stop.stopStatus == completed;
  bool get isSkipped => _stop.stopStatus == skipped;

  /// Whether progress can be modified (Past itineraries are read-only).
  bool get isReadOnly => _isReadOnly;

  /// The temporary start time currently shown in the UI.
  DateTime get editedStartTime => _editedStartTime;

  /// The temporary end time derived from the edited start + duration.
  DateTime get editedEndTime => _editedEndTime;

  /// Whether the traveler has changed the start time (pending).
  bool get hasTimeChanges {
    return _editedStartTime.hour != _stop.startTime.hour ||
        _editedStartTime.minute != _stop.startTime.minute;
  }

  /// Whether any temporary value differs from the persisted stop.
  bool get hasUnsavedChanges => hasTimeChanges;

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

  // ─── Time editing ───────────────────────────────────────────

  /// Set a new temporary START time and derive the end time from the
  /// existing [durationMinutes]. Validates the result and does NOT
  /// touch the database. Returns `false` when the time is invalid.
  bool setStartTime(DateTime newStart) {
    final candidate = DateTime(
      _editedStartTime.year,
      _editedStartTime.month,
      _editedStartTime.day,
      newStart.hour,
      newStart.minute,
      newStart.second,
    );
    final newEnd = candidate.add(Duration(minutes: _stop.durationMinutes));

    if (!newEnd.isAfter(candidate)) {
      _error = 'The selected start time is invalid.';
      notifyListeners();
      return false;
    }

    debugPrint('[EDIT STOP] Time selected');
    debugPrint('[EDIT STOP] Original: '
        '${_fmt(_stop.startTime)} - ${_fmt(_stop.endTime)}');
    debugPrint('[EDIT STOP] New: ${_fmt(candidate)} - ${_fmt(newEnd)}');
    debugPrint('[EDIT STOP] Duration: ${_stop.durationMinutes} minutes');

    _editedStartTime = candidate;
    _editedEndTime = newEnd;
    _error = null;
    notifyListeners();
    return true;
  }

  /// Discard any pending time edits (restore the persisted values).
  void resetTimeEdits() {
    _editedStartTime = _stop.startTime;
    _editedEndTime = _stop.endTime;
    _error = null;
    notifyListeners();
  }

  /// Persist the pending time change (and optional skip reason) in a single
  /// repository update. Does not touch status here — status is handled by
  /// [updateStatus] after its own confirmation.
  Future<bool> saveTimeChanges() async {
    if (_isReadOnly) {
      _error = 'This itinerary is in the past and cannot be modified.';
      notifyListeners();
      return false;
    }
    if (!hasTimeChanges) {
      _error = null;
      return true; // Nothing to save.
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = _buildUpdatedStop(
        startTime: _editedStartTime,
        endTime: _editedEndTime,
      );

      debugPrint('[EDIT STOP] Updating stop');
      debugPrint('[EDIT STOP] Stop ID: ${updated.stopId}');
      debugPrint('[EDIT STOP] Start: ${_fmt(updated.startTime)}');
      debugPrint('[EDIT STOP] End: ${_fmt(updated.endTime)}');
      debugPrint('[EDIT STOP] Status: ${updated.stopStatus}');

      final saved = await _repo.updateStop(updated);
      _stop = saved.copyWith(place: _stop.place);
      _editedStartTime = _stop.startTime;
      _editedEndTime = _stop.endTime;
      _error = null;
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

  // ─── Status ─────────────────────────────────────────────────

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

    debugPrint('[EDIT STOP] Status change confirmed');
    debugPrint('[EDIT STOP] From: ${_stop.stopStatus}');
    debugPrint('[EDIT STOP] To: $newStatus');

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      // Build the updated stop preserving ALL scheduling/planning fields.
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

  /// Persist only the skip reason/note (traveler note, not scheduling).
  /// Does not change the status and never touches the schedule.
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

  // ─── Helpers ────────────────────────────────────────────────

  /// Build an updated stop preserving every scheduling/planning field,
  /// applying only the provided changes. Never overwrites with null.
  ItineraryStop _buildUpdatedStop({
    DateTime? startTime,
    DateTime? endTime,
    String? stopStatus,
    String? skipReason,
    bool clearSkipReason = false,
  }) {
    return ItineraryStop(
      stopId: _stop.stopId,
      itineraryId: _stop.itineraryId,
      placeId: _stop.placeId,
      dayIndex: _stop.dayIndex,
      stopOrder: _stop.stopOrder,
      startTime: startTime ?? _stop.startTime,
      endTime: endTime ?? _stop.endTime,
      durationMinutes: _stop.durationMinutes,
      travelFromPrevMinutes: _stop.travelFromPrevMinutes,
      stopStatus: stopStatus ?? _stop.stopStatus,
      skipReason: clearSkipReason
          ? null
          : (skipReason ?? _stop.skipReason),
      weatherNote: _stop.weatherNote,
      place: _stop.place,
      createdAt: _stop.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
