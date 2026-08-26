// lib/viewmodel/ItineraryModel/step3_add_place_vm.dart
import 'package:flutter/foundation.dart';
import '../../core/config/api_keys.dart';
import '../../core/services/google_maps_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/destination.dart';
import '../../model/entities/place.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/repositories/adapters/destination_repository_adapter.dart';
import '../../model/repositories/interfaces/destination_repository.dart';

/// UI model for a place shown in Step 3.
class WizardPlace {
  final String placeId; // Google Place ID (used to dedupe results)
  final String name;
  final String type;
  final double rating;
  final String? imageUrl;
  final String walkingTime;
  final String? duration;
  final String location; // destination label

  const WizardPlace({
    required this.placeId,
    required this.name,
    required this.type,
    required this.rating,
    this.imageUrl,
    this.walkingTime = 'N/A',
    this.duration,
    this.location = '',
  });
}

/// ViewModel for Step 3 (Must-go attractions).
///
/// Two tabs with two completely separate behaviours:
///
/// TAB 0 – Bookmarks:
///   Existing bookmark list, filtered locally by the search query.
///   No Google Maps API calls. Kept exactly as it was.
///
/// TAB 1 – Search Maps:
///   Performs a real Google Places text search, restricted to the
///   destination(s) selected in Step 1 (from [TripDraft.destinations]).
///   Results are validated against the destination coordinates, deduped
///   by Google Place ID, and converted into [WizardPlace].
class Step3AddPlaceVM extends ChangeNotifier {
  final TripDraft draft;
  final GoogleMapsService _mapsService;
  final DestinationRepository _destinationRepository;

  int selectedTab = 0; // 0: Bookmarks, 1: Search Maps
  String searchQuery = '';

  // ─── Bookmarks (UNCHANGED behaviour) ────────────────────────
  List<WizardPlace> _bookmarks = [];
  List<WizardPlace> get bookmarks => List.unmodifiable(_bookmarks);

  // ─── Search Maps state ──────────────────────────────────────
  List<WizardPlace> _defaultPlaces = []; // shown when query is empty
  List<WizardPlace> _searchResults = [];
  bool isLoading = false;
  String? errorMessage;

  // ─── Shared selection ───────────────────────────────────────
  final List<String> _mustVisitPlaces = [];

  Step3AddPlaceVM(
    this.draft, {
    GoogleMapsService? mapsService,
    DestinationRepository? destinationRepository,
  })  : _mapsService = mapsService ?? GoogleMapsService(),
        _destinationRepository =
            destinationRepository ?? DestinationRepositoryImpl() {
    _loadBookmarks();
  }

  // ---------- Getters ----------

  /// The list shown in the body, depending on the active tab.
  /// Bookmarks: local filtering. Search Maps: default high-rated picks
  /// when the query is empty, otherwise the live server results.
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

  List<String> get mustVisitPlaces => _mustVisitPlaces;

  // ---------- Actions ----------

  void setTab(int index) {
    selectedTab = index;
    errorMessage = null;
    if (index == 1 && _defaultPlaces.isEmpty && !isLoading) {
      // Show high-rated attractions + restaurants for the selected
      // destination(s) as soon as the Search Maps tab is opened.
      _loadDefaultPlaces();
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

  void togglePlace(String name) {
    if (_mustVisitPlaces.contains(name)) {
      _mustVisitPlaces.remove(name);
    } else {
      _mustVisitPlaces.add(name);
    }
    notifyListeners();
  }

  bool isPlaceAdded(String name) => _mustVisitPlaces.contains(name);

  TripDraft buildDraft() {
    return draft.copyWith(mustVisitIds: _mustVisitPlaces);
  }

  // ---------- Private Helpers ----------

  // Bookmarks stay exactly as they were — mock list until a real
  // bookmark repository is wired up.
  void _loadBookmarks() {
    _bookmarks = const [
      WizardPlace(
        placeId: 'batu_caves',
        name: 'Batu Caves',
        type: 'Cultural site · Kuala Lumpur',
        rating: 4.8,
        imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCDTcgV1RJQV_GKJAEkyZdZuJ-2SEe8r2hciTAdosn5MeIMQvyHt4BbUdAr0Ku2-93mDIbrkVGnBw5eWRDFwqNsk0_TDP6YWQgxQ0XeVKzJl2h1GyPiJYIdZtKjN_UtaRmn5rakqRT54Grvcpd9xdCQZqUfFUCCsHnyPeBDZUvIQcieCmzjUpa-AG69Q7H65d8If9GS-AeE75FAqkBuWGW9f8nAs-Nmgw18LZ3shDg7-tXyBw9oACge',
        walkingTime: '15 min',
        duration: '2 hr',
      ),
      WizardPlace(
        placeId: 'uncle_lims',
        name: "Uncle Lim's Cafe",
        type: 'Heritage Dining · KL Center',
        rating: 4.6,
        imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDMGwhhOKd3c1ZRjSlPXaHpjfdoF6u0oLWWZp5A1YPkvwmtLJh0HVwoLtgDwvFfISw4AOB3MLcS65QbYM9xieXMmK288WeL_b2OvPjxudwwOwcAqJBGiolQ96Dcs43WdUCL3YwaNPL2MvOsjnWu7OgPn2x178HgO-JkKERYtHis83yrtH45ga_3gitge4O106U-_RoaeSFVQm2-WPE2xFS0aLbtZ9jHeec9qKtiH23zEushtpp9JJDZ',
        walkingTime: '5 min',
        duration: '1 hr',
      ),
      WizardPlace(
        placeId: 'perdana_gardens',
        name: 'Perdana Gardens',
        type: 'Nature Park · KL',
        rating: 4.9,
        imageUrl: null,
        walkingTime: '12 min',
        duration: null,
      ),
    ];
  }

  /// Load high-rated attractions + restaurants for the selected
  /// destination(s). Called when the Search Maps tab is opened so the
  /// user sees useful picks immediately instead of an empty list.
  Future<void> _loadDefaultPlaces() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final selected = await _resolveSelectedDestinations();
      if (selected.isEmpty) {
        errorMessage = 'No destinations selected. Go back to Step 1.';
        _defaultPlaces = [];
        return;
      }

      // Attractions + restaurant categories to fetch per destination.
      const attractionTypes = [
        'tourist_attraction',
        'museum',
        'park',
        'landmark',
      ];
      const foodTypes = ['restaurant', 'cafe'];

      final all = <WizardPlace>[];
      final seenIds = <String>{};

      for (final dest in selected) {
        final coords = dest.latitude != null && dest.longitude != null
            ? Coordinates(latitude: dest.latitude!, longitude: dest.longitude!)
            : null;

        // 1. Fetch attractions
        final attractions = await _mapsService.searchNearbyPlaces(
          latitude: coords?.latitude ?? 0,
          longitude: coords?.longitude ?? 0,
          radius: 10000, // 10 km
          types: attractionTypes,
        );

        // 2. Fetch restaurants
        final restaurants = await _mapsService.searchNearbyPlaces(
          latitude: coords?.latitude ?? 0,
          longitude: coords?.longitude ?? 0,
          radius: 10000,
          types: foodTypes,
        );

        final merged = [...attractions, ...restaurants];
        for (final place in merged) {
          // Validate the place belongs to this destination.
          if (!_belongsToDestination(place, dest, coords)) continue;
          if (!seenIds.add(place.placeId)) continue;
          all.add(_toWizardPlace(place, dest.destinationName));
        }
      }

      // Random selection of high-rated picks, sorted by rating (highest
      // first) so the best places appear at the top.
      //all.shuffle();
      all.sort((a, b) => b.rating.compareTo(a.rating));
      _defaultPlaces = all.take(20).toList();
    } catch (e) {
      errorMessage = 'Could not load places. Check your connection.';
      _defaultPlaces = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Search Maps: run a Google Places text search for the active query,
  /// restricted to each selected destination from the TripDraft.
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
      // Resolve the selected destinations (with coordinates) from the
      // database — no hard-coded destination→coordinate map.
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

        // Restrict the query to the destination by combining the query
        // with the destination name AND biasing the search location.
        final localizedQuery = coords != null
            ? query
            : '$query, ${dest.destinationName}';

        final results = await _mapsService.searchTextPlaces(
          query: localizedQuery,
          latitude: coords?.latitude,
          longitude: coords?.longitude,
        );

        for (final place in results) {
          // Validate the place actually belongs to this destination.
          if (!_belongsToDestination(place, dest, coords)) continue;

          // Dedupe by Google Place ID.
          if (!seenIds.add(place.placeId)) continue;

          all.add(_toWizardPlace(place, dest.destinationName));
        }
      }

      _searchResults = all;
    } catch (e) {
      errorMessage = 'Could not search places. Check your connection.';
      _searchResults = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Load the destination entities matching the names stored in the
  /// TripDraft (the ones the traveler selected in Step 1).
  Future<List<Destination>> _resolveSelectedDestinations() async {
    if (draft.destinations.isEmpty) return const [];
    try {
      final all = await _destinationRepository.getAllDestinations();
      final names = draft.destinations.map((n) => n.trim().toLowerCase()).toSet();
      return all
          .where((d) => names.contains(d.destinationName.trim().toLowerCase()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Destination relevance check: when the destination has coordinates,
  /// the place must be within a reasonable radius of it. When we only
  /// have a name, fall back to checking the address string.
  bool _belongsToDestination(
    Place place,
    Destination dest,
    Coordinates? destCoords,
  ) {
    const maxKm = 50.0; // generous city radius

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

  WizardPlace _toWizardPlace(Place place, String destinationName) {
    final category = place.category ?? 'Attraction';
    final durationMinutes = place.visitDurationMinutes ?? 60;

    return WizardPlace(
      placeId: place.placeId,
      name: place.name,
      type: category,
      rating: place.rating,
      imageUrl: place.photoReference != null
          ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${place.photoReference}&key=${ApiKeys.googleMapsApiKey}'
          : null,
      walkingTime: 'N/A',
      duration: '$durationMinutes min',
      location: destinationName,
    );
  }
}
