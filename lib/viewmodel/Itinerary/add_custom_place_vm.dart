// lib/viewmodel/ItineraryModel/add_custom_place_vm.dart
import 'package:flutter/foundation.dart';

import '../../core/config/itinerary_constants.dart';
import '../../core/services/database_manager.dart';
import '../../core/utils/friendly_messages.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/itinerary/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary/place_repository_adapter.dart';
import '../../model/repositories/interfaces/bookmark/bookmark_repository.dart';

/// ViewModel for the "Add a Place" workflow (Manage Itinerary).
///
/// Responsibilities (day-aware — everything keys off itineraryId+dayIndex):
///   - Load the SELECTED day's stops (with joined Place data), or use the
///     host-supplied temporary day context in preview mode.
///   - Load the traveler's bookmarks (for quick selection).
///   - Search places by free-text query (Google = discovery only; every
///     result passes the same validation as recommendations).
///   - Validate every candidate BEFORE it reaches the UI:
///     identity → name → coordinates → opening hours (on the itinerary
///     DAY date, not the device date) → duplicates (stable place_id).
///   - Build "RECOMMENDED FOR THIS DAY" from the existing day stops'
///     geography + interests, never as if the day were empty.
///   - Run AI planning + deterministic validation for the selected place
///     against existingStops + newPlace (existing stops are preserved).
///   - Preview mode: return the proposed day to the host (no DB write).
///   - Database mode: replace ONLY this day's stops through the repo.
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
  final ItineraryStopRepositoryImpl _stopRepo;

  /// Cached day contexts per 1-based day index.
  final Map<int, List<ExistingStopContext>> _dayContextCache = {};
  final Map<String, CustomPlacePlanResult> _planCache = {};

  /// Preview mode: the host injected a TEMPORARY day schedule. It is the
  /// source of truth for this day — refresh must never replace it with
  /// database data.
  bool _previewMode = false;
  List<ExistingStopContext>? _previewStops;

  /// Raw DB stops for the selected day (real stopId/status preserved) —
  /// used to apply the proposed day without losing stop identity.
  List<ItineraryStop> _rawDayStops = [];

  /// Every place_id scheduled anywhere in this itinerary (whole-trip
  /// duplicate protection; the day-scoped set is a subset).
  Set<String> _itineraryUsedPlaceIds = {};

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

  // ─── Recommendations ──────────────────────────────────────────
  List<Place> _recommendations = [];
  bool _isLoadingRecommendations = false;
  String? _recommendationsError;

  // ─── Selection + proximity + planning ────────────────────────
  String? _selectedPlaceId;
  PlaceProximityInfo? _proximity;
  bool _isPlanning = false;
  bool _isSaving = false;
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
    ItineraryStopRepositoryImpl? stopRepo,
  })  : _dayIndex = dayIndex,
        _dayDate = dayDate,
        _placeRepo = placeRepo ?? DatabaseManager().placeRepository,
        _service = service ?? CustomPlaceService(),
        _bookmarkRepo =
            bookmarkRepo ?? DatabaseManager().bookmarkRepository,
        _stopRepo = stopRepo ?? DatabaseManager().itineraryStopRepository;

  // ─── Getters ────────────────────────────────────────────────

  int get dayIndex => _dayIndex;
  DateTime get dayDate => _dayDate;

  List<ItineraryStop> get dayStops => List.unmodifiable(_dayStops);
  List<Place> get dayPlaces =>
      _dayStops.map((s) => s.place ?? Place.empty(s.placeId)).toList();
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
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

  List<Place> get recommendations => List.unmodifiable(_recommendations);
  bool get isLoadingRecommendations => _isLoadingRecommendations;
  String? get recommendationsError => _recommendationsError;

  String? get selectedPlaceId => _selectedPlaceId;
  PlaceProximityInfo? get proximity => _proximity;
  bool get isPlanning => _isPlanning;
  String? get planError => _planError;
  CustomPlacePlanResult? get planResult => _planResult;
  bool get hasPlan => _planResult != null;
  bool get isPreviewMode => _previewMode;

  Place? get selectedPlace {
    for (final p in _searchResults) {
      if (p.placeId == _selectedPlaceId) return p;
    }
    for (final p in _bookmarks) {
      if (p.placeId == _selectedPlaceId) return p;
    }
    for (final p in _recommendations) {
      if (p.placeId == _selectedPlaceId) return p;
    }
    return null;
  }

  /// Place IDs already scheduled on the SELECTED DAY (stable place_id).
  Set<String> get _dayPlaceIds => _dayStops.map((s) => s.placeId).toSet();

  // ─── Load ───────────────────────────────────────────────────

  Future<void> load() async {
    debugPrint('[ADD_CUSTOM_LOAD] ── Loading Add Place day context ──');
    debugPrint('[ADD_CUSTOM_LOAD] itineraryId = $itineraryId');
    debugPrint('[ADD_CUSTOM_LOAD] dayIndex = $_dayIndex');
    debugPrint('[ADD_CUSTOM_LOAD] dayDate = $_dayDate');
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      // Whole-itinerary stop set = source of truth for day + trip dedupe.
      final allStops = await _stopRepo.getStopsForItinerary(itineraryId);
      _itineraryUsedPlaceIds = allStops.map((s) => s.placeId).toSet();

      final contexts = await _loadDayContext(_dayIndex);

      if (_previewMode) {
        debugPrint('[ADD_CUSTOM_LOAD] source = temporary dayStops '
            '(preview — DB not read for this day)');
        _rawDayStops = _contextsToStops(contexts);
      } else {
        debugPrint('[ADD_CUSTOM_LOAD] source = database');
        _rawDayStops = allStops
            .where((s) => s.dayIndex == _dayIndex)
            .toList()
          ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
        final placeById = {for (final c in contexts) c.place.placeId: c.place};
        _rawDayStops = _rawDayStops
            .map((s) => s.copyWith(place: s.place ?? placeById[s.placeId]))
            .toList();
      }

      _dayStops = _rawDayStops;

      debugPrint('[ADD_CUSTOM_DAY_CONTEXT] existing stop count = '
          '${_dayStops.length}');
      debugPrint('[ADD_CUSTOM_DAY_CONTEXT] existing place IDs = '
          '${_dayPlaceIds.join(', ')}');
    } catch (e) {
      _loadError = friendlyErrorMessage(
        e,
        fallback: 'Unable to load the itinerary. Please try again.',
      );
      debugPrint('[ADD_CUSTOM_LOAD] ERROR: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Recommendations are DAY-BASED — build them right after the day
    // context exists so the "RECOMMENDED FOR THIS DAY" section is real,
    // not an empty placeholder.
    await loadRecommendations();
  }

  List<ItineraryStop> _contextsToStops(List<ExistingStopContext> contexts) {
    return [
      for (var i = 0; i < contexts.length; i++)
        ItineraryStop(
          stopId: 0,
          itineraryId: itineraryId,
          placeId: contexts[i].place.placeId,
          dayIndex: _dayIndex,
          stopOrder: i + 1,
          startTime: contexts[i].startTime,
          endTime: contexts[i].endTime,
          durationMinutes: contexts[i].durationMinutes,
          travelFromPrevMinutes: contexts[i].travelFromPrevMinutes,
          stopStatus: 'PLANNED',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          place: contexts[i].place,
        ),
    ];
  }

  /// Loads ONE day's schedule context (place joins + times), cached per day.
  /// Preview mode always answers from the host-supplied temporary state.
  Future<List<ExistingStopContext>> _loadDayContext(int dayIndex1Based) async {
    if (_previewMode &&
        dayIndex1Based == _dayIndex &&
        _previewStops != null) {
      return _previewStops!;
    }
    final cached = _dayContextCache[dayIndex1Based];
    if (cached != null) return cached;

    final all = await _stopRepo.getStopsForItinerary(itineraryId);
    final stopsForDay = all
        .where((s) => s.dayIndex == dayIndex1Based)
        .toList()
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

    final contexts = <ExistingStopContext>[];
    for (final stop in stopsForDay) {
      Place? place = stop.place;
      if (place == null) {
        try {
          place = await _placeRepo.getPlace(stop.placeId);
        } catch (e) {
          debugPrint('[ADD_CUSTOM_LOAD] place join failed for '
              '${stop.placeId}: $e');
        }
      }
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

  /// Lets the host screen inject the CURRENT TEMPORARY day schedule.
  void seedDayContext(int dayIndex1Based, List<ExistingStopContext> stops) {
    if (dayIndex1Based == _dayIndex) {
      _previewMode = true;
      _previewStops = List.of(stops);
    }
    _dayContextCache[dayIndex1Based] = stops;
  }

  /// Switch the target day and reload its stops.
  Future<void> selectDay(int newDayIndex, DateTime newDayDate) async {
    if (newDayIndex == _dayIndex) return;
    debugPrint('[ADD_CUSTOM] Selected day: $newDayIndex');
    _dayIndex = newDayIndex;
    _dayDate = newDayDate;
    _previewMode = false;
    _previewStops = null;
    _clearSelection();
    await load();
  }

  /// Full manual refresh. Reloads the REAL data (never reuses stale
  /// day stops, place lists, recommendations or search results) and
  /// re-runs every filter. Preview mode keeps the host's (re-seeded)
  /// temporary day context as its source.
  Future<void> refreshAll() async {
    debugPrint('[ADD_CUSTOM_REFRESH] START');
    debugPrint('[ADD_CUSTOM_REFRESH] Reloading day context');
    _dayContextCache.remove(_dayIndex);
    _planCache.removeWhere((k, _) => k.startsWith('${_dayIndex}_'));
    debugPrint('[ADD_CUSTOM_REFRESH] Clearing stale search state');
    _searchResults = [];
    _searchError = null;
    _isSearching = false;
    _hasSearched = false;
    _query = '';
    _selectedPlaceId = null;
    _proximity = null;
    _planResult = null;
    _planError = null;
    notifyListeners();

    await load();

    debugPrint('[ADD_CUSTOM_REFRESH] Reloading bookmarks');
    await loadBookmarks();

    debugPrint('[ADD_CUSTOM_REFRESH] Rebuilding recommendations');
    // (load() already rebuilt them — with validation re-applied)
    debugPrint('[ADD_CUSTOM_REFRESH] Applying validation — done '
        '(recommendations=${_recommendations.length}, '
        'bookmarks=${_bookmarks.length})');
    debugPrint('[ADD_CUSTOM_REFRESH] UI state updated');
    debugPrint('[ADD_CUSTOM_REFRESH] COMPLETE');
  }

  /// Load the traveler's bookmarked places (validated + day-deduped).
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
      final raw = dtos.map((d) => d.place).toList();
      debugPrint('[ADD_CUSTOM_VALIDATE] bookmark candidates = ${raw.length}');
      _bookmarks = _validateCandidates(raw, stage: 'BOOKMARKS');
      if (_bookmarks.isEmpty) {
        _bookmarksError = 'No saved places available';
      }
    } catch (e) {
      _bookmarksError = 'No saved places available';
      debugPrint('[ADD_CUSTOM_VALIDATE] bookmarks load ERROR: $e');
      _bookmarks = [];
    } finally {
      _isLoadingBookmarks = false;
      notifyListeners();
    }
  }

  // ─── Candidate validation (single pipeline for ALL sources) ───

  /// Validates candidates before they can reach the UI or planning.
  /// Order: identity → name → coordinates → opening hours (SELECTED DAY)
  /// → duplicates (day + whole itinerary). Invalid records NEVER reach
  /// routing, scheduling or the widgets.
  List<Place> _validateCandidates(List<Place> candidates,
      {required String stage}) {
    final dayIds = _dayPlaceIds;
    final center = _dayCentroid();
    final dayOfWeek = _dayDate.weekday; // Mon=1..Sun=7 — the ITINERARY day
    final passed = <Place>[];

    for (final p in candidates) {
      // A/B. Stable identity (database place_id).
      if (p.placeId.trim().isEmpty) {
        debugPrint('[ADD_CUSTOM_VALIDATE] REJECT [$stage] placeId = '
            '<empty> — reason = invalid or missing place ID');
        continue;
      }
      // C. Name.
      if (p.placeName.trim().isEmpty) {
        debugPrint('[ADD_CUSTOM_VALIDATE] REJECT [$stage] placeId = '
            '${p.placeId} — reason = missing place name');
        continue;
      }
      // D/E. Coordinates — BEFORE any routing/distance use.
      if (!_isValidCoordinate(p.placeLatitude, isLatitude: true) ||
          !_isValidCoordinate(p.placeLongitude, isLatitude: false) ||
          (p.placeLatitude == 0 && p.placeLongitude == 0)) {
        debugPrint('[ADD_CUSTOM_COORDINATE] REJECT [$stage] placeId = '
            '${p.placeId} — reason = invalid coordinates '
            '(lat=${p.placeLatitude}, lng=${p.placeLongitude}) — not sent '
            'to any routing/distance calculation');
        continue;
      }
      // F. Opening hours ON THE SELECTED ITINERARY DATE (missing data is
      // NOT a rejection — existing project rule).
      final hours = p.openingHours;
      if (hours != null && hours.periods.isNotEmpty) {
        if (!hours.isOpenOnDay(dayOfWeek)) {
          debugPrint('[ADD_CUSTOM_OPENING_HOURS] REJECT [$stage] '
              'placeId = ${p.placeId} — reason = closed on '
              '${_dayDate.toIso8601String().substring(0, 10)} '
              '(weekday $dayOfWeek)');
          continue;
        }
      }
      // Duplicate — stable place_id against the SELECTED DAY first…
      if (dayIds.contains(p.placeId)) {
        debugPrint('[ADD_CUSTOM_DUPLICATE] REJECT [$stage] '
            'Candidate place_id=${p.placeId} rejected because it already '
            'exists in Day $_dayIndex.');
        continue;
      }
      // …then against the whole itinerary.
      if (_itineraryUsedPlaceIds.contains(p.placeId) &&
          !dayIds.contains(p.placeId)) {
        debugPrint('[ADD_CUSTOM_DUPLICATE] REJECT [$stage] '
            'Candidate place_id=${p.placeId} rejected because it is '
            'already scheduled on another day of this itinerary.');
        continue;
      }
      // Destination/day compatibility (existing range rule: within
      // maxSearchRadiusKm of the day's stop centroid, when a day exists).
      if (center != null) {
        final d = center.distanceTo(p.coordinates);
        if (d > ItineraryConstants.maxSearchRadiusKm) {
          debugPrint('[ADD_CUSTOM_VALIDATE] REJECT [$stage] placeId = '
              '${p.placeId} — reason = ${d.toStringAsFixed(1)} km from '
              "the day's stops (max "
              '${ItineraryConstants.maxSearchRadiusKm} km)');
          continue;
        }
      }
      passed.add(p);
    }
    debugPrint('[ADD_CUSTOM_VALIDATE] [$stage] ${candidates.length} '
        'candidates -> ${passed.length} valid');
    return passed;
  }

  bool _isValidCoordinate(double v, {required bool isLatitude}) {
    if (v.isNaN || v.isInfinite) return false;
    return isLatitude ? (v >= -90 && v <= 90) : (v >= -180 && v <= 180);
  }

  /// Geographic center of the selected day's stops (null when the day is
  /// empty — then no day-geography constraint can be applied).
  Coordinates? _dayCentroid() {
    double lat = 0, lng = 0;
    var n = 0;
    for (final p in dayPlaces) {
      if (!_isValidCoordinate(p.placeLatitude, isLatitude: true) ||
          !_isValidCoordinate(p.placeLongitude, isLatitude: false) ||
          (p.placeLatitude == 0 && p.placeLongitude == 0)) {
        continue;
      }
      lat += p.placeLatitude;
      lng += p.placeLongitude;
      n++;
    }
    if (n == 0) return null;
    return Coordinates(latitude: lat / n, longitude: lng / n);
  }

  // ─── Google Places text search ──────────────────────────────

  /// Search places by the user's free-text query. Google is a DISCOVERY
  /// source only — every result passes the shared validation pipeline and
  /// the day-context filters before reaching `searchResults`.
  Future<void> searchPlaces() async {
    final trimmed = _query.trim();
    debugPrint('[ADD_CUSTOM_SEARCH] Query received: "${_query}"');
    debugPrint('[ADD_CUSTOM_SEARCH] Trimmed query: "$trimmed"');

    // Empty query → NEVER call the external API; reset to the default
    // day-aware recommendation / bookmark view.
    if (trimmed.isEmpty) {
      debugPrint('[ADD_CUSTOM_SEARCH] Empty query — API not called; '
          'returning to recommendations/bookmarks');
      _searchResults = [];
      _hasSearched = false;
      _searchError = null;
      _isSearching = false;
      _clearSelection();
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchError = null;
    _searchResults = [];
    notifyListeners();

    try {
      debugPrint('[ADD_CUSTOM_SEARCH] Search started');
      final locationBias = _dayCentroid();
      final results = await _service.searchPlaces(
        query: trimmed,
        locationBias: locationBias,
      );
      debugPrint('[ADD_CUSTOM_SEARCH] Raw result count = ${results.length}');

      final dayIds = _dayPlaceIds;
      var invalidCoords = 0;
      var duplicates = 0;
      var closed = 0;
      final valid = <Place>[];
      final seen = <String>{};
      final center = locationBias;
      final dayOfWeek = _dayDate.weekday;

      for (final p in results) {
        if (!seen.add(p.placeId)) continue; // dedupe within the response
        if (p.placeId.trim().isEmpty || p.placeName.trim().isEmpty) {
          debugPrint('[ADD_CUSTOM_VALIDATE] REJECT [SEARCH] placeId = '
              '${p.placeId} — reason = invalid identity/name');
          continue;
        }
        if (!_isValidCoordinate(p.placeLatitude, isLatitude: true) ||
            !_isValidCoordinate(p.placeLongitude, isLatitude: false) ||
            (p.placeLatitude == 0 && p.placeLongitude == 0)) {
          invalidCoords++;
          debugPrint('[ADD_CUSTOM_COORDINATE] REJECT [SEARCH] placeId = '
              '${p.placeId} — reason = invalid coordinates — no route '
              'calculation attempted');
          continue;
        }
        final hours = p.openingHours;
        if (hours != null &&
            hours.periods.isNotEmpty &&
            !hours.isOpenOnDay(dayOfWeek)) {
          closed++;
          debugPrint('[ADD_CUSTOM_OPENING_HOURS] REJECT [SEARCH] placeId '
              '= ${p.placeId} — reason = closed on '
              '${_dayDate.toIso8601String().substring(0, 10)}');
          continue;
        }
        if (dayIds.contains(p.placeId) ||
            _itineraryUsedPlaceIds.contains(p.placeId)) {
          duplicates++;
          debugPrint('[ADD_CUSTOM_DUPLICATE] REJECT [SEARCH] Candidate '
              'place_id=${p.placeId} rejected because it already exists '
              'in Day $_dayIndex (or this itinerary).');
          continue;
        }
        if (center != null &&
            center.distanceTo(p.coordinates) >
                ItineraryConstants.maxSearchRadiusKm) {
          debugPrint('[ADD_CUSTOM_VALIDATE] REJECT [SEARCH] placeId = '
              '${p.placeId} — reason = outside the selected day/'
              'destination range');
          continue;
        }
        valid.add(p);
      }

      debugPrint('[ADD_CUSTOM_SEARCH] Valid result count = ${valid.length}');
      debugPrint('[ADD_CUSTOM_SEARCH] Duplicate result count = $duplicates');
      debugPrint('[ADD_CUSTOM_SEARCH] Invalid coordinate count = '
          '$invalidCoords');
      debugPrint('[ADD_CUSTOM_SEARCH] Closed-place count = $closed');
      debugPrint('[ADD_CUSTOM_SEARCH] Final result count = ${valid.length}');
      _searchResults = valid;
      debugPrint('[ADD_CUSTOM_SEARCH] Search completed');
    } catch (e, st) {
      _searchError = friendlyErrorMessage(
        e,
        fallback: "We couldn't search for places right now. Please try again.",
      );
      debugPrint('[ADD_CUSTOM_SEARCH] ERROR: $e');
      debugPrint('[ADD_CUSTOM_SEARCH] Exception: $e');
      debugPrint('[ADD_CUSTOM_SEARCH] StackTrace: $st');
      _searchResults = [];
    } finally {
      _isSearching = false;
      _hasSearched = true;
      notifyListeners();
    }
  }

  /// Clears the search view and returns to recommendations/bookmarks.
  void clearSearch() {
    _query = '';
    _searchResults = [];
    _searchError = null;
    _hasSearched = false;
    _clearSelection();
    notifyListeners();
  }

  // ─── Recommendations ──────────────────────────────────────────

  /// "RECOMMENDED FOR THIS DAY" — built around the ACTUAL existing stops
  /// of the selected day (centroid geography, interests), then run
  /// through the same validation pipeline (identity, coordinates,
  /// opening hours on the itinerary date, day duplicates, range).
  Future<void> loadRecommendations({int maxResults = 8}) async {
    final contexts = await _loadDayContext(_dayIndex);
    debugPrint('[ADD_CUSTOM_RECOMMENDATION] Day index = $_dayIndex');
    debugPrint('[ADD_CUSTOM_RECOMMENDATION] Existing stops count = '
        '${contexts.length}');
    debugPrint('[ADD_CUSTOM_RECOMMENDATION] Existing place IDs = '
        '${_dayPlaceIds.join(', ')}');

    final center = _dayCentroid();
    if (contexts.isEmpty || center == null) {
      _recommendationsError = contexts.isEmpty
          ? 'This day is empty — add or plan a stop first.'
          : 'Existing stops have no valid coordinates to build '
                'recommendations from.';
      _recommendations = [];
      notifyListeners();
      return;
    }

    _isLoadingRecommendations = true;
    _recommendationsError = null;
    notifyListeners();

    try {
      final results = await _service.recommendPlaces(
        location: center,
        interests: interests,
        explorationTime: explorationTime,
        maxResults: maxResults * 2, // over-fetch, validation prunes
      );
      debugPrint('[ADD_CUSTOM_RECOMMENDATION] Candidate count before '
          'filtering = ${results.length}');

      final validated = _validateCandidates(results, stage: 'RECOMMEND');
      debugPrint('[ADD_CUSTOM_RECOMMENDATION] Candidate count after '
          'validation = ${validated.length}');
      final deduped = _dedupeById(validated);
      debugPrint('[ADD_CUSTOM_RECOMMENDATION] Candidate count after '
          'duplicate filtering = ${deduped.length}');

      _recommendations = deduped.take(maxResults).toList();
      debugPrint('[ADD_CUSTOM_RECOMMENDATION] Final recommendation count '
          '= ${_recommendations.length}');
      if (_recommendations.isEmpty) {
        _recommendationsError =
            'No specific recommendations available for this schedule.';
      }
    } catch (e, st) {
      _recommendationsError = friendlyErrorMessage(
        e,
        fallback:
            "We couldn't get recommendations right now. Please try again.",
      );
      debugPrint('[ADD_CUSTOM_RECOMMENDATION] ERROR: $e');
      debugPrint('[ADD_CUSTOM_RECOMMENDATION] StackTrace: $st');
      _recommendations = [];
    } finally {
      _isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  List<Place> _dedupeById(List<Place> places) {
    final seen = <String>{};
    final out = <Place>[];
    for (final p in places) {
      if (seen.add(p.placeId)) {
        out.add(p);
      } else {
        debugPrint('[ADD_CUSTOM_DUPLICATE] DROPPED duplicate response '
            'place_id=${p.placeId}');
      }
    }
    return out;
  }

  // ─── Selection + proximity + planning ───────────────────────

  /// Select a candidate; VALIDATE AGAIN, then compute distance/travel
  /// info (information only) and run AI planning against
  /// existing day stops + the new place.
  Future<void> selectPlace(String placeId) async {
    _selectedPlaceId = placeId;
    _proximity = null;
    _planResult = null;
    _planError = null;
    notifyListeners();

    final place = selectedPlace;
    if (place == null) return;
    debugPrint('[ADD_CUSTOM] Selected place: ${place.placeName} ($placeId)');

    // Re-validation at selection time (never trust the list alone).
    final ok = _validateCandidates([place], stage: 'SELECT');
    if (ok.isEmpty) {
      _planError = 'This place can no longer be added. Please pick '
          'another place or refresh.';
      debugPrint('[ADD_CUSTOM_PLAN] REJECTED before planning — validation '
          'failed at selection time for place_id=$placeId');
      notifyListeners();
      return;
    }

    // Coordinates are known valid here → safe for routing/proximity.
    try {
      _proximity = await _service.evaluateProximity(
        place: place,
        existingDayPlaces: dayPlaces,
        transportMode: transportMode,
      );
      debugPrint('[ADD_CUSTOM_ROUTE] Distance from day stops = '
          '${_proximity!.distanceFromItineraryKm.toStringAsFixed(1)} km, '
          'travel ≈ ${_proximity!.travelMinutes} min — route information '
          'is context, not a data-validity judgement');
      notifyListeners();
    } catch (e) {
      debugPrint('[ADD_CUSTOM_ROUTE] proximity error: $e');
    }

    await planInsertion();
  }

  /// Run AI planning + deterministic validation for the selected place.
  /// The service receives the EXISTING DAY STOPS + the new place — the
  /// day is never rebuilt from the new place alone.
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

    debugPrint('[ADD_CUSTOM_PLAN] Planning insertion of '
        '${place.placeName} into Day $_dayIndex');
    _isPlanning = true;
    _planError = null;
    _planResult = null;
    notifyListeners();

    try {
      final context = await _loadDayContext(_dayIndex);
      debugPrint('[ADD_CUSTOM_PLAN] existing stops passed to scheduler = '
          '${context.length} (+1 new place)');
      final result = await _service.planInsertion(
        dayIndex: _dayIndex - 1, // 0-based for the pipeline
        date: _dayDate,
        existingStops: context,
        newPlace: place,
        explorationTime: explorationTime,
        transportMode: transportMode,
        travelPace: travelPace,
        interests: interests,
        tripLocation: context.isNotEmpty ? context.first.place.coordinates : null,
        itineraryUsedPlaceIds: _itineraryUsedPlaceIds,
      );
      _planResult = result;
      if (result.success) {
        _planCache[cacheKey] = result;
        final kept = context
            .where((s) => result.proposedDay!.stops
                .any((d) => d.attraction.place.placeId == s.place.placeId));
        debugPrint('[ADD_CUSTOM_PLAN] SUCCESS — proposed day holds '
            '${result.proposedDay?.stops.length} stops '
            '(existing preserved: ${kept.length}/${context.length}), '
            'insertIndex=${result.insertIndex}, usedAi=${result.usedAi}');
      } else {
        debugPrint('[ADD_CUSTOM_PLAN] FAIL — ${result.message ?? 'no reason'}');
      }
    } catch (e) {
      _planError = friendlyErrorMessage(
        e,
        fallback: "We couldn't plan this place right now. Please try again.",
      );
      debugPrint('[ADD_CUSTOM_PLAN] ERROR: $e');
    } finally {
      _isPlanning = false;
      notifyListeners();
    }
  }

  // ─── Confirmation ───────────────────────────────────────────

  /// Returns the validated proposed day for the caller.
  ScheduledDay? confirmedProposedDay() {
    final plan = _planResult;
    if (plan == null || !plan.success) return null;
    return plan.proposedDay;
  }

  /// Database mode only: persist the proposed day by replacing THIS
  /// day's stops. Existing stops keep their identity (stopId, status,
  /// destination, place) — only their times/order follow the plan, and
  /// the new place is inserted. Preview mode NEVER calls this.
  Future<bool> applyProposedDay() async {
    final plan = _planResult;
    final day = plan?.proposedDay;
    if (plan == null || !plan.success || day == null) {
      debugPrint('[ADD_CUSTOM_SAVE] REJECTED — no valid plan to apply');
      return false;
    }
    if (_previewMode) {
      debugPrint('[ADD_CUSTOM_SAVE] Skipped DB write — preview mode: the '
          'host applies the proposed day as temporary state');
      return true;
    }

    final proposedPlaceIds =
        day.stops.map((s) => s.attraction.place.placeId).toSet();
    for (final existing in _rawDayStops) {
      if (!proposedPlaceIds.contains(existing.placeId)) {
        _planError = 'The proposed plan is missing an existing stop — '
            'nothing was saved.';
        debugPrint('[ADD_CUSTOM_SAVE] ABORT — existing stop '
            '${existing.stopId} (${existing.placeId}) missing from '
            'proposed day; refusing to persist');
        return false;
      }
    }

    _isSaving = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      final byPlaceId = {for (final s in _rawDayStops) s.placeId: s};
      final newStops = <ItineraryStop>[];
      for (var i = 0; i < day.stops.length; i++) {
        final s = day.stops[i];
        final pid = s.attraction.place.placeId;
        final existing = byPlaceId[pid];
        if (existing != null) {
          // Preserve identity + status; only reseat time/order.
          newStops.add(existing.copyWith(
            stopOrder: i + 1,
            startTime: s.startTime,
            endTime: s.endTime,
            durationMinutes: s.durationMinutes,
            travelFromPrevMinutes: s.travelFromPreviousMinutes,
            updatedAt: now,
          ));
        } else {
          newStops.add(ItineraryStop(
            stopId: 0, // server-assigned
            itineraryId: itineraryId,
            placeId: pid,
            dayIndex: _dayIndex,
            stopOrder: i + 1,
            startTime: s.startTime,
            endTime: s.endTime,
            durationMinutes: s.durationMinutes,
            travelFromPrevMinutes: s.travelFromPreviousMinutes,
            stopStatus: 'PLANNED',
            createdAt: now,
            updatedAt: now,
            place: s.attraction.place,
          ));
        }
      }

      debugPrint('[ADD_CUSTOM_SAVE] Applying proposed Day $_dayIndex — '
          '${_rawDayStops.length} existing + 1 new = '
          '${newStops.length} stops');
      await _stopRepo.replaceDayStops(
        itineraryId: itineraryId,
        dayIndex: _dayIndex,
        newStops: newStops,
      );
      debugPrint('[ADD_CUSTOM_SAVE] SUCCESS — Day $_dayIndex replaced');

      _dayContextCache.remove(_dayIndex);
      _planCache.removeWhere((k, _) => k.startsWith('${_dayIndex}_'));
      _clearSelection();
      await load();
      return true;
    } catch (e) {
      _planError = friendlyErrorMessage(
        e,
        fallback: 'Unable to update the itinerary. Please try again.',
      );
      debugPrint('[ADD_CUSTOM_SAVE] FAILED: $e');
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
    // Keep recommendations; they are independent.
  }
}
