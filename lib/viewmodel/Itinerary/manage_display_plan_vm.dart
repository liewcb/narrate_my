import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/services/database_manager.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/itinerary_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';
import '../../core/config/api_keys.dart';
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
  final ItineraryRepositoryImpl _repository = DatabaseManager().itineraryRepository;
  final ItineraryStopRepositoryImpl _stopRepo = DatabaseManager().itineraryStopRepository;
  final PlaceRepositoryAdapter _placeRepo = DatabaseManager().placeRepository;

  // ─── State ──────────────────────────────────────────────────

  Itinerary? _itinerary;
  List<ItineraryStop> _stops = [];
  int? _selectedDayFilter; // null = all days, otherwise day index
  String? _expandedStopId;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  ItineraryTemporalStatus _temporalStatus = ItineraryTemporalStatus.upcoming;
  String? _stopStatusFilter;

  // ─── Getters ────────────────────────────────────────────────

  Itinerary? get itinerary => _itinerary;
  List<ItineraryStop> get stops => _stops;
  int? get selectedDayFilter => _selectedDayFilter;
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

  /// Whether the itinerary can be customized (Ongoing or Upcoming – now editable).
  bool get canCustomize => _temporalStatus.isEditable;

  /// Sorted list of available day indices (1‑based).
  List<int> get availableDayIndices {
    final set = _stops.map((s) => s.dayIndex).toSet();
    final list = set.toList()..sort();
    return list;
  }

  /// Set the stop-status filter (Planned/Completed/Skipped, or null for all).
  void setStopStatusFilter(String? status) {
    if (_stopStatusFilter == status) return;
    _stopStatusFilter = status;
    notifyListeners();
  }

  /// Stops for the currently selected day, or all stops if filter is null.
  /// Sorted by [ItineraryStop.stopOrder].
  List<ItineraryStop> get filteredStops {
    var filtered = _stops;
    if (_selectedDayFilter != null) {
      filtered = filtered.where((s) => s.dayIndex == _selectedDayFilter).toList();
    }
    if (_stopStatusFilter != null) {
      filtered = filtered.where((s) => s.stopStatus == _stopStatusFilter).toList();
    }
    filtered.sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    return filtered;
  }

  /// Returns a hero image URL for a given day (or for all days if [dayIndex] is null).
  String? getHeroImageUrl(int? dayIndex) {
    String? ref;
    if (dayIndex == null) {
      // All days: use the first stop of the whole itinerary
      final firstStop = _stops.isNotEmpty ? _stops.first : null;
      ref = firstStop?.place?.placePhotoRef;
    } else {
      // Specific day: find the first stop of that day
      final dayStops = _stops.where((s) => s.dayIndex == dayIndex).toList()
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      ref = dayStops.isNotEmpty ? dayStops.first.place?.placePhotoRef : null;
    }
    if (ref == null || ref.isEmpty) return null;
    return _buildPhotoUrl(ref, maxWidth: 800);
  }

  String _buildPhotoUrl(String photoreference, {int maxWidth = 800}) {
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=$maxWidth'
        '&photoreference=$photoreference'
        '&key=${ApiKeys.googleMapsApiKey}';
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

      // Reset selected day filter to null (show all) after load.
      _selectedDayFilter = null;
      _expandedStopId = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh (pull‑to‑refresh).
  Future<void> refresh() => load();

  /// Change the selected day filter (null for all days).
  void selectDay(int? dayIndex) {
    if (_selectedDayFilter == dayIndex) return;
    _selectedDayFilter = dayIndex;
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

  /// Add bookmarked places (by their Google placeIds) as new stops on
  /// [dayIndex].
  Future<int> addBookmarkedPlaces({
    required int dayIndex,
    required List<String> placeIds,
  }) async {
    if (!canCustomize) return 0;
    if (placeIds.isEmpty) return 0;

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
        debugPrint('[ManagePlanVM] bookmark place save failed: $e');
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
    await _stopRepo.saveStops(_stops);
    notifyListeners();
    return added.length;
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
    final currentDay = selectedDayFilter ?? 1;
    final currentDate = itinerary!.startDate.add(Duration(days: currentDay - 1));
    final dateStr = DateFormat('d MMM').format(currentDate);
    return 'Day $currentDay · $dateStr · ${itinerary!.title}';
  }

  /// Combined stops with place data and computed travel intervals for UI rendering.
  List<DisplayableStop> get currentDayDisplayStops {
    final stops = filteredStops;
    final List<DisplayableStop> displayList = [];

    for (int i = 0; i < stops.length; i++) {
      final current = stops[i];
      final place = current.place ?? Place.empty(current.placeId);

      final timeFormat = DateFormat('HH:mm');
      final timeRange =
          '${timeFormat.format(current.startTime)} – ${timeFormat.format(current.endTime)}';

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