import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../model/entities/bookmark.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/itinerary_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';
import 'package:narrate_my/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';

/// Presentation UI wrapper combining Stop + Place details.
class DisplayableStop {
  final ItineraryStop stop;
  final Place place;
  final String formattedTime;
  final String? travelFromPrevText;
  final String? travelToNextText;

  DisplayableStop({
    required this.stop,
    required this.place,
    required this.formattedTime,
    this.travelFromPrevText,
    this.travelToNextText,
  });
}

class ManageDisplayPlanViewModel extends ChangeNotifier {
  final String itineraryId;
  final ItineraryRepositoryImpl _repository = ItineraryRepositoryImpl();
  final ItineraryStopRepositoryImpl _stopRepo = ItineraryStopRepositoryImpl();
  final PlaceRepositoryAdapter _placeRepo = PlaceRepositoryAdapter();

  // ─── State ──────────────────────────────────────────────────

  Itinerary? _itinerary;
  List<ItineraryStop> _stops = [];
  int _selectedDayIndex = 1; // 1-based day (header: "Day 1")
  String? _expandedStopId;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  ItineraryTemporalStatus _temporalStatus = ItineraryTemporalStatus.upcoming;

  /// Stop-status filter (null = show all).
  String? _stopStatusFilter;

  // ─── Getters ────────────────────────────────────────────────

  Itinerary? get itinerary => _itinerary;
  List<ItineraryStop> get stops => _stops;
  int get selectedDayIndex => _selectedDayIndex;
  String? get expandedStopId => _expandedStopId;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  String? get stopStatusFilter => _stopStatusFilter;

  /// Date-based temporal status (Past / Ongoing / Upcoming).
  ItineraryTemporalStatus get temporalStatus => _temporalStatus;

  /// Whether the itinerary is read-only (Past).
  bool get isReadOnly => _temporalStatus.isReadOnly;

  /// Whether progress recording (Completed/Skipped) is allowed (Ongoing only).
  bool get canRecordProgress => _temporalStatus.allowsProgressRecording;

  /// Whether the itinerary can be customized (Ongoing only).
  bool get canCustomize => _temporalStatus.isEditable;

  /// Set the stop-status filter (Planned/Completed/Skipped, or null for all).
  void setStopStatusFilter(String? status) {
    if (_stopStatusFilter == status) return;
    _stopStatusFilter = status;
    notifyListeners();
  }

  /// Stops for the currently selected day, sorted by [ItineraryStop.stopOrder].
  /// Stops are stored 1-based (`day_index > 0`), matching [selectedDayIndex].
  List<ItineraryStop> get currentDayStops {
    var dayStops = _stops
        .where((s) => s.dayIndex == _selectedDayIndex)
        .toList();
    dayStops.sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

    // Apply the stop-status filter (Planned / Completed / Skipped).
    if (_stopStatusFilter != null) {
      dayStops = dayStops
          .where((s) => s.stopStatus == _stopStatusFilter)
          .toList();
    }
    return dayStops;
  }

  /// Condensed itinerary preview: the first stop of each day.
  ///
  /// Groups [_stops] by [ItineraryStop.dayIndex], sorts each day's stops by
  /// [ItineraryStop.stopOrder] ascending, and keeps only the stop with the
  /// smallest `stopOrder` per day. Keys are 1-based day indexes.
  Map<int, ItineraryStop> get firstStopPerDay {
    final byDay = <int, List<ItineraryStop>>{};
    for (final stop in _stops) {
      byDay.putIfAbsent(stop.dayIndex, () => []).add(stop);
    }

    final result = <int, ItineraryStop>{};
    final dayIndexes = byDay.keys.toList()..sort();
    for (final dayIndex in dayIndexes) {
      final stops = byDay[dayIndex]!
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      if (stops.isNotEmpty) {
        result[dayIndex] = stops.first;
      }
    }
    return result;
  }

  /// [firstStopPerDay] as a sorted list (ascending day order) for previews.
  List<ItineraryStop> get firstStopPerDayList {
    final map = firstStopPerDay;
    final days = map.keys.toList()..sort();
    return [for (final day in days) map[day]!];
  }

  // ─── Constructor ────────────────────────────────────────────

  ManageDisplayPlanViewModel({required this.itineraryId});

  // ─── Public Methods ────────────────────────────────────────

  /// Load the itinerary, its stops, and join each stop with its Place.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('📚 Loading itinerary: $itineraryId');
      _itinerary = await _repository.getItinerary(itineraryId);
      print('✅ Itinerary loaded: $_itinerary');

      // Compute temporal status from dates (not from the stored status field).
      _temporalStatus = ItineraryStatusResolver.resolve(
        startDate: _itinerary!.startDate,
        endDate: _itinerary!.endDate,
      );
      print('✅ Temporal status: ${_temporalStatus.name}');

      final rawStops = await _stopRepo.getStopsForItinerary(itineraryId);
      print('✅ Stops loaded: ${rawStops.length}');

      // Join each stop with its original Place (nullable; fall back to
      // Place.empty when the place is not yet in the local DB).
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

      _selectedDayIndex = 1;
      _expandedStopId = null;
    } catch (e) {
      _error = e.toString();
      print('❌ Load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh (pull‑to‑refresh).
  Future<void> refresh() => load();

  /// Change the selected day.
  void selectDay(int dayIndex) {
    _selectedDayIndex = dayIndex;
    _expandedStopId = null;
    notifyListeners();
  }

  /// Toggle expansion of a stop card by stop ID.
  void toggleStopExpansion(String stopId) {
    _expandedStopId = _expandedStopId == stopId ? null : stopId;
    notifyListeners();
  }

  /// Add a new stop.
  Future<void> addStop(ItineraryStop newStop) async {
    final maxOrder = _stops
        .where((s) => s.dayIndex == newStop.dayIndex)
        .fold<int>(-1, (max, s) => s.stopOrder > max ? s.stopOrder : max);
    newStop = newStop.copyWith(
      stopOrder: maxOrder + 1,
      itineraryId: itineraryId,
    );
    _stops.add(newStop);
    await _stopRepo.saveStops(_stops);
    notifyListeners();
  }

  /// Add the given bookmarked places as new stops on [dayIndex].
  ///
  /// Only runs for ongoing itineraries. Each bookmark is saved as a Place
  /// (so the stop can be joined later) and appended to the day after the
  /// last existing stop.
  Future<bool> addBookmarkedPlaces({
    required int dayIndex,
    required List<Bookmark> bookmarks,
  }) async {
    if (!canCustomize) return false;
    if (bookmarks.isEmpty) return true;

    // Skip bookmarks already used in this itinerary.
    final usedIds = _stops.map((s) => s.placeId).toSet();
    // final toAdd = bookmarks
    //     .where((b) => !usedIds.contains(b.placeId))
    //     .toList();
    // if (toAdd.isEmpty) return true;

    var nextOrder = _stops
            .where((s) => s.dayIndex == dayIndex)
            .fold<int>(-1, (max, s) => s.stopOrder > max ? s.stopOrder : max) +
        1;

    final now = DateTime.now();
    final added = <ItineraryStop>[];

    // for (final b in toAdd) {
    //   // final place = Place(
    //   //   placeId: b.placeId,
    //   //   placeName: b.placeName,
    //   //   placeAddress: b.placeAddress,
    //   //   placeLatitude: b.placeLatitude,
    //   //   placeLongitude: b.placeLongitude,
    //   //   placeRating: b.placeRating ?? 3.5,
    //   //   placeTypes: (b.placeTypes ?? '').split(','),
    //   //   placePhotoRef: b.placePhotoRef,
    //   //   category: 'landmark',
    //   //   visitDurationMinutes: 90,
    //   // );
    //   try {
    //     await _placeRepo.savePlace(place);
    //   } catch (e) {
    //     debugPrint('[ManagePlanVM] bookmark place save failed: $e');
    //   }
    //
    //   added.add(ItineraryStop(
    //     stopId: 0,
    //     itineraryId: itineraryId,
    //     placeId: b.placeId,
    //     dayIndex: dayIndex,
    //     stopOrder: nextOrder++,
    //     startTime: now,
    //     endTime: now.add(const Duration(minutes: 90)),
    //     durationMinutes: 90,
    //     travelFromPrevMinutes: null,
    //     stopStatus: 'PLANNED',
    //     createdAt: now,
    //     updatedAt: now,
    //   ));
    // }

    _stops.addAll(added);
    await _stopRepo.saveStops(_stops);
    notifyListeners();
    return true;
  }

  /// Remove a stop by its stop ID.
  Future<void> deleteStop(String stopId) async {
    final index = _stops.indexWhere((s) => s.stopId.toString() == stopId);
    if (index < 0 || index >= _stops.length) return;
    _stops.removeAt(index);
    _reassignStopOrders();
    await _stopRepo.saveStops(_stops);
    notifyListeners();
  }

  /// Update an existing stop.
  Future<void> updateStop(int stopIndex, ItineraryStop updatedStop) async {
    if (stopIndex < 0 || stopIndex >= _stops.length) return;
    _stops[stopIndex] = updatedStop;
    await _stopRepo.saveStops(_stops);
    notifyListeners();
  }

  /// Reorder stops within a day.
  void reorderStops(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final item = _stops.removeAt(oldIndex);
    _stops.insert(newIndex, item);
    _reassignStopOrders();
    _stopRepo.saveStops(_stops);
    notifyListeners();
  }

  /// Save all changes (itinerary metadata + stops).
  Future<void> saveChanges() async {
    if (_itinerary == null) return;
    _isSaving = true;
    notifyListeners();

    try {
      final updatedItinerary = _itinerary!.copyWith(
        lastModifiedAt: DateTime.now(),
      );
      await _repository.updateItinerary(updatedItinerary);
      await _stopRepo.saveStops(_stops);
      _itinerary = updatedItinerary;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // ─── Private Helpers ────────────────────────────────────────

  void _reassignStopOrders() {
    int order = 0;
    for (int i = 0; i < _stops.length; i++) {
      _stops[i] = _stops[i].copyWith(stopOrder: order++);
    }
  }
}

/// Presentation helpers combining Itinerary + stops + Place data
/// for the EditItinerary screen.
extension ManageDisplayPlanViewModelUI on ManageDisplayPlanViewModel {
  /// Header string formatted like: "Day 1 · 12 Aug · Kuala Lumpur Getaway"
  String get formattedDayHeader {
    if (itinerary == null) return '';
    final currentDate =
        itinerary!.startDate.add(Duration(days: selectedDayIndex - 1));
    final dateStr = DateFormat('d MMM').format(currentDate);
    return 'Day $selectedDayIndex · $dateStr · ${itinerary!.title}';
  }

  /// Combined stops with place data and computed travel intervals for UI rendering.
  List<DisplayableStop> get currentDayDisplayStops {
    final stops = currentDayStops; // Filtered & sorted by stopOrder
    final List<DisplayableStop> displayList = [];

    for (int i = 0; i < stops.length; i++) {
      final current = stops[i];
      final place = current.place ?? Place.empty(current.placeId); // Join reference

      final timeFormat = DateFormat('HH:mm');
      final timeRange =
          '${timeFormat.format(current.startTime)} – ${timeFormat.format(current.endTime)}';

      // Prev travel calculation
      final prevText = current.travelFromPrevMinutes != null
          ? '${current.travelFromPrevMinutes} min'
          : null;

      // Next travel calculation
      String? nextText;
      if (i < stops.length - 1) {
        final nextStop = stops[i + 1];
        if (nextStop.travelFromPrevMinutes != null) {
          nextText = '${nextStop.travelFromPrevMinutes} min';
        }
      }

      displayList.add(
        DisplayableStop(
          stop: current,
          place: place,
          formattedTime: timeRange,
          travelFromPrevText: prevText,
          travelToNextText: nextText,
        ),
      );
    }
    return displayList;
  }
}
