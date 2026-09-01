// lib/viewmodel/Itinerary/interactive_maps_vm.dart
//
// ViewModel for the Interactive Maps screen. Owns the itinerary, its stops
// (joined with their Places), the selected day filter and the day-grouped
// daily plan data. All data is loaded through the same repositories used by
// the other itinerary screens (no Supabase/Google access from the UI).

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

/// Presentation item: a single itinerary stop joined with its [Place],
/// prepared for the map markers and the daily plan rows.
class MapStopItem {
  final ItineraryStop stop;
  final Place place;

  MapStopItem({
    required this.stop,
    required this.place,
  });

  String get placeId => stop.placeId;
  String get name => place.placeName;
  String get address => place.placeAddress;
  double get latitude => place.placeLatitude;
  double get longitude => place.placeLongitude;
  int get dayIndex => stop.dayIndex;
  int get stopOrder => stop.stopOrder;

  /// "09:00 – 10:30"
  String get formattedTime {
    final f = DateFormat('HH:mm');
    return '${f.format(stop.startTime)} – ${f.format(stop.endTime)}';
  }
}

/// A single day's itinerary plan (used by the daily plan cards).
class DailyPlanItem {
  final int dayIndex;
  final DateTime date;
  final List<MapStopItem> stops;

  DailyPlanItem({
    required this.dayIndex,
    required this.date,
    required this.stops,
  });
}

class InteractiveMapsViewModel extends ChangeNotifier {
  final String itineraryId;

  final ItineraryRepositoryImpl _repository = DatabaseManager().itineraryRepository;
  final ItineraryStopRepositoryImpl _stopRepo = DatabaseManager().itineraryStopRepository;
  final PlaceRepositoryAdapter _placeRepo = DatabaseManager().placeRepository;

  // ─── State ──────────────────────────────────────────────────

  Itinerary? _itinerary;
  List<ItineraryStop> _stops = [];
  int? _selectedDayFilter; // null = All Days
  bool _isLoading = false;
  String? _error;
  ItineraryTemporalStatus _temporalStatus = ItineraryTemporalStatus.upcoming;

  // ─── Getters ────────────────────────────────────────────────

  Itinerary? get itinerary => _itinerary;
  List<ItineraryStop> get stops => _stops;
  int? get selectedDayFilter => _selectedDayFilter;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ItineraryTemporalStatus get temporalStatus => _temporalStatus;

  /// Past itineraries are read-only (reuses the same business rule as the
  /// other itinerary screens — no second definition here).
  bool get isReadOnly => _temporalStatus.isReadOnly;

  /// Only ongoing itineraries can be edited.
  bool get canEdit => _temporalStatus.isEditable;

  /// All day indices that actually contain stops, sorted ascending.
  List<int> get availableDayIndices {
    final indices = _stops.map((s) => s.dayIndex).toSet().toList()..sort();
    return indices;
  }

  /// Stops for the map, filtered by the selected day (null = all days).
  List<MapStopItem> get mapStops {
    final stops = _stops.where(
      (s) => _selectedDayFilter == null || s.dayIndex == _selectedDayFilter,
    );
    final items = stops
        .map((s) => MapStopItem(stop: s, place: s.place ?? Place.empty(s.placeId)))
        .toList()
      ..sort((a, b) {
        final day = a.dayIndex.compareTo(b.dayIndex);
        return day != 0 ? day : a.stopOrder.compareTo(b.stopOrder);
      });
    return items;
  }

  /// Daily plans grouped by actual [ItineraryStop.dayIndex], each day's
  /// stops sorted by [ItineraryStop.stopOrder]. Built from ALL stops (not
  /// filtered by the selected map day) so the Edit screen can show every day.
  List<DailyPlanItem> get dailyPlans {
    final grouped = <int, List<MapStopItem>>{};
    for (final stop in _stops) {
      final item = MapStopItem(
        stop: stop,
        place: stop.place ?? Place.empty(stop.placeId),
      );
      grouped.putIfAbsent(stop.dayIndex, () => []).add(item);
    }
    final days = grouped.keys.toList()..sort();
    final startDate = _itinerary?.startDate ?? DateTime.now();
    return days.map((dayIndex) {
      final dayStops = grouped[dayIndex]!
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      return DailyPlanItem(
        dayIndex: dayIndex,
        date: startDate.add(Duration(days: dayIndex - 1)),
        stops: dayStops,
      );
    }).toList();
  }

  // ─── Constructor ────────────────────────────────────────────

  InteractiveMapsViewModel({required this.itineraryId});

  // ─── Public Methods ─────────────────────────────────────────

  /// Load the itinerary, its stops and join each stop with its Place.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('[INTERACTIVE MAP] Loading itinerary: $itineraryId');
      _itinerary = await _repository.getItinerary(itineraryId);

      _temporalStatus = ItineraryStatusResolver.resolve(
        startDate: _itinerary!.startDate,
        endDate: _itinerary!.endDate,
      );
      debugPrint('[INTERACTIVE MAP] Status: ${_temporalStatus.name}');

      final rawStops = await _stopRepo.getStopsForItinerary(itineraryId);
      debugPrint('[INTERACTIVE MAP] Total stops: ${rawStops.length}');

      final joined = <ItineraryStop>[];
      for (final stop in rawStops) {
        Place? place;
        try {
          place = await _placeRepo.getPlace(stop.placeId);
        } catch (e) {
          place = null;
          debugPrint('[INTERACTIVE MAP] Failed to load place '
              '${stop.placeId}: $e');
        }
        joined.add(stop.copyWith(place: place));
      }
      _stops = joined;

      for (final dayIndex in availableDayIndices) {
        final count = _stops
            .where((s) => s.dayIndex == dayIndex)
            .length;
        debugPrint('[INTERACTIVE MAP] Day $dayIndex stops: $count');
      }

      for (final stop in _stops) {
        final place = stop.place;
        if (place != null) {
          debugPrint('[INTERACTIVE MAP] Marker: '
              'placeId=${stop.placeId} '
              'name=${place.placeName} '
              'day=${stop.dayIndex} '
              'stopOrder=${stop.stopOrder} '
              'lat=${place.placeLatitude} '
              'lng=${place.placeLongitude}');
        }
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('[INTERACTIVE MAP] Load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh from the repositories (called after a successful edit).
  Future<void> refresh() => load();

  /// Change the day filter used by the map and the daily plans.
  void selectDay(int? dayIndex) {
    if (_selectedDayFilter == dayIndex) return;
    _selectedDayFilter = dayIndex;
    notifyListeners();
  }
}
