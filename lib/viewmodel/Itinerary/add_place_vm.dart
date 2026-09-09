import 'package:flutter/foundation.dart';
import '../../core/config/api_keys.dart';
import '../../core/config/itinerary_constants.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/business_logic/itinerary_service/scoring_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/interfaces/itinerary/itinerary_stop_repository.dart';

/// A candidate place the user can add to a day of a generated itinerary.
/// A candidate place the user can add to a day of a generated itinerary.
class AddPlaceOption {
  final String placeId;
  final String name;
  final String category;
  final String? imageUrl;
  final int durationMinutes;
  final double rating;
  final int? userRatingsTotal;
  final String? address;

  /// Full place record — carried through the AI insertion + validation flow so
  /// stable identity, coordinates, category and opening hours are never lost.
  final Place place;

  const AddPlaceOption({
    required this.placeId,
    required this.name,
    required this.category,
    this.imageUrl,
    required this.durationMinutes,
    this.rating = 0.0,
    this.userRatingsTotal,
    this.address,
    required this.place,
  });
}

/// Result of trying to add places to a day.
class AddPlaceResult {
  final bool success;
  final String? message;
  final List<ItineraryStop> addedStops;

  /// Preview mode: the validated, AI-positioned updated day. The caller
  /// replaces ONLY this day in the working itinerary — nothing is written to
  /// the database during preview.
  final ScheduledDay? proposedDay;

  const AddPlaceResult({
    required this.success,
    this.message,
    this.addedStops = const [],
    this.proposedDay,
  });
}

/// ViewModel for "Add a Place" after the itinerary has been generated.
///
/// Two modes:
///
///  * PREVIEW mode ([workingDay] != null) — the itinerary is still an
///    unsaved, in-memory preview. Candidates are retrieved for the SELECTED
///    DAY (existing CandidateRetrieval/Google Places services), filtered
///    (duplicate by stable place_id, valid id, valid coordinates, destination
///    compatibility, existing eligibility rules) and ranked. On selection the
///    existing [CustomPlaceService] builds a specific-day context, asks
///    DeepSeek for the best insertion position, deterministically constructs
///    the complete updated day and hard-validates it. The validated day is
///    returned to the Preview — the database is NEVER touched.
///
///  * LEGACY mode ([workingDay] == null) — a saved itinerary (Manage/detail
///    screens). Behaviour is unchanged: the day's stops are read from the
///    repository and confirmed places are appended as new [ItineraryStop]
///    rows.
class AddPlaceVM extends ChangeNotifier {
  final String itineraryId;
  final int dayIndex;
  final String explorationTime;

  // ─── Preview working state (null → legacy DB mode) ──────────
  final ScheduledDay? workingDay;
  final Set<String> itineraryUsedPlaceIds;
  final DateTime? dayDate;
  final String transportMode;
  final String travelPace;
  final List<String> interests;
  final List<String> mustVisitPlaceIds;
  final Coordinates? destinationCenter;

  final ItineraryStopRepository _stopRepository;
  final CustomPlaceService _service;

  AddPlaceVM({
    required this.itineraryId,
    required this.dayIndex,
    required this.explorationTime,
    this.workingDay,
    this.itineraryUsedPlaceIds = const {},
    this.dayDate,
    this.transportMode = 'walking',
    this.travelPace = 'Standard',
    this.interests = const [],
    this.mustVisitPlaceIds = const [],
    this.destinationCenter,
    ItineraryStopRepository? stopRepository,
    CustomPlaceService? service,
  })  : _stopRepository =
            stopRepository ?? DatabaseManager().itineraryStopRepository,
        _service = service ?? CustomPlaceService();

  bool get isPreviewMode => workingDay != null;

  // ─── Existing schedule ──────────────────────────────────────
  List<ItineraryStop> _existingStops = [];
  bool isLoadingStops = false;
  String? loadError;

  List<ItineraryStop> get existingStops => List.unmodifiable(_existingStops);

  // ─── Search & Category Filters ──────────────────────────────
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String _selectedCategoryFilter = 'All';
  String get selectedCategoryFilter => _selectedCategoryFilter;

  bool isSearching = false;
  List<AddPlaceOption> _searchResults = [];

  void setCategoryFilter(String category) {
    _selectedCategoryFilter = category;
    notifyListeners();
  }

  // ─── Candidates & selection ─────────────────────────────────
  final List<AddPlaceOption> _retrievedCandidates = [];
  bool isLoadingCandidates = false;
  String? candidatesError;

  /// Rich curated list of iconic, top-rated Malaysian landmarks and attractions.
  static final List<AddPlaceOption> _curatedFamousPlaces = [
    AddPlaceOption(
      placeId: 'petronas_twin_towers',
      name: 'Petronas Twin Towers',
      category: 'Landmark & Architecture',
      imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 90,
      rating: 4.7,
      userRatingsTotal: 145200,
      address: 'Kuala Lumpur City Centre, 50088 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=600&auto=format&fit=crop&q=80',
        placeId: 'petronas_twin_towers',
        placeName: 'Petronas Twin Towers',
        placeAddress: 'Kuala Lumpur City Centre, 50088 Kuala Lumpur',
        placeLatitude: 3.1578,
        placeLongitude: 101.7119,
        placeRating: 4.7,
        placeTotalReviews: 145200,
        placeTypes: ['tourist_attraction', 'point_of_interest'],
        category: 'Landmark',
        visitDurationMinutes: 90,
      ),
    ),
    AddPlaceOption(
      placeId: 'batu_caves',
      name: 'Batu Caves',
      category: 'Heritage & Temple',
      imageUrl:
          'https://images.unsplash.com/photo-1544644181-1484b3fdfc62?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 120,
      rating: 4.6,
      userRatingsTotal: 98400,
      address: 'Gombak, 68100 Batu Caves, Selangor',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1544644181-1484b3fdfc62?w=600&auto=format&fit=crop&q=80',
        placeId: 'batu_caves',
        placeName: 'Batu Caves',
        placeAddress: 'Gombak, 68100 Batu Caves, Selangor',
        placeLatitude: 3.2379,
        placeLongitude: 101.6840,
        placeRating: 4.6,
        placeTotalReviews: 98400,
        placeTypes: ['tourist_attraction', 'place_of_worship'],
        category: 'Culture',
        visitDurationMinutes: 120,
      ),
    ),
    AddPlaceOption(
      placeId: 'kl_tower',
      name: 'KL Tower (Menara Kuala Lumpur)',
      category: 'Observation Deck & Views',
      imageUrl:
          'https://images.unsplash.com/photo-1508963493744-76fce69379c0?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 90,
      rating: 4.5,
      userRatingsTotal: 52300,
      address: '2 Jalan Punchak, Off Jalan P. Ramlee, 50250 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1508963493744-76fce69379c0?w=600&auto=format&fit=crop&q=80',
        placeId: 'kl_tower',
        placeName: 'KL Tower (Menara Kuala Lumpur)',
        placeAddress: '2 Jalan Punchak, Off Jalan P. Ramlee, 50250 Kuala Lumpur',
        placeLatitude: 3.1528,
        placeLongitude: 101.7038,
        placeRating: 4.5,
        placeTotalReviews: 52300,
        placeTypes: ['tourist_attraction', 'point_of_interest'],
        category: 'Landmark',
        visitDurationMinutes: 90,
      ),
    ),
    AddPlaceOption(
      placeId: 'aquaria_klcc',
      name: 'Aquaria KLCC',
      category: 'Aquarium & Marine Life',
      imageUrl:
          'https://images.unsplash.com/photo-1522069169874-c58ec4b76be5?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 90,
      rating: 4.6,
      userRatingsTotal: 42100,
      address: 'Kuala Lumpur Convention Centre, Jalan Pinang, 50088 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1522069169874-c58ec4b76be5?w=600&auto=format&fit=crop&q=80',
        placeId: 'aquaria_klcc',
        placeName: 'Aquaria KLCC',
        placeAddress:
            'Kuala Lumpur Convention Centre, Jalan Pinang, 50088 Kuala Lumpur',
        placeLatitude: 3.1534,
        placeLongitude: 101.7135,
        placeRating: 4.6,
        placeTotalReviews: 42100,
        placeTypes: ['aquarium', 'tourist_attraction'],
        category: 'Nature',
        visitDurationMinutes: 90,
      ),
    ),
    AddPlaceOption(
      placeId: 'pavilion_kl',
      name: 'Pavilion Kuala Lumpur',
      category: 'Premier Shopping & Dining',
      imageUrl:
          'https://images.unsplash.com/photo-1567449303078-57ad995bd301?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 120,
      rating: 4.7,
      userRatingsTotal: 98600,
      address: '168 Jalan Bukit Bintang, 55100 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1567449303078-57ad995bd301?w=600&auto=format&fit=crop&q=80',
        placeId: 'pavilion_kl',
        placeName: 'Pavilion Kuala Lumpur',
        placeAddress: '168 Jalan Bukit Bintang, 55100 Kuala Lumpur',
        placeLatitude: 3.1488,
        placeLongitude: 101.7133,
        placeRating: 4.7,
        placeTotalReviews: 98600,
        placeTypes: ['shopping_mall', 'point_of_interest'],
        category: 'Shopping',
        visitDurationMinutes: 120,
      ),
    ),
    AddPlaceOption(
      placeId: 'thean_hou_temple',
      name: 'Thean Hou Temple',
      category: 'Heritage & Culture',
      imageUrl:
          'https://images.unsplash.com/photo-1584282479339-4d6bfaaa381b?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 75,
      rating: 4.7,
      userRatingsTotal: 33200,
      address: '65 Guan Di Temple, Lorong Bellamy, 50460 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1584282479339-4d6bfaaa381b?w=600&auto=format&fit=crop&q=80',
        placeId: 'thean_hou_temple',
        placeName: 'Thean Hou Temple',
        placeAddress: '65 Guan Di Temple, Lorong Bellamy, 50460 Kuala Lumpur',
        placeLatitude: 3.1219,
        placeLongitude: 101.6872,
        placeRating: 4.7,
        placeTotalReviews: 33200,
        placeTypes: ['place_of_worship', 'tourist_attraction'],
        category: 'Culture',
        visitDurationMinutes: 75,
      ),
    ),
    AddPlaceOption(
      placeId: 'jalan_alor',
      name: 'Jalan Alor Food Street',
      category: 'Food & Street Dining',
      imageUrl:
          'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 90,
      rating: 4.4,
      userRatingsTotal: 39500,
      address: 'Bukit Bintang, 50200 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=600&auto=format&fit=crop&q=80',
        placeId: 'jalan_alor',
        placeName: 'Jalan Alor Food Street',
        placeAddress: 'Bukit Bintang, 50200 Kuala Lumpur',
        placeLatitude: 3.1461,
        placeLongitude: 101.7088,
        placeRating: 4.4,
        placeTotalReviews: 39500,
        placeTypes: ['restaurant', 'food'],
        category: 'Food',
        visitDurationMinutes: 90,
      ),
    ),
    AddPlaceOption(
      placeId: 'heli_lounge_bar',
      name: 'Heli Lounge Bar',
      category: 'Nightlife & Rooftop Bar',
      imageUrl:
          'https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 90,
      rating: 4.5,
      userRatingsTotal: 7200,
      address: '34 Menara KH, Jalan Sultan Ismail, 50450 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=600&auto=format&fit=crop&q=80',
        placeId: 'heli_lounge_bar',
        placeName: 'Heli Lounge Bar',
        placeAddress: '34 Menara KH, Jalan Sultan Ismail, 50450 Kuala Lumpur',
        placeLatitude: 3.1508,
        placeLongitude: 101.7099,
        placeRating: 4.5,
        placeTotalReviews: 7200,
        placeTypes: ['bar', 'night_club'],
        category: 'Nightlife',
        visitDurationMinutes: 90,
      ),
    ),
    AddPlaceOption(
      placeId: 'changkat_bukit_bintang',
      name: 'Changkat Bukit Bintang',
      category: 'Nightlife & Pubs',
      imageUrl:
          'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 120,
      rating: 4.5,
      userRatingsTotal: 14200,
      address: 'Bukit Bintang, 50200 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?w=600&auto=format&fit=crop&q=80',
        placeId: 'changkat_bukit_bintang',
        placeName: 'Changkat Bukit Bintang',
        placeAddress: 'Bukit Bintang, 50200 Kuala Lumpur',
        placeLatitude: 3.1472,
        placeLongitude: 101.7077,
        placeRating: 4.5,
        placeTotalReviews: 14200,
        placeTypes: ['bar', 'night_club'],
        category: 'Nightlife',
        visitDurationMinutes: 120,
      ),
    ),
    AddPlaceOption(
      placeId: 'saloma_link',
      name: 'Saloma Link (Pintasan Saloma)',
      category: 'Scenic Bridge & Landmark',
      imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 45,
      rating: 4.6,
      userRatingsTotal: 18500,
      address: 'Lorong Saloma, Kampung Baru, 50300 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=600&auto=format&fit=crop&q=80',
        placeId: 'saloma_link',
        placeName: 'Saloma Link (Pintasan Saloma)',
        placeAddress: 'Lorong Saloma, Kampung Baru, 50300 Kuala Lumpur',
        placeLatitude: 3.1594,
        placeLongitude: 101.7088,
        placeRating: 4.6,
        placeTotalReviews: 18500,
        placeTypes: ['tourist_attraction', 'point_of_interest'],
        category: 'Landmark',
        visitDurationMinutes: 45,
      ),
    ),
    AddPlaceOption(
      placeId: 'perdana_botanical_garden',
      name: 'Perdana Botanical Garden',
      category: 'Nature & Botanical Park',
      imageUrl:
          'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 90,
      rating: 4.6,
      userRatingsTotal: 24500,
      address: 'Jalan Kebun Bunga, Tasik Perdana, 55100 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?w=600&auto=format&fit=crop&q=80',
        placeId: 'perdana_botanical_garden',
        placeName: 'Perdana Botanical Garden',
        placeAddress: 'Jalan Kebun Bunga, Tasik Perdana, 55100 Kuala Lumpur',
        placeLatitude: 3.1437,
        placeLongitude: 101.6841,
        placeRating: 4.6,
        placeTotalReviews: 24500,
        placeTypes: ['park', 'tourist_attraction'],
        category: 'Nature',
        visitDurationMinutes: 90,
      ),
    ),
    AddPlaceOption(
      placeId: 'islamic_arts_museum',
      name: 'Islamic Arts Museum Malaysia',
      category: 'Museum & Art Gallery',
      imageUrl:
          'https://images.unsplash.com/photo-1582555172866-f73bb12a2ab3?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 120,
      rating: 4.7,
      userRatingsTotal: 15100,
      address: 'Jalan Lembah, Tasik Perdana, 50480 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1582555172866-f73bb12a2ab3?w=600&auto=format&fit=crop&q=80',
        placeId: 'islamic_arts_museum',
        placeName: 'Islamic Arts Museum Malaysia',
        placeAddress: 'Jalan Lembah, Tasik Perdana, 50480 Kuala Lumpur',
        placeLatitude: 3.1417,
        placeLongitude: 101.6896,
        placeRating: 4.7,
        placeTotalReviews: 15100,
        placeTypes: ['museum', 'tourist_attraction'],
        category: 'Culture',
        visitDurationMinutes: 120,
      ),
    ),
    AddPlaceOption(
      placeId: 'central_market',
      name: 'Central Market (Pasar Seni)',
      category: 'Culture & Souvenir Market',
      imageUrl:
          'https://images.unsplash.com/photo-1541480601022-2308c0f02487?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 75,
      rating: 4.4,
      userRatingsTotal: 45200,
      address: 'Jalan Hang Kasturi, City Centre, 50050 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1541480601022-2308c0f02487?w=600&auto=format&fit=crop&q=80',
        placeId: 'central_market',
        placeName: 'Central Market (Pasar Seni)',
        placeAddress: 'Jalan Hang Kasturi, City Centre, 50050 Kuala Lumpur',
        placeLatitude: 3.1453,
        placeLongitude: 101.6958,
        placeRating: 4.4,
        placeTotalReviews: 45200,
        placeTypes: ['shopping_mall', 'point_of_interest'],
        category: 'Shopping',
        visitDurationMinutes: 75,
      ),
    ),
    AddPlaceOption(
      placeId: 'petaling_street',
      name: 'Petaling Street (Chinatown)',
      category: 'Street Market & Culture',
      imageUrl:
          'https://images.unsplash.com/photo-1583037189850-1921ae7c6c22?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 90,
      rating: 4.4,
      userRatingsTotal: 48900,
      address: 'Jalan Petaling, City Centre, 50000 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1583037189850-1921ae7c6c22?w=600&auto=format&fit=crop&q=80',
        placeId: 'petaling_street',
        placeName: 'Petaling Street (Chinatown)',
        placeAddress: 'Jalan Petaling, City Centre, 50000 Kuala Lumpur',
        placeLatitude: 3.1444,
        placeLongitude: 101.6978,
        placeRating: 4.4,
        placeTotalReviews: 48900,
        placeTypes: ['tourist_attraction', 'point_of_interest'],
        category: 'Culture',
        visitDurationMinutes: 90,
      ),
    ),
    AddPlaceOption(
      placeId: 'dataran_merdeka',
      name: 'Merdeka Square (Dataran Merdeka)',
      category: 'Historical Landmark',
      imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=600&auto=format&fit=crop&q=80',
      durationMinutes: 60,
      rating: 4.6,
      userRatingsTotal: 31200,
      address: 'Jalan Raja, City Centre, 50050 Kuala Lumpur',
      place: const Place(
        placeImageUrl: 'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=600&auto=format&fit=crop&q=80',
        placeId: 'dataran_merdeka',
        placeName: 'Merdeka Square (Dataran Merdeka)',
        placeAddress: 'Jalan Raja, City Centre, 50050 Kuala Lumpur',
        placeLatitude: 3.1492,
        placeLongitude: 101.6938,
        placeRating: 4.6,
        placeTotalReviews: 31200,
        placeTypes: ['tourist_attraction', 'point_of_interest'],
        category: 'Landmark',
        visitDurationMinutes: 60,
      ),
    ),
  ];

  List<AddPlaceOption> get candidates {
    List<AddPlaceOption> raw;
    if (_searchQuery.trim().isNotEmpty) {
      raw = _searchResults;
    } else if (isPreviewMode) {
      raw = _retrievedCandidates.isNotEmpty ? _retrievedCandidates : _curatedFamousPlaces;
    } else {
      raw = _curatedFamousPlaces;
    }

    if (_selectedCategoryFilter == 'All') {
      return List.unmodifiable(raw);
    }

    return List.unmodifiable(raw.where((item) {
      final cat = item.category.toLowerCase();
      switch (_selectedCategoryFilter) {
        case 'Landmarks':
          return cat.contains('landmark') ||
              cat.contains('tower') ||
              cat.contains('square') ||
              cat.contains('deck') ||
              cat.contains('bridge');
        case 'Culture':
          return cat.contains('museum') ||
              cat.contains('temple') ||
              cat.contains('heritage') ||
              cat.contains('art') ||
              cat.contains('culture');
        case 'Food & Nightlife':
          return cat.contains('food') ||
              cat.contains('nightlife') ||
              cat.contains('bar') ||
              cat.contains('dining') ||
              cat.contains('restaurant') ||
              cat.contains('pub');
        case 'Shopping':
          return cat.contains('shopping') ||
              cat.contains('mall') ||
              cat.contains('market');
        case 'Nature':
          return cat.contains('nature') ||
              cat.contains('park') ||
              cat.contains('garden') ||
              cat.contains('aquarium');
        default:
          return true;
      }
    }));
  }

  /// Live Search method for finding places by text query
  Future<void> search(String query) async {
    _searchQuery = query;
    if (query.trim().isEmpty) {
      _searchResults.clear();
      isSearching = false;
      notifyListeners();
      return;
    }

    isSearching = true;
    notifyListeners();

    try {
      final dayPlaces = workingDay?.stops.map((s) => s.attraction.place).toList() ?? [];
      final center = destinationCenter ??
          (dayPlaces.isNotEmpty ? dayPlaces.first.coordinates : null);

      final places = await _service.searchPlaces(
        query: query.trim(),
        locationBias: center,
      );

      final results = <AddPlaceOption>[];
      final usedIds = <String>{
        ...itineraryUsedPlaceIds,
        ...dayPlaces.map((p) => p.placeId),
      };

      for (final p in places) {
        if (p.placeId.isEmpty || p.placeName.isEmpty) continue;
        if (usedIds.contains(p.placeId)) continue;

        results.add(AddPlaceOption(
          placeId: p.placeId,
          name: p.placeName,
          category: p.category ??
              (p.placeTypes.isNotEmpty
                  ? p.placeTypes.first.replaceAll('_', ' ').toUpperCase()
                  : 'Attraction'),
          imageUrl: _photoUrl(p.placePhotoRef) ?? p.placeImageUrl ?? p.placePhotoGoogleMapsUri,
          durationMinutes: p.visitDurationMinutes ??
              ItineraryConstants.defaultDurationMinutes,
          rating: p.placeRating,
          userRatingsTotal: p.placeTotalReviews,
          address: p.placeAddress.isNotEmpty ? p.placeAddress : null,
          place: p,
        ));
      }

      // Also search in curated famous list for local matches
      final queryLower = query.toLowerCase();
      for (final curated in _curatedFamousPlaces) {
        if (!usedIds.contains(curated.placeId) &&
            !results.any((r) => r.placeId == curated.placeId)) {
          if (curated.name.toLowerCase().contains(queryLower) ||
              curated.category.toLowerCase().contains(queryLower) ||
              (curated.address?.toLowerCase().contains(queryLower) ?? false)) {
            results.add(curated);
          }
        }
      }

      _searchResults = results;
    } catch (e) {
      debugPrint('[AddPlaceVM] search error: $e');
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  final Set<String> _selectedPlaceIds = {};
  Set<String> get selectedPlaceIds => Set.unmodifiable(_selectedPlaceIds);

  bool isSelected(String placeId) => _selectedPlaceIds.contains(placeId);

  void toggleSelection(String placeId) {
    if (_selectedPlaceIds.contains(placeId)) {
      _selectedPlaceIds.remove(placeId);
    } else {
      // Preview mode fits ONE place per AI insertion operation; legacy mode
      // keeps the original multi-select behaviour.
      if (isPreviewMode) _selectedPlaceIds.clear();
      _selectedPlaceIds.add(placeId);
    }
    notifyListeners();
  }

  // ─── Derived schedule info ──────────────────────────────────
  bool isSaving = false;
  String? saveError;

  /// Total free minutes left in the day's schedule (manual adds allow up to 23:00 / 1380 min).
  int get availableMinutes {
    const manualDayEndMinutes = 1380; // 23:00
    if (_existingStops.isEmpty) return manualDayEndMinutes - 540;

    final lastEnd = _existingStops
        .map((s) => _minutesOfDay(s.endTime))
        .reduce((a, b) => a > b ? a : b);
    final remaining = manualDayEndMinutes - lastEnd;
    return remaining > 0 ? remaining : 120;
  }

  ExplorationWindow get _window =>
      ItineraryConstants.explorationWindows[explorationTime] ??
      ItineraryConstants.explorationWindows['Standard']!;

  int _minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

  // ─── Load ───────────────────────────────────────────────────
  Future<void> load() async {
    isLoadingStops = true;
    loadError = null;
    notifyListeners();
    try {
      if (isPreviewMode) {
        _loadPreviewDayContext();
        await _retrieveDayCandidates();
      } else {
        final all = await _stopRepository.getStopsForItinerary(itineraryId);
        _existingStops = all.where((s) => s.dayIndex == dayIndex).toList()
          ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      }
    } catch (e) {
      loadError = 'Unable to load this day. Please try again.';
      debugPrint('[AddPlace] load error: $e');
    } finally {
      isLoadingStops = false;
      notifyListeners();
    }
  }

  /// Builds the display stop list from the CURRENT preview day (never the
  /// database) so the traveler always works against the latest state.
  void _loadPreviewDayContext() {
    final day = workingDay!;
    _existingStops = [
      for (var i = 0; i < day.stops.length; i++)
        ItineraryStop(
          stopId: 0,
          itineraryId: itineraryId,
          placeId: day.stops[i].attraction.place.placeId,
          dayIndex: day.dayIndex,
          stopOrder: i + 1,
          startTime: day.stops[i].startTime,
          endTime: day.stops[i].endTime,
          durationMinutes: day.stops[i].durationMinutes,
          travelFromPrevMinutes: day.stops[i].travelFromPreviousMinutes,
          stopStatus: day.stops[i].startTime == day.stops[i].endTime ? 'UNSCHEDULED' : 'PLANNED',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          place: day.stops[i].attraction.place,
        ),
    ];
  }

  // ─── Candidate retrieval for the selected day ───────────────
  Future<void> _retrieveDayCandidates() async {
    final day = workingDay!;
    isLoadingCandidates = true;
    candidatesError = null;
    _retrievedCandidates.clear();
    notifyListeners();

    try {
      final dayPlaces = day.stops.map((s) => s.attraction.place).toList();
      final anchors = InsertionAnchors(
        previousStop: dayPlaces.isNotEmpty ? dayPlaces.first : null,
        nextStop: dayPlaces.length > 1 ? dayPlaces.last : null,
      );
      final center = destinationCenter ??
          (dayPlaces.isNotEmpty ? dayPlaces.first.coordinates : null);

      // Search with expanded radius (8-10km) around the day's route endpoints / center
      final nearby = await _service.retrieveNearbyPlaces(
        anchors: anchors,
        interests: interests,
        fallbackCenter: center,
        radiusMeters: 8000,
      );

      // Filter: valid id, valid coordinates, not already used anywhere in the
      // itinerary, opening hours on the actual travel date.
      final usedIds = <String>{
        ...itineraryUsedPlaceIds,
        ...dayPlaces.map((p) => p.placeId),
      };
      var filtered = _service.filterCandidates(
        candidates: nearby,
        usedPlaceIds: usedIds,
        dayOfWeek: day.date.weekday,
      );

      // Destination compatibility — reuse the existing travel-area ceiling.
      if (center != null) {
        filtered = filtered
            .where((p) =>
                center.distanceTo(p.coordinates) <=
                ItineraryConstants.maxSearchRadiusKm)
            .toList();
      }

      final ranked = _service.rankCandidates(
        candidates: filtered,
        anchors: anchors,
        interests: interests,
        tripLocation: center,
        transportMode: transportMode,
      );

      for (final r in ranked.take(20)) {
        final p = r.place;
        if (usedIds.contains(p.placeId)) continue;
        _retrievedCandidates.add(AddPlaceOption(
          placeId: p.placeId,
          name: p.placeName,
          category: p.category ?? (p.placeTypes.isNotEmpty ? p.placeTypes.first.replaceAll('_', ' ').toUpperCase() : 'Attraction'),
          imageUrl: _photoUrl(p.placePhotoRef) ?? p.placeImageUrl ?? p.placePhotoGoogleMapsUri,
          durationMinutes: p.visitDurationMinutes ??
              ItineraryConstants.defaultDurationMinutes,
          rating: p.placeRating,
          userRatingsTotal: p.placeTotalReviews,
          address: p.placeAddress.isNotEmpty ? p.placeAddress : null,
          place: p,
        ));
      }

      // If retrieved candidates are few (< 8), supplement with famous curated places
      if (_retrievedCandidates.length < 8) {
        for (final curated in _curatedFamousPlaces) {
          if (!usedIds.contains(curated.placeId) &&
              !_retrievedCandidates.any((c) => c.placeId == curated.placeId)) {
            _retrievedCandidates.add(curated);
          }
        }
      }

      if (_retrievedCandidates.isEmpty) {
        candidatesError = 'No suitable places were found for this day.';
      }
    } catch (e) {
      debugPrint('[AddPlace] candidate retrieval failed: $e');
      // On network failure, fallback to curated famous places
      for (final curated in _curatedFamousPlaces) {
        if (!itineraryUsedPlaceIds.contains(curated.placeId)) {
          _retrievedCandidates.add(curated);
        }
      }
    } finally {
      isLoadingCandidates = false;
      notifyListeners();
    }
  }

  // ─── Validation ─────────────────────────────────────────────
  /// Business rules: at least one place selected, and each selected
  /// candidate must fit inside the remaining exploration window.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (_selectedPlaceIds.isEmpty) {
      errors['selection'] = 'Select at least one place to add.';
      return errors;
    }

    return errors;
  }

  // ─── Save ───────────────────────────────────────────────────
  Future<AddPlaceResult> addPlaces() async {
    if (isPreviewMode) return _addPlaceToPreviewDay();
    return _addPlacesLegacy();
  }

  /// Preview mode — AI proposes the insertion position, Dart builds the
  /// complete updated day and hard-validates it. Only the selected day is
  /// produced; the database is never written.
  Future<AddPlaceResult> _addPlaceToPreviewDay() async {
    final day = workingDay!;
    if (_selectedPlaceIds.any((id) => itineraryUsedPlaceIds.contains(id) ||
        day.stops.any((s) => s.attraction.place.placeId == id))) {
      return const AddPlaceResult(success: false, message: 'This place is already in your itinerary.');
    }
    if (_selectedPlaceIds.isEmpty) {
      return const AddPlaceResult(
          success: false, message: 'Select a place to add.');
    }
    AddPlaceOption? option;
    final allPools = [
      ..._searchResults,
      ..._retrievedCandidates,
      ..._curatedFamousPlaces,
    ];
    for (final c in allPools) {
      if (c.placeId == _selectedPlaceIds.first) {
        option = c;
        break;
      }
    }
    if (option == null) {
      return const AddPlaceResult(
          success: false, message: 'The selected place is no longer available.');
    }

    isSaving = true;
    saveError = null;
    notifyListeners();

      final effectivePlace = (option.place.placeImageUrl == null || option.place.placeImageUrl!.isEmpty) &&
              (option.imageUrl != null && option.imageUrl!.isNotEmpty)
          ? option.place.copyWith(placeImageUrl: option.imageUrl)
          : option.place;

    try {

      final existing = [
        for (final s in day.stops)
          ExistingStopContext(
            place: s.attraction.place,
            startTime: s.startTime,
            endTime: s.endTime,
            durationMinutes: s.durationMinutes,
            travelFromPrevMinutes: s.travelFromPreviousMinutes,
            isMustVisit: mustVisitPlaceIds.contains(s.attraction.place.placeId) ||
                s.attraction.isMustVisit,
          ),
      ];

      final plan = await _service.planInsertion(
        dayIndex: day.dayIndex,
        date: day.date,
        existingStops: existing,
        newPlace: effectivePlace,
        explorationTime: explorationTime,
        transportMode: transportMode,
        travelPace: travelPace,
        interests: interests,
        tripLocation: destinationCenter ??
            (existing.isNotEmpty ? existing.first.place.coordinates : null),
      );

      ScheduledDay? proposedDay;
      if (plan.success && plan.proposedDay != null) {
        proposedDay = plan.proposedDay;
      } else {
        debugPrint('[AddPlace] AI insertion did not fit automatically. Using fallback append.');
        final existingStops = day.stops;
        final defaultDuration = option.durationMinutes > 0 ? option.durationMinutes : 90;
        final lastEnd = existingStops.isNotEmpty
            ? existingStops.last.endTime
            : DateTime(day.date.year, day.date.month, day.date.day, 9, 0);

        int travelMins = 15;
        if (existingStops.isNotEmpty) {
          final lastCoords = existingStops.last.attraction.place.coordinates;
          final newCoords = effectivePlace.coordinates;
          if (lastCoords.latitude != 0 && newCoords.latitude != 0) {
            final distKm = lastCoords.distanceTo(newCoords);
            travelMins = ((distKm / 35.0) * 60).round().clamp(5, 120);
          }
        }
        final start = lastEnd.add(Duration(minutes: travelMins));
        final end = start.add(Duration(minutes: defaultDuration));

        final newStop = ScheduledStop(
          attraction: ScoredAttraction(
            place: effectivePlace,
            score: 0,
            breakdown: const {},
          ),
          startTime: start,
          endTime: end,
          durationMinutes: defaultDuration,
          travelFromPreviousMinutes: existingStops.isNotEmpty ? travelMins : 0,
          scheduleReason: 'Added by traveler',
          weatherNote: '',
        );

        final allStops = [...existingStops, newStop];
        proposedDay = ScheduledDay(
          dayIndex: day.dayIndex,
          date: day.date,
          stops: allStops,
          totalDuration: allStops.fold<int>(0, (sum, s) => sum + s.durationMinutes),
          totalTravelTime: allStops.fold<double>(0, (sum, s) => sum + s.travelFromPreviousMinutes),
        );
      }

      _selectedPlaceIds.clear();
      return AddPlaceResult(success: true, proposedDay: normalizeProposedDay(proposedDay!, explorationTime));
    } catch (e) {
      debugPrint('[AddPlace] AI insertion failed with error: $e. Using fallback append.');
      final existingStops = day.stops;
      final defaultDuration = option.durationMinutes > 0 ? option.durationMinutes : 90;
      final lastEnd = existingStops.isNotEmpty
          ? existingStops.last.endTime
          : DateTime(day.date.year, day.date.month, day.date.day, 9, 0);

      int travelMins = 15;
      if (existingStops.isNotEmpty) {
        final lastCoords = existingStops.last.attraction.place.coordinates;
        final newCoords = effectivePlace.coordinates;
        if (lastCoords.latitude != 0 && newCoords.latitude != 0) {
          final distKm = lastCoords.distanceTo(newCoords);
          travelMins = ((distKm / 35.0) * 60).round().clamp(5, 120);
        }
      }
      final start = lastEnd.add(Duration(minutes: travelMins));
      final end = start.add(Duration(minutes: defaultDuration));

      final newStop = ScheduledStop(
        attraction: ScoredAttraction(
          place: effectivePlace,
          score: 0,
          breakdown: const {},
        ),
        startTime: start,
        endTime: end,
        durationMinutes: defaultDuration,
        travelFromPreviousMinutes: existingStops.isNotEmpty ? travelMins : 0,
        scheduleReason: 'Added by traveler',
        weatherNote: '',
      );

      final allStops = [...existingStops, newStop];
      final proposedDay = ScheduledDay(
        dayIndex: day.dayIndex,
        date: day.date,
        stops: allStops,
        totalDuration: allStops.fold<int>(0, (sum, s) => sum + s.durationMinutes),
        totalTravelTime: allStops.fold<double>(0, (sum, s) => sum + s.travelFromPreviousMinutes),
      );

      _selectedPlaceIds.clear();
      return AddPlaceResult(success: true, proposedDay: normalizeProposedDay(proposedDay, explorationTime));
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  /// Legacy mode — append confirmed places as new stop rows (unchanged).
  Future<AddPlaceResult> _addPlacesLegacy() async {
    final errors = validate();
    if (errors.isNotEmpty) {
      return AddPlaceResult(success: false, message: errors.values.first);
    }

    isSaving = true;
    saveError = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final added = <ItineraryStop>[];

      // Base time: after the last existing stop (or window start).
      var cursor = _nextCursor();
      var nextOrder = _nextStopOrder();

      for (final candidate in candidates.where(
        (c) => _selectedPlaceIds.contains(c.placeId),
      )) {
        final base = dayDate ?? cursor;
        final midnight = DateTime(base.year, base.month, base.day);
        final limit = midnight.add(Duration(minutes:
          ItineraryConstants.explorationWindowFor(explorationTime).endMinutes));
        final proposedEnd = cursor.add(Duration(minutes: candidate.durationMinutes));
        final fits = cursor.isBefore(limit) && !proposedEnd.isAfter(limit) &&
            proposedEnd.isBefore(midnight.add(const Duration(days: 1)));
        final start = fits ? cursor : midnight;
        final end = fits ? proposedEnd : midnight;

        final effectivePlace = (candidate.place.placeImageUrl == null || candidate.place.placeImageUrl!.isEmpty) &&
                (candidate.imageUrl != null && candidate.imageUrl!.isNotEmpty)
            ? candidate.place.copyWith(placeImageUrl: candidate.imageUrl)
            : candidate.place;

        final stop = ItineraryStop(
          stopId: 0, // server-assigned
          itineraryId: itineraryId,
          placeId: candidate.placeId,
          dayIndex: dayIndex,
          stopOrder: nextOrder++,
          startTime: start,
          endTime: end,
          durationMinutes: candidate.durationMinutes,
          stopStatus: fits ? 'PLANNED' : 'UNSCHEDULED',
          place: effectivePlace,
          createdAt: now,
          updatedAt: now,
        );

        final saved = await _stopRepository.addStop(stop);
        added.add(saved.copyWith(place: saved.place ?? effectivePlace));

        // Advance cursor with a travel buffer between stops.
        cursor = proposedEnd.add(
          Duration(minutes: ItineraryConstants.bufferMinutes),
        );
      }

      _existingStops = [..._existingStops, ...added]
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      _selectedPlaceIds.clear();

      return AddPlaceResult(success: true, addedStops: added);
    } catch (e) {
      saveError = 'Failed to add: $e';
      return AddPlaceResult(success: false, message: 'Failed to add: $e');
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  DateTime _nextCursor() {
    final window = _window;
    if (_existingStops.isEmpty) {
      return DateTime(
        2024, 1, 1, window.startHour, window.startMinute,
      );
    }
    final last = _existingStops.last;
    return last.endTime.add(
      Duration(minutes: ItineraryConstants.bufferMinutes),
    );
  }

  int _nextStopOrder() {
    if (_existingStops.isEmpty) return 0;
    return _existingStops
            .map((s) => s.stopOrder)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  String? _photoUrl(String? photoRef) {
    if (photoRef == null || photoRef.isEmpty) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=400&photoreference=$photoRef'
        '&key=${ApiKeys.googleMapsApiKey}';
  }
}
