// lib/viewmodel/ItineraryModel/must_visit_selection_vm.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/config/api_keys.dart';
import '../../core/services/database_manager.dart';
import '../../core/services/google_maps_service.dart';
import '../../model/business_logic/itinerary_service/candidate_retrieval_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/destination.dart';
import '../../model/entities/destination_hotspot.dart';
import '../../model/entities/place.dart';
import '../../model/entities/trip_draft.dart';
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
  final List<String> _mustVisitPlaces = [];
  final List<String> _mustVisitPlaceIds = [];
  final Map<String, String> _mustVisitNameById = {};

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
    if (draft.mustVisitPlaceIds.isNotEmpty) {
      _mustVisitPlaceIds.addAll(draft.mustVisitPlaceIds);
      for (final id in draft.mustVisitPlaceIds) {
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

  List<String> get mustVisitPlaces => _mustVisitPlaces;
  List<String> get mustVisitPlaceIds => List.unmodifiable(_mustVisitPlaceIds);
  DestinationHotspot? get selectedHotspot => _selectedHotspot;
  double? get selectedHotspotRadiusKm => _selectedHotspot?.suggestedRadiusKm;

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
      final dtos = await _bookmarkRepository.getBookmarksWithPlaces(user_id);
      final mapped = dtos.map((dto) {
        try {
          return _toWizardPlace(dto.place, '').copyWith(isEnabled: true);
        } catch (e) {
          return null;
        }
      }).where((w) => w != null).cast<WizardPlace>().toList();

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

  bool _belongsToAnySelectedDestinationByPlace(WizardPlace w) {
    // Placeholder: you can implement actual geofencing or name matching
    // For now, we treat all bookmarks as enabled.
    return true;
  }

  bool _belongsToAnySelectedDestination(Place place) {
    if (_cachedSelectedDestinations.isEmpty) return false;
    for (final dest in _cachedSelectedDestinations) {
      final destCoords = (dest.latitude != null && dest.longitude != null)
          ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
          : null;
      if (destCoords != null) {
        final distance = destCoords.distanceTo(place.coordinates);
        if (distance <= 50.0) return true;
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

  void togglePlace(String placeName) {
    final place = availablePlaces.firstWhere(
          (p) => p.name == placeName,
      orElse: () => WizardPlace(
          placeId: '',
          name: '',
          type: '',
          typeIcon: Icons.place,
          rating: 0,
          isEnabled: false),
    );
    if (!place.isEnabled) return;

    final placeId = place.placeId.isNotEmpty ? place.placeId : placeName;

    if (_mustVisitPlaces.contains(placeName) ||
        _mustVisitPlaceIds.contains(placeId)) {
      _mustVisitPlaces.remove(placeName);
      _mustVisitPlaceIds.remove(placeId);
      _mustVisitNameById.remove(placeId);
    } else {
      _mustVisitPlaces.add(placeName);
      _mustVisitPlaceIds.add(placeId);
      _mustVisitNameById[placeId] = place.name;
    }
    // Keep the draft's must-visit selections in sync so BACK navigation
    // keeps the selection.
    draft = draft.copyWith(
      mustVisitPlaceIds: _mustVisitPlaceIds,
    );
    notifyListeners();
  }

  bool isPlaceAdded(String name) => _mustVisitPlaces.contains(name);

  TripDraft buildDraft() {
    final ids = _mustVisitPlaceIds.isNotEmpty
        ? _mustVisitPlaceIds
        : _mustVisitPlaces;
    final updated = draft.copyWith(mustVisitPlaceIds: ids);
    draft = updated;
    return updated;
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