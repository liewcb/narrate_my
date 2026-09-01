// lib/viewmodel/ItineraryModel/add_custom_place_vm.dart
import 'package:flutter/foundation.dart';

import '../../core/services/database_manager.dart';
import '../../core/utils/friendly_messages.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/bookmark_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';
import '../../model/repositories/interfaces/bookmark_repository.dart';

/// ViewModel for the "Add Location" workflow (Manage Itinerary).
///
/// Responsibilities:
///   - Load the selected day's stops (with joined Place data).
///   - Load the traveler's bookmarks (for quick selection).
///   - Search Google Places by free-text query (NOT the rejected
///     central-point/radius approach).
///   - Show search results; on selection compute distance + travel time
///     (Near/Moderate/Far) relative to the itinerary.
///   - Run AI planning + deterministic validation for the selected place.
///   - On confirmation, replace the affected day's stops through the repo.
class AddCustomPlaceVM extends ChangeNotifier {
  final String itineraryId;
  int _dayIndex; // 1-based (DB: day_index > 0)
  DateTime _dayDate;
  final String explorationTime;
  final String travelPace;
  final String transportMode;
  final List<String> interests;
  final String userId;

  final ItineraryStopRepositoryImpl _stopRepo;
  final PlaceRepositoryAdapter _placeRepo;
  final CustomPlaceService _service;
  final BookmarkRepository _bookmarkRepo;

  // ─── Existing day ────────────────────────────────────────────
  List<ItineraryStop> _dayStops = [];
  bool _isLoading = false;
  String? _loadError;

  // ─── Bookmarks ───────────────────────────────────────────────
  List<Place> _bookmarks = [];
  bool _isLoadingBookmarks = false;
  String? _bookmarksError;

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
    required int dayIndex,
    required DateTime dayDate,
    this.explorationTime = 'Standard',
    this.travelPace = 'Standard',
    this.transportMode = 'walking',
    this.interests = const [],
    this.userId = '',
    ItineraryStopRepositoryImpl? stopRepo,
    PlaceRepositoryAdapter? placeRepo,
    CustomPlaceService? service,
    BookmarkRepository? bookmarkRepo,
  })  : _dayIndex = dayIndex,
        _dayDate = dayDate,
        _stopRepo = stopRepo ?? DatabaseManager().itineraryStopRepository,
        _placeRepo = placeRepo ?? DatabaseManager().placeRepository,
        _service = service ?? CustomPlaceService(),
        _bookmarkRepo = bookmarkRepo ?? DatabaseManager().bookmarkRepository;

  // ─── Getters ────────────────────────────────────────────────

  int get dayIndex => _dayIndex;
  DateTime get dayDate => _dayDate;

  List<ItineraryStop> get dayStops => List.unmodifiable(_dayStops);
  List<Place> get dayPlaces =>
      _dayStops.map((s) => s.place ?? Place.empty(s.placeId)).toList();
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  List<Place> get bookmarks => List.unmodifiable(_bookmarks);
  bool get isLoadingBookmarks => _isLoadingBookmarks;
  String? get bookmarksError => _bookmarksError;

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
    for (final p in _bookmarks) {
      if (p.placeId == _selectedPlaceId) return p;
    }
    return null;
  }

  // ─── Load ───────────────────────────────────────────────────

  Future<void> load() async {
    debugPrint('[ADD_CUSTOM] Itinerary loaded — day $dayIndex');
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
      debugPrint('[ADD_CUSTOM] Existing stops: ${_dayStops.length}');
    } catch (e) {
      _loadError = friendlyErrorMessage(
        e,
        fallback: 'Unable to load the itinerary. Please try again.',
      );
      debugPrint('[ADD_CUSTOM] Load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switch the target day and reload its stops. Used when the traveler
  /// changes the day selector on the screen.
  Future<void> selectDay(int newDayIndex, DateTime newDayDate) async {
    if (newDayIndex == _dayIndex) return;
    debugPrint('[ADD_CUSTOM] Selected day: $newDayIndex');
    _dayIndex = newDayIndex;
    _dayDate = newDayDate;
    _clearSelection();
    await load();
  }

  /// Load the traveler's bookmarked places (only those not already in the
  /// selected day, so they are valid insertion candidates).
  Future<void> loadBookmarks() async {
    if (userId.isEmpty) {
      _bookmarks = [];
      _bookmarksError = 'No saved places available';
      notifyListeners();
      return;
    }
    _isLoadingBookmarks = true;
    _bookmarksError = null;
    notifyListeners();

    try {
      final dtos = await _bookmarkRepo.getBookmarksWithPlaces(userId);
      final usedIds = _dayStops.map((s) => s.placeId).toSet();
      _bookmarks = dtos
          .map((d) => d.place)
          .where((p) => !usedIds.contains(p.placeId))
          .toList();
      if (_bookmarks.isEmpty) {
        _bookmarksError = 'No saved places available';
      }
    } catch (e) {
      _bookmarksError = 'No saved places available';
      debugPrint('[ADD_CUSTOM] Bookmarks load failed: $e');
      _bookmarks = [];
    } finally {
      _isLoadingBookmarks = false;
      notifyListeners();
    }
  }

  // ─── Google Places text search ──────────────────────────────

  /// Search Google Places by the user's free-text query.
  Future<void> searchPlaces() async {
    if (_query.trim().isEmpty) return;
    debugPrint('[ADD_CUSTOM] Search query: $_query');

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
      debugPrint('[ADD_CUSTOM] Search results: ${_searchResults.length}');
    } catch (e) {
      _searchError = friendlyErrorMessage(
        e,
        fallback: "We couldn't search for places right now. Please try again.",
      );
      debugPrint('[ADD_CUSTOM] Search error: $e');
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
    debugPrint('[ADD_CUSTOM] Selected place: ${place.placeName} ($placeId)');

    try {
      _proximity = await _service.evaluateProximity(
        place: place,
        existingDayPlaces: dayPlaces,
        transportMode: transportMode,
      );
      debugPrint('[ADD_CUSTOM] Proximity calculated: '
          '${_proximity!.proximity} ${_proximity!.distanceFromItineraryKm.toStringAsFixed(1)}km');
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

    debugPrint('[ADD_CUSTOM] Planning insertion');
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
      debugPrint('[ADD_CUSTOM] Proposed schedule generated — '
          'success=${result.success}');
      if (!result.success) {
        debugPrint('[ADD_CUSTOM] Validation: FAIL — '
            '${result.message ?? 'no reason'}');
      } else {
        debugPrint('[ADD_CUSTOM] Validation: PASS');
      }
    } catch (e) {
      _planError = friendlyErrorMessage(
        e,
        fallback: 'Unable to plan this place. Please try again.',
      );
      debugPrint('[ADD_CUSTOM] Planning error: $e');
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
    if (plan == null || proposedDay == null || !plan.success) {
      _saveError = 'No validated plan to save.';
      return false;
    }

    debugPrint('[ADD_CUSTOM] Saving updated itinerary');
    _isSaving = true;
    _saveError = null;
    notifyListeners();

    try {
      // 1. Persist the places so stop place_id references are valid.
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
          stopOrder: i + 1, // recalculated sequentially
          startTime: s.startTime,
          endTime: s.endTime,
          durationMinutes: s.durationMinutes,
          travelFromPrevMinutes: s.travelFromPreviousMinutes,
          stopStatus: 'PLANNED',
          createdAt: now,
          updatedAt: now,
        ));
      }

      // 2. Atomically replace the day's stops (delete + batch insert).
      await _stopRepo.replaceDayStops(
        itineraryId: itineraryId,
        dayIndex: dayIndex,
        newStops: newStops,
      );

      _saved = true;
      debugPrint('[ADD_CUSTOM] Supabase update successful');
      notifyListeners();
      return true;
    } catch (e) {
      _saveError = friendlyErrorMessage(
        e,
        fallback: 'Unable to save your itinerary. Please try again.',
      );
      debugPrint('[ADD_CUSTOM] Save failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // ─── Helpers ────────────────────────────────────────────────

  void _clearSelection() {
    _query = '';
    _searchResults = [];
    _selectedPlaceId = null;
    _proximity = null;
    _planResult = null;
    _planError = null;
    _hasSearched = false;
  }
}
