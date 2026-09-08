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
import '../../model/repositories/interfaces/bookmark/bookmark_repository.dart';
import '../../model/repositories/interfaces/itinerary/destination_repository.dart';

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

  /// True when the LAST destination resolution attempt FAILED (transient
  /// DB/network problem). While set, destination membership is UNKNOWN —
  /// the VM shows an error state and never claims any place is valid
  /// for the destination until a successful refresh (REQ: no silent
  /// "allow everything" fallback).
  bool _destinationsLoadFailed = false;
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
  }) : _mapsService = mapsService ?? GoogleMapsService(),
       _destinationRepository =
           destinationRepository ?? DatabaseManager().destinationRepository,
       _bookmarkRepository =
           bookmarkRepository ?? DatabaseManager().bookmarkRepository,
       user_id = userId,
       _candidateService = candidateService ?? CandidateRetrievalService() {
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
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.type.toLowerCase().contains(q),
        )
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

  bool get isSelectionLimitReached =>
      _mustVisitPlaceIds.length >= maxMustVisits;

  // ---------- Init / Load ----------
  /// Resolves the SELECTED destinations (identity = destination_id) and
  /// caches them for membership checks. Failures are remembered via
  /// [_destinationsLoadFailed] so nothing is ever treated as valid while
  /// destination information is unknown — a refresh retries resolution.
  Future<void> _ensureSelectedDestinations({bool force = false}) async {
    if (!force && _cachedSelectedDestinations.isNotEmpty) return;
    try {
      _cachedSelectedDestinations = await _resolveSelectedDestinations();
      _destinationsLoadFailed = false;
    } catch (e) {
      debugPrint('Failed to resolve destinations: $e');
      _cachedSelectedDestinations = [];
      _destinationsLoadFailed = true;
    }
  }

  Future<void> loadBookmarks() async {
    isLoadingBookmarks = true;
    bookmarksError = null;
    notifyListeners();

    try {
      await _ensureSelectedDestinations();

      // Destination UNKNOWN → never claim any bookmark is valid.
      if (_destinationsLoadFailed) {
        _bookmarks = [];
        bookmarksError =
        'Could not verify your selected destinations. Pull to refresh '
            'and try again.';
        return;
      }
      if (_cachedSelectedDestinations.isEmpty && draft.destinations.isNotEmpty) {
        _bookmarks = [];
        bookmarksError =
        'Your selected destinations could not be found. Pull to refresh '
            'and try again.';
        return;
      }

      final dtos = await _bookmarkRepository.getBookmarksWithPlaces(user_id);

      final validBookmarks = <WizardPlace>[];
      final disabledBookmarks = <WizardPlace>[];
      final seenBookmarkIds = <String>{};

      for (final dto in dtos) {
        final place = dto.place;

        if (!_isValidPlaceRecord(place)) continue;
        if (!seenBookmarkIds.add(place.placeId)) continue;

        // 1. Find which selected destination this bookmark belongs to
        Destination? matchedDest;
        for (final dest in _cachedSelectedDestinations) {
          final destCoords = (dest.latitude != null && dest.longitude != null)
              ? Coordinates(
            latitude: dest.latitude!,
            longitude: dest.longitude!,
          )
              : null;

          if (_belongsToDestination(place, dest, destCoords)) {
            matchedDest = dest;
            break;
          }
        }

        if (matchedDest == null) {
          // Outside all destinations → disabled
          disabledBookmarks.add(
            _toWizardPlace(
              place,
              'Outside Travel Area',
            ).copyWith(isEnabled: false),
          );
          continue;
        }

        // 2. Hotspot filter: only show bookmarks within the destination's hotspot
        final hotspot = await _hotspotForDestination(matchedDest.destinationId);
        if (hotspot != null) {
          final hotspotCoords = Coordinates(
            latitude: hotspot.latitude,
            longitude: hotspot.longitude,
          );
          final distanceKm =
          _mapsService.distanceKm(hotspotCoords, place.coordinates);
          // If outside the hotspot radius, skip this bookmark (filter it out)
          if (distanceKm > hotspot.suggestedRadiusKm) {
            continue;
          }
          // Inside hotspot → add as valid, optionally store distance/status
          final status = hotspot_svc.classifyHotspotDistance(
            distanceKm,
            hotspot.suggestedRadiusKm,
          );
          validBookmarks.add(
            _toWizardPlace(
              place,
              matchedDest.destinationName,
              destinationId: matchedDest.destinationId,
              distanceKm: distanceKm,
              distanceStatus: status.label,
            ).copyWith(isEnabled: true),
          );
        } else {
          // No hotspot configured for this destination – show the bookmark anyway
          validBookmarks.add(
            _toWizardPlace(
              place,
              matchedDest.destinationName,
              destinationId: matchedDest.destinationId,
            ).copyWith(isEnabled: true),
          );
        }
      }

      // Show valid ones if any, otherwise show disabled ones.
      _bookmarks = validBookmarks.isNotEmpty
          ? validBookmarks
          : disabledBookmarks;
    } catch (e) {
      bookmarksError = 'Could not load bookmarks.';
      _bookmarks = [];
    } finally {
      isLoadingBookmarks = false;
      notifyListeners();
    }
  }

  /// Full pull-to-refresh: reload destinations → hotspots → places,
  /// re-apply every destination/range/hotspot filter, reset pagination
  /// and drop stale search results. The UI list is never "refreshed"
  /// without the underlying data being revalidated.
  Future<void> refreshAll() async {
    debugPrint('🔄 refreshAll() — destinations → hotspots → places');
    // Stale hotspot / destination state must not survive a refresh.
    _hotspotCache.clear();
    _selectedHotspot = null;
    _currentPage = 0;
    isLoadingMore = false;
    _searchResults = [];

    await _ensureSelectedDestinations(force: true);
    await loadBookmarks();
    if (selectedTab == 1) {
      await loadDefaultPlaces();
    } else {
      // Drop any previously loaded places so switching to Search Maps
      // reloads and re-filters from scratch (setTab reloads when empty).
      _defaultPlaces = [];
      errorMessage = null;
      notifyListeners();
    }
  }

  /// Defensive data-quality gate (the DB is the source of truth, but API
  /// responses may still carry incomplete rows).
  bool _isValidPlaceRecord(Place place) {
    if (place.id.trim().isEmpty) return false;
    if (place.placeId.trim().isEmpty) return false;
    if (place.placeName.trim().isEmpty) return false;
    final lat = place.placeLatitude;
    final lng = place.placeLongitude;
    if (lat == 0.0 && lng == 0.0) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    return true;
  }

  /// REQ_MV_02 — a bookmark is destination-compatible when its underlying
  /// Place belongs to one of the selected destinations. Destination
  /// identity (`destination_id`) takes priority, then geographic range
  /// using the destination coordinates and
  /// [ItineraryConstants.maxSearchRadiusKm]. Name-only association is
  /// never invented. When destinations cannot be resolved the place is
  /// NOT claimed valid (selection re-checks on every attempt / refresh).
  bool _belongsToAnySelectedDestinationByPlace(WizardPlace w) {
    if (_cachedSelectedDestinations.isEmpty) return false;
    final place = _placeById[w.placeId];
    if (place == null) return false;
    return _belongsToAnySelectedDestination(place);
  }

  bool _belongsToAnySelectedDestination(Place place) {
    if (_cachedSelectedDestinations.isEmpty) return false;
    for (final dest in _cachedSelectedDestinations) {
      if (_destinationMatchesPlace(place, dest)) return true;
    }
    return false;
  }

  /// Shared membership rule for ONE destination:
  /// 1. explicit identity: `place.destinationId == dest.destinationId`;
  /// 2. geographic range: destination coordinates +
  ///    [ItineraryConstants.maxSearchRadiusKm].
  /// A place whose destination cannot be established (no identity AND no
  /// destination coordinates) is NEVER claimed to belong (no name-only
  /// association).
  bool _destinationMatchesPlace(Place place, Destination dest) {
    if (!_isValidPlaceRecord(place)) return false;
    final pid = place.destinationId?.trim();
    if (pid != null && pid.isNotEmpty) {
      // Identity is authoritative when present — a place tagged to
      // another destination is NEVER accepted (and the selected
      // destination is never switched to match it).
      return pid == dest.destinationId.trim();
    }
    final destCoords = (dest.latitude != null && dest.longitude != null)
        ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
        : null;
    if (destCoords == null) return false;
    final distance = destCoords.distanceTo(place.coordinates);
    return distance <= ItineraryConstants.maxSearchRadiusKm;
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

    // ── REQ_MV_10 — destination compatibility. ──
    // UNKNOWN destination state is never treated as valid: the traveler
    // is asked to refresh (which retries destination resolution).
    if (draft.destinations.isEmpty) {
      return MustVisitSelectionResult.rejected(
        'No destinations are selected yet. Go back to Step 1 and choose a '
        'destination first.',
      );
    }
    if (_destinationsLoadFailed || _cachedSelectedDestinations.isEmpty) {
      return MustVisitSelectionResult.rejected(
        'Your selected destinations could not be verified right now. '
        'Pull to refresh and try again.',
      );
    }
    if (!_belongsToAnySelectedDestination(place)) {
      return MustVisitSelectionResult.rejected(
        'This place cannot be added because its location is outside your '
        'selected destinations.',
      );
    }

    // ── REQ_MV_13 — hotspot distance validation. ──
    // FAR_FROM_DESTINATION → REJECT (never addable);
    // OUTSIDE_HOTSPOT → existing warning / confirmation flow;
    // WITHIN_HOTSPOT → add normally.
    final hotspotDecision = await _hotspotCheckFor(place);
    if (hotspotDecision != null &&
        !(hotspotDecision.status == MustVisitSelectionStatus.warning &&
            confirmOutsideHotspot)) {
      return hotspotDecision;
    }

    // ── All validation passed → preserve stable identity + metadata. ──
    _mustVisitPlaceIds.add(id);
    _mustVisitNameById[id] = place.placeName.isNotEmpty
        ? place.placeName
        : (placeName ?? id);
    _mustVisitMeta[id] = MustVisitPlaceInfo(
      placeId: id,
      placeName: place.placeName,
      destinationId: place.destinationId ?? _destinationIdForPlace(place),
      source: source,
      latitude: place.placeLatitude,
      longitude: place.placeLongitude,
    );
    _syncDraft();
    return MustVisitSelectionResult.added();
  }

  /// Hotspot decision for a place that already passed destination
  /// compatibility:
  ///   WITHIN_HOTSPOT     → `null` (add normally)
  ///   OUTSIDE_HOTSPOT    → warning (existing confirmation flow decides)
  ///   FAR_FROM_DESTINATION → rejected (never addable)
  /// The hotspot is always resolved for the destination the PLACE belongs
  /// to — a hotspot of another destination can never be applied.
  Future<MustVisitSelectionResult?> _hotspotCheckFor(Place place) async {
    for (final dest in _cachedSelectedDestinations) {
      if (!_destinationMatchesPlace(place, dest)) continue;
      final hotspot = await _hotspotForDestination(dest.destinationId);
      if (hotspot == null) return null; // no hotspot → nothing to warn about
      final hotspotDistance = _mapsService.distanceKm(
        Coordinates(latitude: hotspot.latitude, longitude: hotspot.longitude),
        place.coordinates,
      );
      final status = hotspot_svc.classifyHotspotDistance(
        hotspotDistance,
        hotspot.suggestedRadiusKm,
      );
      switch (status) {
        case hotspot_svc.HotspotDistanceStatus.farFromDestination:
          return MustVisitSelectionResult.rejected(
            'This place is too far from your selected destination to be '
            'added as a must-visit.',
          );
        case hotspot_svc.HotspotDistanceStatus.outsideHotspot:
          return MustVisitSelectionResult.warning(
            'This place is outside the main sightseeing area for this '
            'destination. Adding it may significantly increase your travel '
            'time.',
          );
        case hotspot_svc.HotspotDistanceStatus.withinHotspot:
          return null;
      }
    }
    return null;
  }

  Future<DestinationHotspot?> _hotspotForDestination(
    String destinationId,
  ) async {
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
      // The hotspot must belong to THIS destination (defense in depth —
      // destination_hotspots is keyed by destination_id in the database).
      if (hotspot != null && hotspot.destinationId != destinationId) {
        debugPrint('❌ Hotspot ${hotspot.id} belongs to '
            '${hotspot.destinationId}, not $destinationId — discarded');
        hotspot = null;
      }
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
    // Full reload = fresh pagination and no stale search results.
    _currentPage = 0;
    isLoadingMore = false;
    _searchResults = [];
    notifyListeners();

    try {
      await _ensureSelectedDestinations();
      final selected = _cachedSelectedDestinations;
      if (selected.isEmpty) {
        errorMessage = _destinationsLoadFailed || draft.destinations.isNotEmpty
            ? 'Could not verify your destinations. Pull to refresh and '
                  'try again.'
            : 'No destinations selected. Go back to Step 1.';
        _defaultPlaces = [];
        return;
      }

      // Build Google Places types from traveler interests (same as before)
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

      // Loop through each selected destination
      for (final dest in selected) {
        // 1. Get hotspot for THIS destination
        final hotspot = await _selectHotspotForDestination(dest);
        _selectedHotspot = hotspot; // keep for UI / getters

        // If no hotspot, skip this destination (no fallback)
        if (hotspot == null) {
          continue;
        }

        // 2. Search around the hotspot, using its configured
        //    suggested_radius_km as the discovery range.
        final places = await _mapsService.searchNearbyPlaces(
          latitude: hotspot.latitude,
          longitude: hotspot.longitude,
          radius: hotspot.suggestedRadiusKm * 1000,
          types: uniqueTypes,
        );

        // 3. Filter candidates and add to the list
        final destCoords = (dest.latitude != null && dest.longitude != null)
            ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
            : null;

        for (final place in places) {
          // Null / malformed records never enter the list.
          if (!_isValidPlaceRecord(place)) continue;
          // Ensure the place belongs to THIS destination (identity or
          // geographic range — never another destination's place).
          if (!_belongsToDestination(place, dest, destCoords)) continue;
          // Deduplicate by stable place_id, not name.
          if (!seenIds.add(place.placeId)) continue;

          // Hotspot classification (WITHIN / OUTSIDE preserved; FAR
          // cannot occur around the hotspot radius but is filtered for
          // safety).
          final hotspotCoords = Coordinates(
            latitude: hotspot.latitude,
            longitude: hotspot.longitude,
          );
          final distanceKm = _mapsService.distanceKm(
            hotspotCoords,
            place.coordinates,
          );
          final distanceStatus = hotspot_svc.classifyHotspotDistance(
            distanceKm,
            hotspot.suggestedRadiusKm,
          );
          if (distanceStatus ==
              hotspot_svc.HotspotDistanceStatus.farFromDestination) {
            continue;
          }

          all.add(
            _toWizardPlace(
              place,
              dest.destinationName,
              destinationId: dest.destinationId,
              hotspotId: hotspot.id,
              distanceKm: distanceKm,
              distanceStatus: distanceStatus.label,
            ),
          );
        }
      }

      // Sort by rating (highest first) and store
      all.sort((a, b) => b.rating.compareTo(a.rating));
      _defaultPlaces = all;
      notifyListeners();

      // Fetch AI durations in the background
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

  /// Returns the best hotspot for a given destination, using the internal
  /// cache. A hotspot whose `destination_id` does not match the requested
  /// destination is discarded (hotspots are destination-scoped).
  /// Returns null if no hotspot can be determined.
  Future<DestinationHotspot?> _selectHotspotForDestination(
    Destination dest,
  ) async {
    // Check cache first
    if (_hotspotCache.containsKey(dest.destinationId)) {
      return _hotspotCache[dest.destinationId];
    }

    DestinationHotspot? hotspot;
    try {
      hotspot = await _candidateService.selectBestHotspot(
        destinationName: dest.destinationName,
        destinationId: dest.destinationId,
        interests: draft.interests.toList(),
      );
      if (hotspot != null && hotspot.destinationId != dest.destinationId) {
        debugPrint('❌ Hotspot ${hotspot.id} belongs to '
            '${hotspot.destinationId}, not ${dest.destinationId} — discarded');
        hotspot = null;
      }
    } catch (e) {
      debugPrint('Hotspot resolution failed for ${dest.destinationName}: $e');
    }

    _hotspotCache[dest.destinationId] = hotspot;
    return hotspot;
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
      await _ensureSelectedDestinations();
      final selected = _cachedSelectedDestinations;
      if (selected.isEmpty) {
        errorMessage = _destinationsLoadFailed || draft.destinations.isNotEmpty
            ? 'Could not verify your destinations. Pull to refresh and '
                  'try again.'
            : 'No destinations selected.';
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
        // Destination-scoped hotspot (cached; a hotspot from another
        // destination is never used).
        final hotspot = await _hotspotForDestination(dest.destinationId);
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

        // Filter results by the relevant types (attractions AND food —
        // both interest type mappings stay supported).
        final filteredResults = results.where((place) {
          final placeTypes = place.placeTypes;
          return placeTypes.any((t) => uniqueTypes.contains(t));
        }).toList();

        for (final place in filteredResults) {
          // Google results NEVER bypass validation:
          // null/invalid → out; duplicate (stable place_id) → out;
          // outside the selected destination → out; FAR → out.
          if (!_isValidPlaceRecord(place)) continue;
          if (!seenIds.add(place.placeId)) continue;
          if (!_belongsToDestination(place, dest, coords)) continue;

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
            final status = hotspot_svc.classifyHotspotDistance(
              distanceKm,
              hotspot.suggestedRadiusKm,
            );
            if (status ==
                hotspot_svc.HotspotDistanceStatus.farFromDestination) {
              continue;
            }
            distanceStatus = status.label;
          }

          all.add(
            _toWizardPlace(
              place,
              dest.destinationName,
              distanceKm: distanceKm,
              distanceStatus: distanceStatus,
              // Identity is always the destination currently being
              // searched — never switched to a place's own destination.
              destinationId: dest.destinationId,
              hotspotId: hotspot?.id,
            ),
          );
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
  Future<String> _fetchDurationFromAI(
    String placeName,
    String placeType,
    String location,
  ) async {
    // 🔥 Replace with real Deepseek API call.
    await Future.delayed(const Duration(milliseconds: 300));
    final type = placeType.toLowerCase();
    if (type.contains('museum') || type.contains('art_gallery'))
      return '120 min';
    if (type.contains('restaurant') || type.contains('cafe')) return '60 min';
    if (type.contains('park') || type.contains('natural_feature'))
      return '90 min';
    if (type.contains('shopping') || type.contains('mall')) return '90 min';
    if (type.contains('attraction') || type.contains('landmark'))
      return '75 min';
    return '60 min';
  }

  Future<void> _fetchAndUpdateDurations() async {
    if (_defaultPlaces.isEmpty) return;
    final futures = _defaultPlaces.map(
      (place) => _fetchDurationFromAI(place.name, place.type, place.location),
    );
    try {
      final durations = await Future.wait(futures);
      for (int i = 0; i < _defaultPlaces.length; i++) {
        _defaultPlaces[i] = _defaultPlaces[i].copyWith(duration: durations[i]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to fetch AI durations: $e');
    }
  }

  Future<void> _fetchAndUpdateSearchDurations() async {
    if (_searchResults.isEmpty) return;
    final futures = _searchResults.map(
      (place) => _fetchDurationFromAI(place.name, place.type, place.location),
    );
    try {
      final durations = await Future.wait(futures);
      for (int i = 0; i < _searchResults.length; i++) {
        _searchResults[i] = _searchResults[i].copyWith(duration: durations[i]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to fetch AI durations for search results: $e');
    }
  }

  // ---------- Destination Helpers ----------
  /// Resolves the draft's selected destinations from the database.
  /// PRIMARY identity is `destination_id`; the name match only exists as
  /// a fallback for legacy draft rows that carry no ID.
  Future<List<Destination>> _resolveSelectedDestinations() async {
    if (draft.destinations.isEmpty) return [];
    final all = await _destinationRepository.getAllDestinations();
    final selectedIds = <String>{};
    final fallbackNames = <String>{};
    for (final d in draft.destinations) {
      final id = d.destinationId.trim();
      if (id.isNotEmpty) {
        selectedIds.add(id);
      } else {
        fallbackNames.add(d.destinationName.trim().toLowerCase());
      }
    }
    final resolvedIds = <String>{};
    final out = <Destination>[];
    for (final d in all) {
      if (resolvedIds.contains(d.destinationId)) continue;
      final matchesIdentity = selectedIds.contains(d.destinationId.trim());
      final matchesLegacyName =
          fallbackNames.contains(d.destinationName.trim().toLowerCase());
      if (matchesIdentity || (selectedIds.isEmpty && matchesLegacyName)) {
        resolvedIds.add(d.destinationId);
        out.add(d);
      }
    }
    return out;
  }

  /// Check 1 — DESTINATION COMPATIBILITY: stable database identity
  /// (`destination_id`) first, then geographic range using the
  /// destination coordinates and [ItineraryConstants.maxSearchRadiusKm].
  bool _belongsToDestination(
    Place place,
    Destination dest,
    Coordinates? destCoords,
  ) {
    return _destinationMatchesPlace(place, dest);
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

    // Priority order: more specific/suitable types first
    const priorityMap = {
      // Must-visit worthy categories (attractions)
      'tourist_attraction': 'Attraction',
      'amusement_park': 'Amusement Park',
      'theme_park': 'Theme Park',
      'water_park': 'Water Park',
      'zoo': 'Zoo',
      'aquarium': 'Aquarium',
      'museum': 'Museum',
      'art_gallery': 'Art Gallery',
      'park': 'Park',
      'national_park': 'National Park',
      'natural_feature': 'Natural Feature',
      'botanical_garden': 'Botanical Garden',
      'beach': 'Beach',
      'campground': 'Campground',
      'hiking_area': 'Hiking Area',
      'place_of_worship': 'Religious Site',
      'church': 'Church',
      'hindu_temple': 'Temple',
      'mosque': 'Mosque',
      'synagogue': 'Synagogue',
      'stadium': 'Stadium',
      'bowling_alley': 'Bowling',
      'movie_theater': 'Cinema',

      // Food & dining
      'restaurant': 'Restaurant',
      'cafe': 'Cafe',
      'bakery': 'Bakery',
      'bar': 'Bar',
      'night_club': 'Night Club',

      // Shopping
      'shopping_mall': 'Shopping Mall',
      'department_store': 'Department Store',
      'clothing_store': 'Clothing Store',
      'book_store': 'Bookstore',
      'jewelry_store': 'Jewellery Store',
      'supermarket': 'Supermarket',

      // Services (NOT must-visit worthy)
      'pharmacy': 'Pharmacy',
      'hospital': 'Hospital',
      'doctor': 'Doctor',
      'dentist': 'Dentist',
      'bank': 'Bank',
      'atm': 'ATM',
      'post_office': 'Post Office',
      'real_estate_agency': 'Real Estate',
      'lawyer': 'Lawyer',
      'spa': 'Spa',
      'hair_care': 'Hair Salon',
      'beauty_salon': 'Beauty Salon',
      'gym': 'Gym',
      'fitness_center': 'Fitness Centre',
    };

    // Try to find a matching type in priority order
    for (final type in types) {
      final matched = priorityMap[type.toLowerCase()];
      if (matched != null) {
        return matched;
      }
    }

    // If no match, try to format the first non-generic type nicely
    final specificTypes = types
        .where((t) => t != 'point_of_interest' && t != 'establishment')
        .toList();
    if (specificTypes.isNotEmpty) {
      final raw = specificTypes.first;
      return raw
          .replaceAll('_', ' ')
          .split(' ')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
    }

    return 'Place';
  }

  IconData _getCategoryIcon(List<String> types) {
    if (types.isEmpty) return Icons.place_rounded;

    // Check for food/dining
    if (_typesContain(types, [
      'restaurant',
      'cafe',
      'bakery',
      'bar',
      'meal_takeaway',
      'meal_delivery',
    ])) {
      return Icons.restaurant_rounded;
    }

    // Check for museums & galleries
    if (_typesContain(types, ['museum', 'art_gallery'])) {
      return Icons.museum_rounded;
    }

    // Check for nature & parks
    if (_typesContain(types, [
      'park',
      'national_park',
      'natural_feature',
      'campground',
      'botanical_garden',
    ])) {
      return Icons.park_rounded;
    }

    // Check for attractions
    if (_typesContain(types, [
      'tourist_attraction',
      'amusement_park',
      'theme_park',
      'water_park',
      'zoo',
      'aquarium',
      'place_of_worship',
      'church',
      'hindu_temple',
      'mosque',
      'synagogue',
      'stadium',
    ])) {
      return Icons.attractions_rounded;
    }

    // Check for shopping
    if (_typesContain(types, [
      'shopping_mall',
      'department_store',
      'clothing_store',
      'book_store',
      'jewelry_store',
      'supermarket',
      'convenience_store',
    ])) {
      return Icons.shopping_bag_rounded;
    }

    // Check for services (pharmacy, bank, etc.)
    if (_typesContain(types, [
      'pharmacy',
      'hospital',
      'doctor',
      'dentist',
      'bank',
      'atm',
      'post_office',
      'real_estate_agency',
      'lawyer',
      'spa',
      'hair_care',
      'beauty_salon',
      'gym',
      'fitness_center',
    ])) {
      return Icons.medical_services_rounded;
    }

    return Icons.place_rounded;
  }

  // Helper to check if any type matches the list
  bool _typesContain(List<String> types, List<String> candidates) {
    final lowerTypes = types.map((t) => t.toLowerCase()).toSet();
    return candidates.any((c) => lowerTypes.contains(c));
  }

  (IconData, String) _getTravelModeInfo() {
    final mode = draft.transportation.toString().toLowerCase();
    if (mode.contains('car') ||
        mode.contains('drive') ||
        mode.contains('driving')) {
      return (Icons.directions_car_rounded, 'Drive');
    } else if (mode.contains('transit') ||
        mode.contains('bus') ||
        mode.contains('train')) {
      return (Icons.directions_bus_rounded, 'Transit');
    } else if (mode.contains('bike') || mode.contains('cycling')) {
      return (Icons.directions_bike_rounded, 'Bike');
    }
    return (Icons.directions_walk_rounded, 'Walk');
  }
}
