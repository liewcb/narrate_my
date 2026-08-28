// lib/viewmodel/ItineraryModel/must_visit_selection_vm.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/config/api_keys.dart';
import '../../core/services/google_maps_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/destination.dart';
import '../../model/entities/place.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/repositories/adapters/bookmark_repository_adapter.dart';
import '../../model/repositories/adapters/destination_repository_adapter.dart';
import '../../model/repositories/interfaces/bookmark_repository.dart';
import '../../model/repositories/interfaces/destination_repository.dart';

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
  final bool isEnabled; // NEW: whether this place belongs to the selected destination

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
    this.isEnabled = true, // default enabled
  });

  /// Convenience copyWith for creating a modified instance.
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
    );
  }
}

/// ViewModel for Step 3 (Must-go attractions).
class Step3AddPlaceVM extends ChangeNotifier {
  final TripDraft draft;
  final GoogleMapsService _mapsService;
  final DestinationRepository _destinationRepository;
  final BookmarkRepository _bookmarkRepository;

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

  // ─── Pagination ─────────────────────────────────────────────
  static const int _pageSize = 10;
  int _currentPage = 0;
  bool isLoadingMore = false;

  // ─── Shared selection ───────────────────────────────────────
  final List<String> _mustVisitPlaces = [];

  // ─── Destination cache for validation ──────────────────────
  List<Destination> _cachedSelectedDestinations = [];

  /// User whose bookmarks are shown on the Bookmarks tab.
  final String userId;

  Step3AddPlaceVM(
      this.draft, {
        this.userId = '06f22239-d257-49f2-a6c9-786a69a5fbec',
        GoogleMapsService? mapsService,
        DestinationRepository? destinationRepository,
        BookmarkRepository? bookmarkRepository,
      })  : _mapsService = mapsService ?? GoogleMapsService(),
        _destinationRepository =
            destinationRepository ?? DestinationRepositoryImpl(),
        _bookmarkRepository =
            bookmarkRepository ?? BookmarkRepositoryImpl() {
    _ensureSelectedDestinations();
    loadBookmarks();
  }

  // ---------- Getters ----------

  /// The list shown in the body, depending on the active tab.
  /// For bookmarks, it returns the filtered (by search query) bookmarks.
  /// For search maps, it returns default places or search results.
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

  List<String> get mustVisitPlaces => _mustVisitPlaces;

  // ---------- Actions ----------

  /// Resolve the selected destinations from the draft and cache them.
  Future<void> _ensureSelectedDestinations() async {
    try {
      _cachedSelectedDestinations = await _resolveSelectedDestinations();
      debugPrint('✅ [Step3VM] Cached ${_cachedSelectedDestinations.length} selected destinations');
    } catch (e) {
      debugPrint('❌ [Step3VM] Failed to resolve destinations: $e');
      _cachedSelectedDestinations = [];
    }
  }

  /// Load bookmarks from the repository, filter by destination,
  /// and set `isEnabled` accordingly.
  Future<void> loadBookmarks() async {
    isLoadingBookmarks = true;
    bookmarksError = null;
    notifyListeners();

    try {
      // Ensure we have the selected destinations.
      await _ensureSelectedDestinations();

      final dtos = await _bookmarkRepository.getBookmarksWithPlaces(userId);
      final selectedDestNames = _cachedSelectedDestinations
          .map((d) => d.destinationName.trim().toLowerCase())
          .toSet();

      _bookmarks = dtos.map((dto) {
        final place = dto.place;
        // Determine if this place belongs to a selected destination.
        final bool isEnabled = _belongsToAnySelectedDestination(place);
        // Optionally, you could also filter out disabled places entirely.
        // For now we keep them but mark as disabled.
        return _toWizardPlace(place, '').copyWith(isEnabled: isEnabled);
      }).toList();

      // You can choose to hide disabled bookmarks by uncommenting:
      // _bookmarks = _bookmarks.where((p) => p.isEnabled).toList();

    } catch (e) {
      debugPrint('❌ [Step3VM] loadBookmarks error: $e');
      bookmarksError = 'Could not load bookmarks.';
      _bookmarks = [];
    } finally {
      isLoadingBookmarks = false;
      notifyListeners();
    }
  }

  /// Check if a place belongs to any selected destination.
  bool _belongsToAnySelectedDestination(Place place) {
    if (_cachedSelectedDestinations.isEmpty) return false;

    for (final dest in _cachedSelectedDestinations) {
      final coords = (dest.latitude != null && dest.longitude != null)
          ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
          : null;

      if (_belongsToDestination(place, dest, coords)) {
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

  /// One search bar, two behaviours:
  ///   tab 0 → local bookmark filtering (no API call)
  ///   tab 1 → real Google Places search, destination-restricted
  void searchPlaces(String query) {
    searchQuery = query;
    if (selectedTab == 0) {
      // Bookmarks: pure local filter — never touch Google.
      notifyListeners();
      return;
    }
    _searchMaps(query);
  }

  /// Toggle selection; only enabled places can be toggled.
  void togglePlace(String placeName) {
    final place = availablePlaces.firstWhere(
          (p) => p.name == placeName,
      orElse: () => WizardPlace(placeId: '', name: '', type: '', typeIcon: Icons.place, rating: 0, isEnabled: false),
    );
    if (!place.isEnabled) return; // prevent selecting disabled places

    if (_mustVisitPlaces.contains(placeName)) {
      _mustVisitPlaces.remove(placeName);
    } else {
      _mustVisitPlaces.add(placeName);
    }
    notifyListeners();
  }

  bool isPlaceAdded(String name) => _mustVisitPlaces.contains(name);

  TripDraft buildDraft() {
    return draft.copyWith(mustVisitPlaceIds: _mustVisitPlaces);
  }

  // ---------- Search Maps – Default Places ----------

  Future<void> loadDefaultPlaces() async {
    debugPrint('🚀 [Step3VM] loadDefaultPlaces()');
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

      const attractionTypes = ['tourist_attraction', 'museum', 'park', 'landmark'];
      const foodTypes = ['restaurant', 'cafe'];

      final all = <WizardPlace>[];
      final seenIds = <String>{};

      for (final dest in selected) {
        final hasCoords = dest.latitude != null && dest.longitude != null;

        List<Place> attractions = [];
        List<Place> restaurants = [];

        if (hasCoords) {
          attractions = await _mapsService.searchNearbyPlaces(
            latitude: dest.latitude!,
            longitude: dest.longitude!,
            radius: 10000,
            types: attractionTypes,
          );
          restaurants = await _mapsService.searchNearbyPlaces(
            latitude: dest.latitude!,
            longitude: dest.longitude!,
            radius: 10000,
            types: foodTypes,
          );
        } else {
          // Fallback: text search
          attractions = await _mapsService.searchTextPlaces(
            query: 'top attractions in ${dest.destinationName}',
          );
          restaurants = await _mapsService.searchTextPlaces(
            query: 'popular restaurants in ${dest.destinationName}',
          );
        }

        final merged = [...attractions, ...restaurants];
        for (final place in merged) {
          final coords = hasCoords
              ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
              : null;

          if (!_belongsToDestination(place, dest, coords)) continue;
          if (!seenIds.add(place.placeId)) continue;
          all.add(_toWizardPlace(place, dest.destinationName));
        }
      }

      all.sort((a, b) => b.rating.compareTo(a.rating));
      _defaultPlaces = all;
    } catch (e) {
      debugPrint('❌ [Step3VM] loadDefaultPlaces error: $e');
      errorMessage = 'Could not load places. Check your connection.';
      _defaultPlaces = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Load the next page of default places (pagination).
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
        errorMessage = 'No destinations selected. Go back to Step 1.';
        _searchResults = [];
        return;
      }

      final all = <WizardPlace>[];
      final seenIds = <String>{};

      for (final dest in selected) {
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

        for (final place in results) {
          if (!_belongsToDestination(place, dest, coords)) continue;
          if (!seenIds.add(place.placeId)) continue;
          all.add(_toWizardPlace(place, dest.destinationName));
        }
      }

      _searchResults = all;
    } catch (e) {
      debugPrint('❌ [Step3VM] _searchMaps error: $e');
      errorMessage = 'Could not search places. Check your connection.';
      _searchResults = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ---------- Destination Helpers ----------

  Future<List<Destination>> _resolveSelectedDestinations() async {
    debugPrint('📥 [Step3VM] Draft destinations: ${draft.destinations}');
    if (draft.destinations.isEmpty) return const [];

    try {
      final all = await _destinationRepository.getAllDestinations();
      final names = draft.destinations.map((n) => n.trim().toLowerCase()).toSet();

      final matched = all
          .where((d) => names.contains(d.destinationName.trim().toLowerCase()))
          .toList();

      debugPrint('🎯 [Step3VM] Matched ${matched.length} destinations');
      return matched;
    } catch (e) {
      debugPrint('❌ [Step3VM] _resolveSelectedDestinations error: $e');
      return const [];
    }
  }

  /// Destination relevance check: when the destination has coordinates,
  /// the place must be within a reasonable radius. Otherwise, fall back
  /// to checking the address string.
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

    // Fallback: address contains the destination name.
    if (dest.destinationName.isNotEmpty) {
      final address = (place.address + ' ' + place.name).toLowerCase();
      if (address.contains(dest.destinationName.toLowerCase())) return true;
    }

    return false;
  }

  // ---------- Conversion Helpers ----------

  WizardPlace _toWizardPlace(Place place, String destinationName) {
    final primaryType = _resolvePrimaryCategory(place.placeTypes);
    final typeIcon = _getCategoryIcon(place.placeTypes);
    final (travelIcon, travelLabel) = _getTravelModeInfo();

    return WizardPlace(
      placeId: place.placeId,
      name: place.placeName,
      type: primaryType,
      typeIcon: typeIcon,
      rating: place.placeRating,
      imageUrl: place.placePhotoRef != null
          ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${place.placePhotoRef}&key=${ApiKeys.googleMapsApiKey}'
          : null,
      travelTime: '$travelLabel ~10-15m',
      travelIcon: travelIcon,
      duration: '60 min',
      location: destinationName,
      isOpenNow: place.placeRegularOpeningHours?.openNow,
      isEnabled: true, // default; will be set later for bookmarks
    );
  }

  String _resolvePrimaryCategory(List<String> types) {
    if (types.isEmpty) return 'Attraction';

    final specificTypes = types.where((t) =>
    t != 'point_of_interest' && t != 'establishment'
    ).toList();

    final rawType = specificTypes.isNotEmpty ? specificTypes.first : types.first;

    return rawType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  IconData _getCategoryIcon(List<String> types) {
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
    final mode = (draft.transportation ?? 'walking').toString().toLowerCase();

    if (mode.contains('car') || mode.contains('drive') || mode.contains('driving')) {
      return (Icons.directions_car_rounded, 'Drive');
    } else if (mode.contains('transit') || mode.contains('bus') || mode.contains('train')) {
      return (Icons.directions_bus_rounded, 'Transit');
    } else if (mode.contains('bike') || mode.contains('cycling')) {
      return (Icons.directions_bike_rounded, 'Bike');
    }
    return (Icons.directions_walk_rounded, 'Walk');
  }
}