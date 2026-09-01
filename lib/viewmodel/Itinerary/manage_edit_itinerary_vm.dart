// lib/viewmodel/ItineraryModel/manage_edit_itinerary_vm.dart
//
// ViewModel for ManageEditItineraryScreen — the day-editor reached after
// tapping a specific day card in ManageDisplayPlanScreen.
//
// Owns the day's stops (joined with their Places), tracks dirty state, and
// persists changes through the same repositories as ManageDisplayPlanViewModel.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/services/database_manager.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/itinerary_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';
import 'package:narrate_my/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';

/// Presentation wrapper for a single stop card in the day editor.
class DayStopItem {
  final ItineraryStop stop;
  final Place place;
  final String formattedTime;
  final String visitDurationText;
  final String? travelFromPrevText;
  final String? travelToNextText;

  DayStopItem({
    required this.stop,
    required this.place,
    required this.formattedTime,
    required this.visitDurationText,
    this.travelFromPrevText,
    this.travelToNextText,
  });
}

class ManageEditItineraryViewModel extends ChangeNotifier {
  final String itineraryId;
  final int dayIndex; // 1-based day number

  final ItineraryRepositoryImpl _repository = DatabaseManager().itineraryRepository;
  final ItineraryStopRepositoryImpl _stopRepo = DatabaseManager().itineraryStopRepository;
  final PlaceRepositoryAdapter _placeRepo = DatabaseManager().placeRepository;

  // ─── State ──────────────────────────────────────────────────

  Itinerary? _itinerary;
  List<ItineraryStop> _stops = [];
  int? _expandedIndex;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasChanges = false;
  String? _error;
  ItineraryTemporalStatus _temporalStatus = ItineraryTemporalStatus.upcoming;

  // ─── Getters ────────────────────────────────────────────────

  Itinerary? get itinerary => _itinerary;
  List<ItineraryStop> get stops => _stops;
  int? get expandedIndex => _expandedIndex;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get hasChanges => _hasChanges;
  String? get error => _error;
  ItineraryTemporalStatus get temporalStatus => _temporalStatus;

  /// Past itineraries are read-only.
  bool get isReadOnly => _temporalStatus.isReadOnly;

  /// Only ongoing itineraries can be customized.
  bool get canCustomize => _temporalStatus.isEditable;

  String get tripTitle => _itinerary?.title ?? 'My Trip';

  /// The calendar date of this day, derived from the itinerary start date.
  DateTime get dayDate {
    if (_itinerary == null) return DateTime.now();
    return _itinerary!.startDate.add(Duration(days: dayIndex - 1));
  }

  /// This day's stops sorted by stop order.
  List<ItineraryStop> get currentDayStops {
    final dayStops = _stops
        .where((s) => s.dayIndex == dayIndex)
        .toList()
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    return dayStops;
  }

  // ─── Constructor ────────────────────────────────────────────

  ManageEditItineraryViewModel({
    required this.itineraryId,
    required this.dayIndex,
  });

  // ─── Public Methods ────────────────────────────────────────

  /// Load the itinerary and this day's stops, joined with their Places.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _itinerary = await _repository.getItinerary(itineraryId);
      _temporalStatus = ItineraryStatusResolver.resolve(
        startDate: _itinerary!.startDate,
        endDate: _itinerary!.endDate,
      );

      final rawStops = await _stopRepo.getStopsForItinerary(itineraryId);
      final joined = <ItineraryStop>[];
      for (final stop in rawStops) {
        Place? place;
        try {
          place = await _placeRepo.getPlace(stop.placeId);
        } catch (_) {
          place = null;
        }
        joined.add(stop.copyWith(place: place));
      }
      _stops = joined;
      _expandedIndex = _stops.isEmpty ? null : 0;
      _hasChanges = false;
    } catch (e) {
      _error = e.toString();
      debugPrint('[EditItineraryVM] Load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh from the repositories (used after returning from sub-screens).
  Future<void> refresh() => load();

  /// Toggle which stop card is expanded.
  void toggleExpand(int index) {
    _expandedIndex = _expandedIndex == index ? null : index;
    notifyListeners();
  }

  /// Remove a stop by its index within this day's list.
  Future<bool> deleteStop(int index) async {
    if (!canCustomize || isReadOnly) return false;
    final stops = currentDayStops;
    if (index < 0 || index >= stops.length) return false;

    final stopToRemove = stops[index];
    _stops.removeWhere(
      (s) =>
          s.dayIndex == dayIndex &&
          s.stopId == stopToRemove.stopId &&
          s.placeId == stopToRemove.placeId,
    );
    _reassignStopOrders();
    _hasChanges = true;
    notifyListeners();

    try {
      await _stopRepo.saveStops(_stops);
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[EditItineraryVM] Delete failed: $e');
      notifyListeners();
      return false;
    }
  }

  /// Add bookmarked places (by Google placeIds) as new stops on this day.
  Future<int> addBookmarkedPlaces(List<String> placeIds) async {
    if (!canCustomize || placeIds.isEmpty) return 0;

    final usedIds = _stops.map((s) => s.placeId).toSet();
    final toAdd = placeIds.where((id) => !usedIds.contains(id)).toList();
    if (toAdd.isEmpty) return 0;

    var nextOrder = _stops
            .where((s) => s.dayIndex == dayIndex)
            .fold<int>(-1, (max, s) => s.stopOrder > max ? s.stopOrder : max) +
        1;

    final now = DateTime.now();
    final added = <ItineraryStop>[];

    for (final placeId in toAdd) {
      Place? place;
      try {
        place = await _placeRepo.getPlace(placeId);
      } catch (_) {
        place = null;
      }
      if (place == null) {
        place = Place.empty(placeId);
      }
      try {
        await _placeRepo.savePlace(place);
      } catch (e) {
        debugPrint('[EditItineraryVM] bookmark place save failed: $e');
      }

      added.add(ItineraryStop(
        stopId: 0,
        itineraryId: itineraryId,
        placeId: place.placeId,
        dayIndex: dayIndex,
        stopOrder: nextOrder++,
        startTime: now,
        endTime: now.add(const Duration(minutes: 90)),
        durationMinutes: 90,
        travelFromPrevMinutes: null,
        stopStatus: 'PLANNED',
        createdAt: now,
        updatedAt: now,
      ));
    }

    _stops.addAll(added);
    _hasChanges = true;
    notifyListeners();
    return added.length;
  }

  /// Reorder stops within this day.
  void reorderStops(int oldIndex, int newIndex) {
    final dayStops = currentDayStops;
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= dayStops.length ||
        newIndex < 0 ||
        newIndex >= dayStops.length) {
      return;
    }

    final dayList = List<ItineraryStop>.from(dayStops);
    final item = dayList.removeAt(oldIndex);
    dayList.insert(newIndex, item);

    for (int i = 0; i < dayList.length; i++) {
      _stops = [
        for (final s in _stops)
          if (s.dayIndex == dayIndex)
            s.copyWith(stopOrder: dayList.indexOf(s))
          else
            s,
      ];
    }
    _hasChanges = true;
    notifyListeners();
  }

  /// Persist this day's stops to the repositories.
  Future<bool> saveChanges() async {
    if (_itinerary == null || isReadOnly) return false;
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      await _stopRepo.saveStops(_stops);
      final updated = _itinerary!.copyWith(lastModifiedAt: DateTime.now());
      await _repository.updateItinerary(updated);
      _itinerary = updated;
      _hasChanges = false;
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[EditItineraryVM] Save failed: $e');
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // ─── Private Helpers ────────────────────────────────────────

  void _reassignStopOrders() {
    int order = 0;
    for (final stop in currentDayStops) {
      _stops = [
        for (final s in _stops)
          if (s == stop) s.copyWith(stopOrder: order) else s,
      ];
      order++;
    }
  }
}

/// Presentation helpers for the day-editor UI.
extension ManageEditItineraryViewModelUI on ManageEditItineraryViewModel {
  /// Header string: "Day 2 · 12 Aug · Kuala Lumpur Getaway".
  String get formattedDayHeader {
    final dateStr = DateFormat('d MMM').format(dayDate);
    return 'Day $dayIndex · $dateStr · $tripTitle';
  }

  /// Day stops rendered as display items (time, duration, travel texts).
  List<DayStopItem> get displayStops {
    final stops = currentDayStops;
    final items = <DayStopItem>[];

    for (int i = 0; i < stops.length; i++) {
      final current = stops[i];
      final place = current.place ?? Place.empty(current.placeId);

      final timeFormat = DateFormat('HH:mm');
      final timeRange =
          '${timeFormat.format(current.startTime)} – '
          '${timeFormat.format(current.endTime)}';

      final prevText = current.travelFromPrevMinutes != null
          ? '${current.travelFromPrevMinutes} min'
          : null;

      String? nextText;
      if (i < stops.length - 1) {
        final nextStop = stops[i + 1];
        if (nextStop.travelFromPrevMinutes != null) {
          nextText = '${nextStop.travelFromPrevMinutes} min';
        }
      }

      items.add(
        DayStopItem(
          stop: current,
          place: place,
          formattedTime: timeRange,
          visitDurationText: _formatDuration(current.durationMinutes),
          travelFromPrevText: prevText,
          travelToNextText: nextText,
        ),
      );
    }
    return items;
  }
}

String _formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  return rem == 0 ? '$hours hours' : '$hours hr $rem min';
}
