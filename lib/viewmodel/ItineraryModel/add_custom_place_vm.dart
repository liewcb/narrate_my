// lib/viewmodel/ItineraryModel/add_custom_place_vm.dart
import 'package:flutter/foundation.dart';

import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';

/// ViewModel for the "Add Location" workflow (Manage Itinerary).
///
/// Responsibilities:
///   - Load the selected day's stops (with joined Place data).
///   - Search Google Places by free-text query (NOT the rejected
///     central-point/radius approach).
///   - Show search results; on selection compute distance + travel time
///     (Near/Moderate/Far) relative to the itinerary.
///   - Run AI planning + deterministic validation for the selected place.
///   - On confirmation, replace the affected day's stops through the repo.
class AddCustomPlaceVM extends ChangeNotifier {
  final String itineraryId;
  final int dayIndex; // 1-based (DB: day_index > 0)
  final DateTime dayDate;
  final String explorationTime;
  final String travelPace;
  final String transportMode;
  final List<String> interests;

  final ItineraryStopRepositoryImpl _stopRepo;
  final PlaceRepositoryAdapter _placeRepo;
  final CustomPlaceService _service;

  // ─── Existing day ────────────────────────────────────────────
  List<ItineraryStop> _dayStops = [];
  bool _isLoading = false;
  String? _loadError;

  // ─── Text search ─────────────────────────────────────────────
  String _query = '';
  List<Place> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _hasSearched = false;

  // ─── Selection + proximity + planning ────────────────────────
  String? _selectedPlaceId;
  PlaceProximityInfo? _proximity;
  bool _isPlanning = false;
  String? _planError;
  CustomPlacePlanResult? _planResult;

  // ─── Confirmation / save ─────────────────────────────────────
  bool _isSaving = false;
  String? _saveError;
  bool _saved = false;

  AddCustomPlaceVM({
    required this.itineraryId,
    required this.dayIndex,
    required this.dayDate,
    this.explorationTime = 'Standard',
    this.travelPace = 'Standard',
    this.transportMode = 'walking',
    this.interests = const [],
    ItineraryStopRepositoryImpl? stopRepo,
    PlaceRepositoryAdapter? placeRepo,
    CustomPlaceService? service,
  })  : _stopRepo = stopRepo ?? ItineraryStopRepositoryImpl(),
        _placeRepo = placeRepo ?? PlaceRepositoryAdapter(),
        _service = service ?? CustomPlaceService();

  // ─── Getters ────────────────────────────────────────────────

  List<ItineraryStop> get dayStops => List.unmodifiable(_dayStops);
  List<Place> get dayPlaces =>
      _dayStops.map((s) => s.place ?? Place.empty(s.placeId)).toList();
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  String get query => _query;
  set query(String value) => _query = value;

  List<Place> get searchResults => List.unmodifiable(_searchResults);
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;
  bool get hasSearched => _hasSearched;

  String? get selectedPlaceId => _selectedPlaceId;
  PlaceProximityInfo? get proximity => _proximity;
  bool get isPlanning => _isPlanning;
  String? get planError => _planError;
  CustomPlacePlanResult? get planResult => _planResult;
  bool get hasPlan => _planResult != null;

  bool get isSaving => _isSaving;
  String? get saveError => _saveError;
  bool get saved => _saved;

  Place? get selectedPlace {
    for (final p in _searchResults) {
      if (p.placeId == _selectedPlaceId) return p;
    }
    return null;
  }

  // ─── Load ───────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      final all = await _stopRepo.getStopsForItinerary(itineraryId);
      final day = all.where((s) => s.dayIndex == dayIndex).toList()
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

      final joined = <ItineraryStop>[];
      for (final stop in day) {
        Place? place;
        try {
          place = await _placeRepo.getPlace(stop.placeId);
        } catch (_) {
          place = null;
        }
        joined.add(stop.copyWith(place: place));
      }
      _dayStops = joined;
    } catch (e) {
      _loadError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Google Places text search ──────────────────────────────

  /// Search Google Places by the user's free-text query.
  Future<void> searchPlaces() async {
    if (_query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    _searchResults = [];
    _selectedPlaceId = null;
    _proximity = null;
    _planResult = null;
    _hasSearched = true;
    notifyListeners();

    try {
      final locationBias =
          dayPlaces.isNotEmpty ? dayPlaces.first.coordinates : null;
      final results = await _service.searchPlaces(
        query: _query,
        locationBias: locationBias,
      );

      // Exclude places already in the itinerary.
      final usedIds = _dayStops.map((s) => s.placeId).toSet();
      _searchResults = results
          .where((p) => !usedIds.contains(p.placeId))
          .toList();
    } catch (e) {
      _searchError = e.toString();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  // ─── Selection + proximity + planning ───────────────────────

  /// Select a search result; compute distance/travel info and run AI
  /// planning + deterministic validation.
  Future<void> selectPlace(String placeId) async {
    _selectedPlaceId = placeId;
    _proximity = null;
    _planResult = null;
    _planError = null;
    notifyListeners();

    final place = selectedPlace;
    if (place == null) return;

    try {
      _proximity = await _service.evaluateProximity(
        place: place,
        existingDayPlaces: dayPlaces,
        transportMode: transportMode,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[AddCustomPlace] proximity error: $e');
    }

    await planInsertion();
  }

  /// Run AI planning + deterministic validation for the selected place.
  Future<void> planInsertion() async {
    final place = selectedPlace;
    if (place == null) return;

    _isPlanning = true;
    _planError = null;
    _planResult = null;
    notifyListeners();

    try {
      final result = await _service.planInsertion(
        dayIndex: dayIndex - 1, // 0-based for the pipeline
        date: dayDate,
        existingDayPlaces: dayPlaces,
        newPlace: place,
        explorationTime: explorationTime,
        transportMode: transportMode,
        travelPace: travelPace,
        interests: interests,
        tripLocation: dayPlaces.isNotEmpty ? dayPlaces.first.coordinates : null,
      );
      _planResult = result;
    } catch (e) {
      _planError = e.toString();
    } finally {
      _isPlanning = false;
      notifyListeners();
    }
  }

  // ─── Confirmation / save ────────────────────────────────────

  /// Replace the affected day with the validated schedule and persist.
  Future<bool> confirmAndSave() async {
    final plan = _planResult;
    final proposedDay = plan?.proposedDay;
    if (plan == null || proposedDay == null) return false;

    _isSaving = true;
    _saveError = null;
    notifyListeners();

    try {
      // 1. Delete the existing day's stops.
      for (final stop in _dayStops) {
        if (stop.stopId != 0) {
          await _stopRepo.deleteStop(stop.stopId);
        }
      }

      // 2. Rebuild the day's stops from the validated schedule.
      final now = DateTime.now();
      final newStops = <ItineraryStop>[];
      for (var i = 0; i < proposedDay.stops.length; i++) {
        final s = proposedDay.stops[i];
        final place = s.attraction.place;
        try {
          await _placeRepo.savePlace(place);
        } catch (e) {
          debugPrint('[AddCustomPlace] place save failed: $e');
        }
        newStops.add(ItineraryStop(
          stopId: 0,
          itineraryId: itineraryId,
          placeId: place.placeId,
          dayIndex: dayIndex, // 1-based
          stopOrder: i + 1, // 1-based
          startTime: s.startTime,
          endTime: s.endTime,
          durationMinutes: s.durationMinutes,
          travelFromPrevMinutes: null,
          stopStatus: 'PLANNED',
          createdAt: now,
          updatedAt: now,
        ));
      }

      // 3. Persist the new stops.
      for (final stop in newStops) {
        await _stopRepo.addStop(stop);
      }

      _saved = true;
      notifyListeners();
      return true;
    } catch (e) {
      _saveError = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
