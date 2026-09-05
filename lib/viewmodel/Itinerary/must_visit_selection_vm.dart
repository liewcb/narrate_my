// lib/viewmodel/ItineraryModel/must_visit_selection_vm.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/config/api_keys.dart';
import '../../core/config/itinerary_constants.dart';
import '../../core/services/database_manager.dart';
import '../../core/services/google_maps_service.dart';
import '../../model/business_logic/itinerary_service/candidate_retrieval_service.dart';
import '../../model/business_logic/itinerary_service/candidate_retrieval_service.dart'
    as hotspot_svc;
import '../../model/entities/coordinates.dart';
import '../../model/entities/destination.dart';
import '../../model/entities/destination_hotspot.dart';
import '../../model/entities/place.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/repositories/interfaces/bookmark_repository.dart';
import '../../model/repositories/interfaces/destination_repository.dart';

/// Outcome of a must-visit selection attempt. The UI only displays the
/// result — every validation rule lives in this ViewModel.
enum MustVisitSelectionStatus { added, warning, rejected }

class MustVisitSelectionResult {
  final MustVisitSelectionStatus status;
  final String message;

  const MustVisitSelectionResult._(this.status, this.message);

  factory MustVisitSelectionResult.added() =>
      const MustVisitSelectionResult._(MustVisitSelectionStatus.added, '');

  factory MustVisitSelectionResult.warning(String message) =>
      MustVisitSelectionResult._(MustVisitSelectionStatus.warning, message);

  factory MustVisitSelectionResult.rejected(String message) =>
      MustVisitSelectionResult._(MustVisitSelectionStatus.rejected, message);
}

/// UI model for a place shown in the Step 3 wizard.
class WizardPlace {
  final String placeId;
  final String name;
  final String type;
  final IconData typeIcon;
  final double rating;
  final String? imageUrl;
  final String travelTime;
  final IconData travelIcon;
  final String? duration;
  final String location;
  final bool? isOpenNow;
  final String? openHours;
  final bool isEnabled;
  final double? distanceKm;
  final String? distanceStatus;
  final String? destinationId;
  final String? hotspotId;

  const WizardPlace({
    required this.placeId,
    required this.name,
    required this.type,
    required this.typeIcon,
    required this.rating,
    this.imageUrl,
    this.travelTime = 'N/A',
    this.travelIcon = Icons.directions_walk_rounded,
    this.duration,
    this.location = '',
    this.isOpenNow,
    this.openHours,
    this.isEnabled = true,
    this.distanceKm,
    this.distanceStatus,
    this.destinationId,
    this.hotspotId,
  });

  bool get isOutsideHotspot =>
      distanceStatus != null && distanceStatus != 'WITHIN_HOTSPOT';

  WizardPlace copyWith({
    String? placeId,
    String? name,
    String? type,
    IconData? typeIcon,
    double? rating,
    String? imageUrl,
    String? travelTime,
    IconData? travelIcon,
    String? duration,
    String? location,
    bool? isOpenNow,
    String? openHours,
    bool? isEnabled,
    double? distanceKm,
    String? distanceStatus,
    String? destinationId,
    String? hotspotId,
  }) {
    return WizardPlace(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      type: type ?? this.type,
      typeIcon: typeIcon ?? this.typeIcon,
      rating: rating ?? this.rating,
      imageUrl: imageUrl ?? this.imageUrl,
      travelTime: travelTime ?? this.travelTime,
      travelIcon: travelIcon ?? this.travelIcon,
      duration: duration ?? this.duration,
      location: location ?? this.location,
      isOpenNow: isOpenNow ?? this.isOpenNow,
      openHours: openHours ?? this.openHours,
      isEnabled: isEnabled ?? this.isEnabled,
      distanceKm: distanceKm ?? this.distanceKm,
      distanceStatus: distanceStatus ?? this.distanceStatus,
      destinationId: destinationId ?? this.destinationId,
      hotspotId: hotspotId ?? this.hotspotId,
    );
  }
}

/// ViewModel for Step 3 (Must-go attractions).
class Step3AddPlaceVM extends ChangeNotifier {
  TripDraft draft;
  final GoogleMapsService _mapsService;
  final DestinationRepository _destinationRepository;
  final BookmarkRepository _bookmarkRepository;
  final CandidateRetrievalService _candidateService;

  // ─── UI State ──────────────────────────────────────────────
  int selectedTab = 0; // 0: Bookmarks, 1: Search Maps
  String searchQuery = '';

  // ─── Bookmarks ──────────────────────────────────────────────
  List<WizardPlace> _bookmarks = [];
  List<WizardPlace> get bookmarks => List.unmodifiable(_bookmarks);
  bool isLoadingBookmarks = false;
  String? bookmarksError;

  // ─── Search Maps state ──────────────────────────────────────
  List<WizardPlace> _defaultPlaces = [];
  List<WizardPlace> _searchResults = [];
  bool isLoading = false;
  String? errorMessage;

  // ─── Selected hotspot ────────────────────────────────────────
  DestinationHotspot? _selectedHotspot;

  // ─── Pagination ─────────────────────────────────────────────
  static const int _pageSize = 10;
  int _currentPage = 0;
  bool isLoadingMore = false;

  // ─── Shared selection ───────────────────────────────────────
  /// REQ_MV_05 — a traveler may select at most 3 must-visit places.
  static const int maxMustVisits = 3;

  final List<String> _mustVisitPlaceIds = [];
  final Map<String, String> _mustVisitNameById = {};
  final Map<String, MustVisitPlaceInfo> _mustVisitMeta = {};

  /// Full Place records (coordinates, types, identity) keyed by stable
  /// place_id — used for must-visit validation on selection.
  final Map<String, Place> _placeById = {};

  /// Best-hotspot cache per destination_id (distance validation).
  final Map<String, DestinationHotspot?> _hotspotCache = {};

  /// Non-travel categories never accepted as must-visits (REQ_MV_11).
  /// Mirrors CandidateRetrievalService's hard-banned types.
  static const List<String> _bannedMustVisitTypes = [
    'lodging',
    'hotel',
    'real_estate_agency',
    'lawyer',
    'spa',
  ];

  // ─── Destination cache ──────────────────────────────────────
  List<Destination> _cachedSelectedDestinations = [];
  String user_id = "";

  // ─── Static Google Places type maps ────────────────────────
  static const Map<String, List<String>> interestToGoogleTypes = {
    'History & Culture': [
      'museum',
      'art_gallery',
      'place_of_worship',
      'hindu_temple',
      'church',
      'mosque',
      'synagogue',
    ],
    'Nature & Outdoors': [
      'park',
      'national_park',
      'natural_feature',
      'campground',
      'zoo',
      'aquarium',
      'botanical_garden',
      'hiking_area',
    ],
    'Food & Culinary': [
      'restaurant',
      'cafe',
      'bakery',
      'meal_takeaway',
      'meal_delivery',
      'bar',
    ],
    'Thrills & Entertainment': [
      'amusement_park',
      'stadium',
      'bowling_alley',
      'tourist_attraction',
      'movie_theater',
    ],
    'Shopping & Markets': [
      'shopping_mall',
      'clothing_store',
      'department_store',
      'book_store',
      'jewelry_store',
      'supermarket',
      'convenience_store',
    ],
    'Nightlife & Social': [
      'night_club',
      'casino',
      'liquor_store',
      'bar',
      'movie_theater',
    ],
  };

  static const Map<String, String> attractionTypesToSubCategory = {
    'zoo': 'Wildlife & Animals',
    'aquarium': 'Wildlife & Animals',
    'amusement_park': 'Theme Parks',
    'theme_park': 'Theme Parks',
    'water_park': 'Theme Parks',
    'bowling_alley': 'Games & Bowling',
    'stadium': 'Sports & Events',
    'museum': 'Museums',
    'art_gallery': 'Art Galleries',
    'tourist_attraction': 'Landmarks',
    'place_of_worship': 'Historical Sites',
    'church': 'Historical Sites',
    'hindu_temple': 'Historical Sites',
    'mosque': 'Historical Sites',
    'synagogue': 'Historical Sites',
    'park': 'Parks & Gardens',
    'garden': 'Parks & Gardens',
    'natural_feature': 'Natural Wonders',
    'forest': 'Natural Wonders',
    'beach': 'Natural Wonders',
    'movie_theater': 'Cinemas',
    'shopping_mall': 'Shopping & Retail',
    'clothing_store': 'Shopping & Retail',
    'department_store': 'Shopping & Retail',
    'book_store': 'Shopping & Retail',
    'jewelry_store': 'Shopping & Retail',
    'market': 'Shopping & Retail',
    'night_club': 'Nightlife',
    'casino': 'Nightlife',
    'liquor_store': 'Nightlife',
    'wine_bar': 'Nightlife',
  };

  static const Map<String, String> foodTypesToSubCategory = {
    'cafe': 'Coffee & Cafe',
    'bakery': 'Bakery & Sweets',
    'restaurant': 'Restaurant',
    'meal_takeaway': 'Quick Bites',
    'meal_delivery': 'Delivery',
    'bar': 'Bars & Pubs',
    'night_club': 'Nightlife & Drinks',
    'wine_bar': 'Wine Bar',
  };

  Step3AddPlaceVM(
      this.draft, {
        userId,
        GoogleMapsService? mapsService,
        DestinationRepository? destinationRepository,
        BookmarkRepository? bookmarkRepository,
        CandidateRetrievalService? candidateService,
      })  : _mapsService = mapsService ?? GoogleMapsService(),
        _destinationRepository =
            destinationRepository ?? DatabaseManager().destinationRepository,
        _bookmarkRepository =
            bookmarkRepository ?? DatabaseManager().bookmarkRepository,
        user_id = userId,
        _candidateService =
            candidateService ?? CandidateRetrievalService() {
    _ensureSelectedDestinations();
    // Restore must-visit selections from the draft so BACK
    // navigation (Step 4 → Step 3) keeps progress.
    for (final id in draft.mustVisitPlaceIds) {
      if (id.isEmpty || _mustVisitPlaceIds.contains(id)) continue;
      _mustVisitPlaceIds.add(id);
      final meta = draft.mustVisitPlaceInfo[id];
      if (meta != null) {
        _mustVisitMeta[id] = meta;
        _mustVisitNameById[id] = meta.placeName;
      } else {
        _mustVisitNameById[id] = id;
      }
    }
    loadBookmarks();
  }

  // ---------- Getters ----------
  List<WizardPlace> get availablePlaces {
    if (selectedTab == 1) {
      return searchQuery.trim().isEmpty ? _defaultPlaces : _searchResults;
    }
    return _filteredBookmarks;
  }

  List<WizardPlace> get _filteredBookmarks {
    if (searchQuery.isEmpty) return _bookmarks;
    final q = searchQuery.toLowerCase();
    return _bookmarks
        .where((p) =>
    p.name.toLowerCase().contains(q) ||
        p.type.toLowerCase().contains(q))
        .toList();
  }

  List<WizardPlace> get pagedDefaultPlaces =>
      _defaultPlaces.take((_currentPage + 1) * _pageSize).toList();

  bool get hasMoreDefaultPlaces =>
      pagedDefaultPlaces.length < _defaultPlaces.length;

  List<String> get mustVisitPlaces =>
      _mustVisitPlaceIds.map((id) => _mustVisitNameById[id] ?? id).toList();
  List<String> get mustVisitPlaceIds => List.unmodifiable(_mustVisitPlaceIds);
  Map<String, MustVisitPlaceInfo> get mustVisitPlaceInfo =>
      Map.unmodifiable(_mustVisitMeta);

  /// (placeId, displayName) pairs for the selected chips (REQ_MV_07).
  List<(String, String)> get mustVisitEntries => [
    for (final id in _mustVisitPlaceIds) (id, _mustVisitNameById[id] ?? id),
  ];

  DestinationHotspot? get selectedHotspot => _selectedHotspot;
  double? get selectedHotspotRadiusKm => _selectedHotspot?.suggestedRadiusKm;
  bool get isSelectionLimitReached => _mustVisitPlaceIds.length >= maxMustVisits;

  // ---------- Init / Load ----------
  Future<void> _ensureSelectedDestinations() async {
    try {
      _cachedSelectedDestinations = await _resolveSelectedDestinations();
    } catch (e) {
      debugPrint('Failed to resolve destinations: $e');
      _cachedSelectedDestinations = [];
    }
  }

  Future<void> loadBookmarks() async {
    isLoadingBookmarks = true;
    bookmarksError = null;
    notifyListeners();

    try {
      await _ensureSelectedDestinations();
      // REQ_MV_01 — the repository query is scoped to the authenticated
      // user's ID, so only that traveler's bookmarks are ever returned.
      final dtos = await _bookmarkRepository.getBookmarksWithPlaces(user_id);
      final mapped = dtos.map((dto) {
        try {
          return _toWizardPlace(dto.place, '').copyWith(isEnabled: true);
        } catch (e) {
          return null;
        }
      }).where((w) => w != null).cast<WizardPlace>().toList();

      // REQ_MV_02 — only destination-relevant bookmarks are selectable.
      final filtered = mapped.where((w) => _belongsToAnySelectedDestinationByPlace(w)).toList();
      if (filtered.isEmpty && mapped.isNotEmpty) {
        _bookmarks = mapped.map((w) => w.copyWith(isEnabled: false)).toList();
      } else {
        _bookmarks = filtered.isEmpty ? mapped : filtered;
      }
    } catch (e) {
      bookmarksError = 'Could not load bookmarks.';
      _bookmarks = [];
    } finally {
      isLoadingBookmarks = false;
      notifyListeners();
    }
  }

  /// REQ_MV_02 — a bookmark is destination-compatible when its underlying
  /// Place belongs to one of the selected destinations (coordinates first,
  /// name match as fallback). When destinations cannot be resolved the check
  /// is skipped so a transient database failure cannot hide every bookmark;
  /// selection-time validation re-applies the rule whenever destinations are
  /// known.
  bool _belongsToAnySelectedDestinationByPlace(WizardPlace w) {
    if (_cachedSelectedDestinations.isEmpty) return true;
    final place = _placeById[w.placeId];
    if (place == null) return false;
    return _belongsToAnySelectedDestination(place);
  }

  bool _belongsToAnySelectedDestination(Place place) {
    if (_cachedSelectedDestinations.isEmpty) return false;
    for (final dest in _cachedSelectedDestinations) {
      final destCoords = (dest.latitude != null && dest.longitude != null)
          ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
          : null;
      if (destCoords != null) {
        final distance = destCoords.distanceTo(place.coordinates);
        if (distance <= ItineraryConstants.maxSearchRadiusKm) return true;
      }
      final combined = (place.placeAddress + ' ' + place.placeName).toLowerCase();
      if (combined.contains(dest.destinationName.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  void setTab(int index) {
    selectedTab = index;
    errorMessage = null;
    if (index == 1 && _defaultPlaces.isEmpty && !isLoading) {
      loadDefaultPlaces();
    } else {
      notifyListeners();
    }
  }

  void searchPlaces(String query) {
    searchQuery = query;
    if (selectedTab == 0) {
      notifyListeners();
      return;
    }
    _searchMaps(query);
  }

  /// Removes a selected must-visit (REQ_MV_07): updates the selected place
  /// IDs, metadata and the TripDraft, then refreshes the UI state.
  void removeMustVisit(String placeId) {
    _mustVisitPlaceIds.remove(placeId);
    _mustVisitNameById.remove(placeId);
    _mustVisitMeta.remove(placeId);
    _syncDraft();
    notifyListeners();
  }

  void _syncDraft() {
    draft = draft.copyWith(
      mustVisitPlaceIds: List.of(_mustVisitPlaceIds),
      mustVisitPlaceInfo: Map.of(_mustVisitMeta),
    );
  }

  /// Adds or removes a place. The [confirmOutsideHotspot] flag is the UI's
  /// answer to the OUTSIDE_HOTSPOT warning — it never bypasses any other
  /// validation rule (§19).
  Future<MustVisitSelectionResult> togglePlace(
    String placeId, {
    String? placeName,
    required String source,
    bool confirmOutsideHotspot = false,
  }) async {
    // Toggle-off path: the place is already selected → remove it.
    if (_mustVisitPlaceIds.contains(placeId)) {
      removeMustVisit(placeId);
      return MustVisitSelectionResult.added();
    }

    // Toggle-on path — full validation chain.
    final result = await _validateAndAdd(
      placeId: placeId,
      placeName: placeName,
      source: source,
      confirmOutsideHotspot: confirmOutsideHotspot,
    );
    notifyListeners();
    return result;
  }

  Future<MustVisitSelectionResult> _validateAndAdd({
    required String placeId,
    String? placeName,
    required String source,
    required bool confirmOutsideHotspot,
  }) async {
    // ── REQ_MV_08 — valid, stable place identity (never the name). ──
    if (placeId.trim().isEmpty) {
      return MustVisitSelectionResult.rejected(
        'This place does not have a valid place ID and cannot be added.',
      );
    }
    final id = placeId.trim();

    // ── REQ_MV_05 / REQ_MV_06 — maximum 3 must-visit places. ──
    if (_mustVisitPlaceIds.length >= maxMustVisits) {
      return MustVisitSelectionResult.rejected(
        'You can select a maximum of 3 must-visit places.',
      );
    }

    final place = _placeById[id];

    // ── REQ_MV_09 — valid coordinates. ──
    if (place == null ||
        place.placeLatitude == 0.0 && place.placeLongitude == 0.0 ||
        place.placeLatitude < -90 ||
        place.placeLatitude > 90 ||
        place.placeLongitude < -180 ||
        place.placeLongitude > 180) {
      return MustVisitSelectionResult.rejected(
        'This place does not have valid coordinates and cannot be added.',
      );
    }

    // ── REQ_MV_12 — duplicate prevention by stable place_id. ──
    if (_mustVisitPlaceIds.contains(id)) {
      return MustVisitSelectionResult.rejected(
        'This place has already been selected.',
      );
    }

    // ── REQ_MV_11 — valid place category (must-visits are attractions /
    // places of interest, never clearly non-travel categories). Mirrors the
    // candidate retrieval service's banned types; food categories stay
    // allowed because the existing pipeline explicitly supports them. ──
    if (place.placeTypes.any(_bannedMustVisitTypes.contains)) {
      return MustVisitSelectionResult.rejected(
        'This place is not a valid attraction and cannot be added as a '
        'must-visit.',
      );
    }

    // ── REQ_MV_10 — destination compatibility (geographic distance). ──
    if (_cachedSelectedDestinations.isNotEmpty &&
        !_belongsToAnySelectedDestination(place)) {
      return MustVisitSelectionResult.rejected(
        'This place cannot be added because its location is outside your '
        'selected destinations.',
      );
    }

    // ── REQ_MV_13 — hotspot distance validation. ──
    final warning = await _hotspotWarningFor(place);
    if (warning != null && !confirmOutsideHotspot) {
      return MustVisitSelectionResult.warning(warning);
    }

    // ── All validation passed → preserve stable identity + metadata. ──
    _mustVisitPlaceIds.add(id);
    _mustVisitNameById[id] = place.placeName.isNotEmpty
        ? place.placeName
        : (placeName ?? id);
    _mustVisitMeta[id] = MustVisitPlaceInfo(
      placeId: id,
      placeName: place.placeName,
      destinationId: place.destinationId ??
          _destinationIdForPlace(place),
      source: source,
      latitude: place.placeLatitude,
      longitude: place.placeLongitude,
    );
    _syncDraft();
    return MustVisitSelectionResult.added();
  }

  /// OUTSIDE_HOTSPOT → confirmation message; WITHIN_HOTSPOT / FAR → null.
  /// FAR_FROM_DESTINATION is rejected earlier by destination compatibility;
  /// a null here means "add normally".
  Future<String?> _hotspotWarningFor(Place place) async {
    if (_cachedSelectedDestinations.isEmpty) return null;
    for (final dest in _cachedSelectedDestinations) {
      final destCoords = (dest.latitude != null && dest.longitude != null)
          ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
          : null;
      if (destCoords == null) continue;
      final distanceKm = _mapsService.distanceKm(destCoords, place.coordinates);
      if (distanceKm <= ItineraryConstants.maxSearchRadiusKm) {
        // Inside the destination's travel area — warn only when the place
        // sits beyond the destination hotspot's suggested radius.
        final hotspot = _selectedHotspot ??
            await _hotspotForDestination(dest.destinationId);
        if (hotspot != null) {
          final hotspotDistance = _mapsService.distanceKm(
            Coordinates(
              latitude: hotspot.latitude,
              longitude: hotspot.longitude,
            ),
            place.coordinates,
          );
          final status = hotspot_svc.classifyHotspotDistance(
            hotspotDistance,
            hotspot.suggestedRadiusKm,
          );
          if (status == HotspotDistanceStatus.outsideHotspot) {
            return 'This place is outside the recommended area for this '
                'destination. Do you still want to add it as a must-visit?';
          }
        }
        return null;
      }
    }
    return null;
  }

  Future<DestinationHotspot?> _hotspotForDestination(String destinationId) async {
    if (_hotspotCache.containsKey(destinationId)) {
      return _hotspotCache[destinationId];
    }
    DestinationHotspot? hotspot;
    try {
      final dest = _cachedSelectedDestinations.firstWhere(
        (d) => d.destinationId == destinationId,
      );
      hotspot = await _candidateService.selectBestHotspot(
        destinationName: dest.destinationName,
        destinationId: dest.destinationId,
        interests: draft.interests.toList(),
      );
    } catch (e) {
      debugPrint('Hotspot resolution failed: $e');
    }
    _hotspotCache[destinationId] = hotspot;
    return hotspot;
  }

  String? _destinationIdForPlace(Place place) {
    for (final dest in _cachedSelectedDestinations) {
      final destCoords = (dest.latitude != null && dest.longitude != null)
          ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
          : null;
      if (destCoords != null &&
          destCoords.distanceTo(place.coordinates) <=
              ItineraryConstants.maxSearchRadiusKm) {
        return dest.destinationId;
      }
    }
    return null;
  }

  bool isPlaceAdded(String placeId) => _mustVisitPlaceIds.contains(placeId);

  /// Exposes the underlying Place record for a candidate so the UI can hand
  /// full validation data (coordinates, types) back to the ViewModel.
  Place? placeById(String placeId) => _placeById[placeId];

  void registerPlace(Place place) {
    if (place.placeId.isEmpty) return;
    _placeById[place.placeId] = place;
  }

  TripDraft buildDraft() {
    _syncDraft();
    return draft;
  }

  // ---------- Search Maps – Default Places ----------
  Future<void> loadDefaultPlaces() async {
    debugPrint('🚀 loadDefaultPlaces()');
    isLoading = true;
    errorMessage = null;
    _currentPage = 0;
    notifyListeners();

    try {
      final selected = await _resolveSelectedDestinations();
      if (selected.isEmpty) {
        errorMessage = 'No destinations selected. Go back to Step 1.';
        _defaultPlaces = [];
        return;
      }

      // ---- Build type list from user interests ----
      final interests = draft.interests;
      final allTypes = <String>[];
      for (final interest in interests) {
        final types = interestToGoogleTypes[interest];
        if (types != null) allTypes.addAll(types);
      }
      final uniqueTypes = allTypes.toSet().toList();
      debugPrint('🔍 Google Places types: $uniqueTypes');

      final all = <WizardPlace>[];
      final seenIds = <String>{};

      for (final dest in selected) {
        final hotspot = await _candidateService.selectBestHotspot(
          destinationName: dest.destinationName,
          destinationId: dest.destinationId,
          interests: draft.interests.toList(),
        );
        _selectedHotspot = hotspot;

        if (hotspot != null) {
          final radiusMeters = (hotspot.suggestedRadiusKm * 1000).toDouble();
          final places = await _mapsService.searchNearbyPlaces(
            latitude: hotspot.latitude,
            longitude: hotspot.longitude,
            radius: radiusMeters,
            types: uniqueTypes, // dynamic types
          );
          for (final place in places) {
            if (!seenIds.add(place.placeId)) continue;
            all.add(_toWizardPlace(
              place,
              dest.destinationName,
              destinationId: hotspot.destinationId,
              hotspotId: hotspot.id,
            ));
          }
        } else {
          // Fallback: use destination centre
          final hasCoords = dest.latitude != null && dest.longitude != null;
          if (!hasCoords) continue;
          final places = await _mapsService.searchNearbyPlaces(
            latitude: dest.latitude!,
            longitude: dest.longitude!,
            radius: 10000,
            types: uniqueTypes,
          );
          final destCoords = Coordinates(
            latitude: dest.latitude!,
            longitude: dest.longitude!,
          );
          for (final place in places) {
            if (!_belongsToDestination(place, dest, destCoords)) continue;
            if (!seenIds.add(place.placeId)) continue;
            all.add(_toWizardPlace(place, dest.destinationName));
          }
        }
      }

      all.sort((a, b) => b.rating.compareTo(a.rating));
      _defaultPlaces = all;
      notifyListeners();

      // ---- Fetch AI durations in background ----
      _fetchAndUpdateDurations();

    } catch (e) {
      debugPrint('❌ loadDefaultPlaces error: $e');
      errorMessage = 'Could not load places. Check your connection.';
      _defaultPlaces = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMorePlaces() async {
    if (isLoadingMore || !hasMoreDefaultPlaces) return;
    isLoadingMore = true;
    notifyListeners();
    _currentPage++;
    notifyListeners();
    isLoadingMore = false;
  }

  // ---------- Search Maps – Text Search ----------
  Future<void> _searchMaps(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      isLoading = false;
      errorMessage = null;
      notifyListeners();
      return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final selected = await _resolveSelectedDestinations();
      if (selected.isEmpty) {
        errorMessage = 'No destinations selected.';
        _searchResults = [];
        return;
      }

      final interests = draft.interests;
      final allTypes = <String>[];
      for (final interest in interests) {
        final types = interestToGoogleTypes[interest];
        if (types != null) allTypes.addAll(types);
      }
      final uniqueTypes = allTypes.toSet().toList();

      final all = <WizardPlace>[];
      final seenIds = <String>{};

      for (final dest in selected) {
        final hotspot = await _candidateService.selectBestHotspot(
          destinationName: dest.destinationName,
          destinationId: dest.destinationId,
          interests: draft.interests.toList(),
        );
        _selectedHotspot = hotspot;

        final coords = dest.latitude != null && dest.longitude != null
            ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
            : null;

        final localizedQuery = coords != null
            ? query
            : '$query, ${dest.destinationName}';

        final results = await _mapsService.searchTextPlaces(
          query: localizedQuery,
          latitude: coords?.latitude,
          longitude: coords?.longitude,
        );

        // Filter results by the relevant types
        final filteredResults = results.where((place) {
          final placeTypes = place.placeTypes ?? [];
          return placeTypes.any((t) => uniqueTypes.contains(t));
        }).toList();

        for (final place in filteredResults) {
          if (!seenIds.add(place.placeId)) continue;

          double? distanceKm;
          String? distanceStatus;
          if (hotspot != null) {
            final hotspotCoords = Coordinates(
              latitude: hotspot.latitude,
              longitude: hotspot.longitude,
            );
            distanceKm = _mapsService.distanceKm(
              hotspotCoords,
              place.coordinates,
            );
            distanceStatus = classifyHotspotDistance(
              distanceKm,
              hotspot.suggestedRadiusKm,
            ).label; // ✅ now works
          }

          all.add(_toWizardPlace(
            place,
            dest.destinationName,
            distanceKm: distanceKm,
            distanceStatus: distanceStatus,
            destinationId: hotspot?.destinationId,
            hotspotId: hotspot?.id,
          ));
        }
      }

      _searchResults = all;
      notifyListeners();

      _fetchAndUpdateSearchDurations();

    } catch (e) {
      debugPrint('❌ _searchMaps error: $e');
      errorMessage = 'Could not search places. Check your connection.';
      _searchResults = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ---------- AI Duration Helpers ----------
  Future<String> _fetchDurationFromAI(String placeName, String placeType, String location) async {
    // 🔥 Replace with real Deepseek API call.
    await Future.delayed(const Duration(milliseconds: 300));
    final type = placeType.toLowerCase();
    if (type.contains('museum') || type.contains('art_gallery')) return '120 min';
    if (type.contains('restaurant') || type.contains('cafe')) return '60 min';
    if (type.contains('park') || type.contains('natural_feature')) return '90 min';
    if (type.contains('shopping') || type.contains('mall')) return '90 min';
    if (type.contains('attraction') || type.contains('landmark')) return '75 min';
    return '60 min';
  }

  Future<void> _fetchAndUpdateDurations() async {
    if (_defaultPlaces.isEmpty) return;
    final futures = _defaultPlaces.map((place) =>
        _fetchDurationFromAI(place.name, place.type, place.location));
    try {
      final durations = await Future.wait(futures);
      for (int i = 0; i < _defaultPlaces.length; i++) {
        _defaultPlaces[i] = _defaultPlaces[i].copyWith(
          duration: durations[i],
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to fetch AI durations: $e');
    }
  }

  Future<void> _fetchAndUpdateSearchDurations() async {
    if (_searchResults.isEmpty) return;
    final futures = _searchResults.map((place) =>
        _fetchDurationFromAI(place.name, place.type, place.location));
    try {
      final durations = await Future.wait(futures);
      for (int i = 0; i < _searchResults.length; i++) {
        _searchResults[i] = _searchResults[i].copyWith(
          duration: durations[i],
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to fetch AI durations for search results: $e');
    }
  }

  // ---------- Destination Helpers ----------
  Future<List<Destination>> _resolveSelectedDestinations() async {
    if (draft.destinations.isEmpty) return [];
    final all = await _destinationRepository.getAllDestinations();
    final names = draft.destinationNames.map((n) => n.trim().toLowerCase()).toSet();
    return all.where((d) => names.contains(d.destinationName.trim().toLowerCase())).toList();
  }

  bool _belongsToDestination(
      Place place,
      Destination dest,
      Coordinates? destCoords,
      ) {
    const maxKm = 50.0;
    if (destCoords != null) {
      final d = _mapsService.distanceKm(destCoords, place.coordinates);
      if (d <= maxKm) return true;
    }
    if (dest.destinationName.isNotEmpty) {
      final address = (place.address + ' ' + place.name).toLowerCase();
      if (address.contains(dest.destinationName.toLowerCase())) return true;
    }
    return false;
  }

  // ---------- Conversion Helpers ----------
  WizardPlace _toWizardPlace(
      Place place,
      String destinationName, {
        double? distanceKm,
        String? distanceStatus,
        String? destinationId,
        String? hotspotId,
      }) {
    // Keep the full Place record so selection-time validation can check
    // identity, coordinates, category and destination compatibility.
    registerPlace(place);

    final primaryType = _resolvePrimaryCategory(place.placeTypes ?? []);
    final typeIcon = _getCategoryIcon(place.placeTypes ?? []);
    final (travelIcon, travelLabel) = _getTravelModeInfo();

    return WizardPlace(
      placeId: place.placeId,
      name: place.placeName ?? 'Unnamed',
      type: primaryType,
      typeIcon: typeIcon,
      rating: place.placeRating ?? 0.0,
      imageUrl: place.placePhotoRef != null
          ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${place.placePhotoRef}&key=${ApiKeys.googleMapsApiKey}'
          : null,
      travelTime: '$travelLabel ~10-15m',
      travelIcon: travelIcon,
      duration: 'Estimating…',
      location: destinationName,
      isOpenNow: place.placeRegularOpeningHours?.openNow,
      isEnabled: true,
      distanceKm: distanceKm,
      distanceStatus: distanceStatus,
      destinationId: destinationId,
      hotspotId: hotspotId,
    );
  }

  String _resolvePrimaryCategory(List<String> types) {
    if (types.isEmpty) return 'Attraction';
    final specificTypes = types.where((t) =>
    t != 'point_of_interest' && t != 'establishment').toList();
    final rawType = specificTypes.isNotEmpty ? specificTypes.first : types.first;
    return rawType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  IconData _getCategoryIcon(List<String> types) {
    if (types.isEmpty) return Icons.place_rounded;
    final joined = types.join(' ').toLowerCase();

    if (joined.contains('restaurant') ||
        joined.contains('cafe') ||
        joined.contains('food') ||
        joined.contains('bakery')) {
      return Icons.restaurant_rounded;
    } else if (joined.contains('museum') ||
        joined.contains('art_gallery')) {
      return Icons.museum_rounded;
    } else if (joined.contains('park') ||
        joined.contains('natural_feature') ||
        joined.contains('campground')) {
      return Icons.park_rounded;
    } else if (joined.contains('tourist_attraction') ||
        joined.contains('amusement_park') ||
        joined.contains('church') ||
        joined.contains('hindu_temple') ||
        joined.contains('mosque')) {
      return Icons.attractions_rounded;
    } else if (joined.contains('shopping_mall') ||
        joined.contains('store')) {
      return Icons.shopping_bag_rounded;
    }
    return Icons.place_rounded;
  }

  (IconData, String) _getTravelModeInfo() {
    final mode = draft.transportation.toString().toLowerCase();
    if (mode.contains('car') || mode.contains('drive') || mode.contains('driving')) {
      return (Icons.directions_car_rounded, 'Drive');
    } else if (mode.contains('transit') || mode.contains('bus') || mode.contains('train')) {
      return (Icons.directions_bus_rounded, 'Transit');
    } else if (mode.contains('bike') || mode.contains('cycling')) {
      return (Icons.directions_bike_rounded, 'Bike');
    }
    return (Icons.directions_walk_rounded, 'Walk');
  }

  // ─── Hotspot distance classifier (corrected) ──────────────
  static ({String label, Color color}) classifyHotspotDistance(
      double distanceKm, double suggestedRadiusKm) {
    if (distanceKm <= suggestedRadiusKm) {
      return (label: 'WITHIN_HOTSPOT', color: Colors.green);
    } else if (distanceKm <= suggestedRadiusKm * 2.0) {
      return (label: 'OUTSIDE_HOTSPOT', color: Colors.orange);
    } else {
      return (label: 'FAR_FROM_DESTINATION', color: Colors.red);
    }
  }
}