// lib/viewmodel/ItineraryModel/add_custom_place_vm.dart
import 'package:flutter/foundation.dart';

import '../../core/services/database_manager.dart';
import '../../core/utils/friendly_messages.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/bookmark_repository_adapter.dart';
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

  final PlaceRepositoryAdapter _placeRepo;
  final CustomPlaceService _service;
  final BookmarkRepository _bookmarkRepo;

  /// Cached day contexts per 1-based day index (loaded once per day; the
  /// selection is not re-planned for unchanged context — avoids repeated
  /// database queries and repeated AI calls for the same place).
  final Map<int, List<ExistingStopContext>> _dayContextCache = {};
  final Map<String, CustomPlacePlanResult> _planCache = {};

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

  AddCustomPlaceVM({
    required this.itineraryId,
    required int dayIndex,
    required DateTime dayDate,
    this.explorationTime = 'Standard',
    this.travelPace = 'Standard',
    this.transportMode = 'walking',
    this.interests = const [],
    this.userId = '',
    PlaceRepositoryAdapter? placeRepo,
    CustomPlaceService? service,
    BookmarkRepository? bookmarkRepo,
  })  : _dayIndex = dayIndex,
        _dayDate = dayDate,
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
      final stops = await _loadDayContext(_dayIndex);
      _dayStops = stops
          .map((s) => ItineraryStop(
                stopId: 0,
                itineraryId: itineraryId,
                placeId: s.place.placeId,
                dayIndex: _dayIndex,
                stopOrder: stops.indexOf(s) + 1,
                startTime: s.startTime,
                endTime: s.endTime,
                durationMinutes: s.durationMinutes,
                travelFromPrevMinutes: s.travelFromPrevMinutes,
                stopStatus: 'PLANNED',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                place: s.place,
              ))
          .toList();
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

  /// Loads ONE day's schedule context (place joins + times), cached per day
  /// so switching days or re-selecting a place never repeats database
  /// queries. The context comes from the itinerary's persisted schedule —
  /// the traveler's confirmed edits are applied to this context by the
  /// host screen through [seedDayContext].
  Future<List<ExistingStopContext>> _loadDayContext(int dayIndex1Based) async {
    final cached = _dayContextCache[dayIndex1Based];
    if (cached != null) return cached;

    final all = await _stopRepoAll(dayIndex1Based);
    final contexts = <ExistingStopContext>[];
    for (final stop in all) {
      Place? place = stop.place;
      place ??= await _placeRepo.getPlace(stop.placeId);
      contexts.add(ExistingStopContext(
        place: place ?? Place.empty(stop.placeId),
        startTime: stop.startTime,
        endTime: stop.endTime,
        durationMinutes: stop.durationMinutes,
        travelFromPrevMinutes: stop.travelFromPrevMinutes ?? 0,
      ));
    }
    _dayContextCache[dayIndex1Based] = contexts;
    return contexts;
  }

  /// Loads the raw stops for one day (repository read, cached indirectly via
  /// [_loadDayContext] callers).
  Future<List<ItineraryStop>> _stopRepoAll(int dayIndex1Based) async {
    final stopRepo = DatabaseManager().itineraryStopRepository;
    final all = await stopRepo.getStopsForItinerary(itineraryId);
    return all
        .where((s) => s.dayIndex == dayIndex1Based)
        .toList()
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
  }

  /// Lets the host screen inject the CURRENT TEMPORARY day schedule
  /// (from EditItineraryViewModel state) so planning runs against the
  /// traveler's uncommitted edits rather than the database snapshot.
  void seedDayContext(int dayIndex1Based, List<ExistingStopContext> stops) {
    _dayContextCache[dayIndex1Based] = stops;
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
  /// Results are cached per (day, place) so re-selecting the same place
  /// never repeats the AI request or the travel-time lookups.
  Future<void> planInsertion() async {
    final place = selectedPlace;
    if (place == null) return;

    final cacheKey = '${_dayIndex}_${place.placeId}';
    final cached = _planCache[cacheKey];
    if (cached != null) {
      _planResult = cached;
      _planError = null;
      notifyListeners();
      return;
    }

    debugPrint('[ADD_CUSTOM] Planning insertion');
    _isPlanning = true;
    _planError = null;
    _planResult = null;
    notifyListeners();

    try {
      final context = _dayContextCache[_dayIndex] ?? const [];
      final result = await _service.planInsertion(
        dayIndex: dayIndex - 1, // 0-based for the pipeline
        date: dayDate,
        existingStops: context,
        newPlace: place,
        explorationTime: explorationTime,
        transportMode: transportMode,
        travelPace: travelPace,
        interests: interests,
        tripLocation: context.isNotEmpty ? context.first.place.coordinates : null,
      );
      _planResult = result;
      if (result.success) {
        _planCache[cacheKey] = result;
        debugPrint('[ADD_CUSTOM] Proposed schedule generated — '
            'insertIndex=${result.insertIndex}, usedAi=${result.usedAi}');
      } else {
        debugPrint('[ADD_CUSTOM] Validation: FAIL — '
            '${result.message ?? 'no reason'}');
      }
    } catch (e) {
      _planError = friendlyErrorMessage(
        e,
        fallback: "We couldn't plan this place right now. Please try again.",
      );
      debugPrint('[ADD_CUSTOM] Planning error: $e');
    } finally {
      _isPlanning = false;
      notifyListeners();
    }
  }

  // ─── Confirmation (temporary state — no persistence) ────────

  /// Returns the validated proposed day for the caller (EditItinerary VM)
  /// to apply to its TEMPORARY state. No database write happens here — the
  /// final itinerary is persisted later through the final Save process.
  /// Returns null when there is no validated plan (the caller shows the
  /// problem message from [planError] / `planResult.message`).
  ScheduledDay? confirmedProposedDay() {
    final plan = _planResult;
    if (plan == null || !plan.success) return null;
    return plan.proposedDay;
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
