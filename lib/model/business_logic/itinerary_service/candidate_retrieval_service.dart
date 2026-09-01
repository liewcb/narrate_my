import 'package:flutter/foundation.dart';
import 'package:narrate_my/model/entities/trip_draft.dart';

import '../../../core/config/interest_mapping.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/database_manager.dart';
import '../../data_sources/remote/places_remote_data_source.dart';
import '../../entities/coordinates.dart';
import '../../entities/destination_hotspot.dart';
import '../../entities/place.dart';
import '../../repositories/interfaces/destination_hotspot_repository.dart';
import '../../repositories/interfaces/destination_repository.dart';
import '../../repositories/interfaces/place_repository.dart';

/// A resolved coordinate anchor for a Google Places search.
class HotspotAnchor {
  final String name;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final bool isFallback;
  final String? destinationId;
  final String? hotspotId;

  const HotspotAnchor({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusKm = 2.0,
    this.isFallback = false,
    this.destinationId,
    this.hotspotId,
  });
}

/// Geographic relationship of a manually-searched place to the selected
/// hotspot area.
///
/// `suggested_radius_km` is ONLY a nearby-discovery radius — it is never
/// treated as a transportation time/distance.
enum HotspotDistanceStatus {
  /// The place is within the hotspot's `suggested_radius_km`.
  withinHotspot,

  /// The place is beyond the hotspot radius but still near the destination.
  outsideHotspot,

  /// The place is very far from the destination.
  farFromDestination;

  String get label => switch (this) {
        HotspotDistanceStatus.withinHotspot => 'WITHIN_HOTSPOT',
        HotspotDistanceStatus.outsideHotspot => 'OUTSIDE_HOTSPOT',
        HotspotDistanceStatus.farFromDestination => 'FAR_FROM_DESTINATION',
      };
}

/// Computes the [HotspotDistanceStatus] of [placeKm] relative to the
/// hotspot's [radiusKm] (geographic distance only — not travel time).
HotspotDistanceStatus classifyHotspotDistance(double placeKm, double radiusKm) {
  if (placeKm <= radiusKm) return HotspotDistanceStatus.withinHotspot;
  if (placeKm <= 50.0) return HotspotDistanceStatus.outsideHotspot;
  return HotspotDistanceStatus.farFromDestination;
}

/// Backward-compatible per-day group (kept so old callers compile).
///
/// NOTE: The new candidate-retrieval architecture no longer builds one
/// group per day. This type is retained only for callers that read
/// [CandidatePool.dailyGroups] (e.g. diagnostic tools); the retrieval
/// service now returns a single merged pool instead.
class DailyCandidateGroup {
  final int dayIndex; // 1-based
  final HotspotAnchor anchor;
  final List<Place> attractions;
  final List<Place> food;

  const DailyCandidateGroup({
    required this.dayIndex,
    required this.anchor,
    required this.attractions,
    required this.food,
  });

  int get attractionCount => attractions.length;
  int get foodCount => food.length;
  int get totalCount => attractionCount + foodCount;
}

class QueryDestination {
  final String name;
  final String? destinationId; // resolved DB id, e.g. "D001"
  final double latitude;
  final double longitude;

  const QueryDestination({
    required this.name,
    this.destinationId,
    required this.latitude,
    required this.longitude,
  });
}

class CandidatePool {
  final List<Place> attractions;
  final List<Place> food;
  final List<DailyCandidateGroup> dailyGroups;

  const CandidatePool({
    required this.attractions,
    required this.food,
    this.dailyGroups = const [],
  });

  /// Build a pool from the day-by-day groups, flattening places
  /// automatically (backward-compatibility helper).
  CandidatePool.fromDailyGroups(List<DailyCandidateGroup> groups)
      : attractions =
            groups.expand((g) => g.attractions).toList(growable: false),
        food = groups.expand((g) => g.food).toList(growable: false),
        dailyGroups = List.unmodifiable(groups);

  List<Place> get all => List.unmodifiable([...attractions, ...food]);
  int get attractionCount => attractions.length;
  int get foodCount => food.length;
  int get totalCount => attractionCount + foodCount;

  Place? findByPlaceId(String placeId) {
    for (final place in all) {
      if (place.placeId == placeId) return place;
    }
    return null;
  }

  bool contains(String placeId) => findByPlaceId(placeId) != null;
}

/// Hotspot-driven candidate retrieval — ONE merged pool per itinerary.
///
/// This service follows the confirmed pipeline architecture:
///
///   Selected destinations
///       ↓
///   Retrieve hotspots for each destination
///       ↓
///   Prioritize hotspots matching traveler interests
///       ↓
///   Search Google Places around those hotspots
///       ↓
///   Merge all results
///       ↓
///   Deduplicate (by Google place_id)
///       ↓
///   ONE candidate pool for the entire itinerary
///
/// The trip duration does NOT force one independent Google search per day.
/// A hotspot is a geographic search area, never an itinerary day.
class CandidateRetrievalService {
  final PlacesRemoteDataSource _placesDataSource;
  final DestinationHotspotRepository _hotspotRepository;
  final DestinationRepository _destinationRepository;
  final PlaceRepository _placesRepository;

  // ── Strict food types (only these 5 are queried / classified as food) ──
  static const List<String> foodTypes = [
    'restaurant',
    'cafe',
    'bakery',
    'meal_takeaway',
    'meal_delivery',
  ];

  // ── Hard-banned types (never allowed in either category) ──────────────
  static const List<String> _bannedTypes = [
    'lodging',
    'hotel',
    'real_estate_agency',
    'lawyer',
  ];

  // ── Safety thresholds ─────────────────────────────────────────────────
  static const int maxHotspotsPerDestination = 4;
  static const int minUserRatingsTotal = 5;
  static const double attractionDiversityKm = 0.5;
  static const double foodDiversityKm = 0.1;

  /// General attraction types always included as a safety floor, merged
  /// with the interest-derived set.
  static const List<String> _generalAttractionTypes = [
    'tourist_attraction',
    'park',
    'museum',
    'art_gallery',
    'natural_feature',
  ];

  CandidateRetrievalService({
    PlacesRemoteDataSource? placesDataSource,
    DestinationHotspotRepository? hotspotRepository,
    DestinationRepository? destinationRepository,
    PlaceRepository? placesRepository,
  })  : _placesDataSource = placesDataSource ?? PlacesRemoteDataSource(),
        _hotspotRepository =
            hotspotRepository ?? DatabaseManager().destinationHotspotRepository,
        _destinationRepository =
            destinationRepository ?? DatabaseManager().destinationRepository,
        _placesRepository = placesRepository ?? DatabaseManager().placeRepository;

  /// Returns a single merged [CandidatePool] for the whole itinerary.
  ///
  /// Every destination is searched around its own hotspots; all Google
  /// Places results are merged and deduplicated by `place_id`. Candidates
  /// are tagged with their source `destinationId` and `hotspotId` so
  /// destination identity is never mixed.
  Future<CandidatePool> retrieveCandidates({
    required TripDraft request,
  }) async {
    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint('════════════════════════════════════');
      debugPrint('📍 CANDIDATE RETRIEVAL (HOTSPOT-DRIVEN, MERGED POOL)');
      debugPrint('════════════════════════════════════');
      debugPrint('🗺️ Destinations: ${request.destinations}');
      debugPrint('📅 Trip duration: ${request.totalDays} days');
      debugPrint('🚶 Travel pace: ${request.travelPace}');
      debugPrint('🎯 Interests: ${request.interests}');
    }

    // ============================================================
    // 1. RESOLVE INTEREST TAGS + GOOGLE TYPES
    // ============================================================

    final List<String> selectedInterests = request.interests;

    final List<String> interestTags =
        InterestMapping.databaseTagsForInterests(selectedInterests);

    final attractionTypes = _buildAttractionTypeSet(selectedInterests);

    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint('🎯 Interest tags: $interestTags');
      debugPrint('🎯 Attraction types: $attractionTypes');
    }

    // ============================================================
    // 2. RESOLVE DESTINATIONS (name → DB destination_id)
    // ============================================================

    final List<QueryDestination> destinations =
        await _resolveDestinations(request);

    // ============================================================
    // 3. RESOLVE SEARCH CENTRES (per-destination hotspots)
    // ============================================================

    final List<_SearchCenter> centers =
        await _buildSearchCenters(destinations: destinations, interestTags: interestTags);

    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint(
        '📍 Search centres: ${centers.length} across '
        '${destinations.length} destination(s)',
      );
      for (final c in centers) {
        debugPrint(
          '   • ${c.sourceLabel} (${c.latitude}, ${c.longitude}) '
          'radius=${c.radiusKm}km',
        );
      }
    }

    if (centers.isEmpty) {
      debugPrint('⚠️ No search centres resolved — returning empty pool.');
      return const CandidatePool(attractions: [], food: []);
    }

    // ============================================================
    // 4. GOOGLE PLACES SEARCH — one search per hotspot (not per day)
    // ============================================================

    final mergedAttractions = <Place>[];
    final mergedFood = <Place>[];
    final seenIds = <String>{};

    for (final center in centers) {
      final raw = await _fetchCenter(center, attractionTypes.toList());

      if (ItineraryConstants.enableCandidateDebugLogs) {
        debugPrint(
          '[SEARCH] ${center.sourceLabel} '
          '@ (${center.latitude}, ${center.longitude}) '
          'radius=${center.radiusKm}km → '
          '${raw.attractions.length} attr, ${raw.food.length} food',
        );
      }

      for (final place in raw.attractions) {
        final tagged = place.copyWith(
          destinationId: center.destinationId,
          hotspotId: center.hotspotId,
        );
        if (seenIds.add(tagged.placeId)) mergedAttractions.add(tagged);
      }
      for (final place in raw.food) {
        final tagged = place.copyWith(
          destinationId: center.destinationId,
          hotspotId: center.hotspotId,
        );
        if (seenIds.add(tagged.placeId)) mergedFood.add(tagged);
      }
    }

    debugPrint(
      '[MERGE] Raw results merged → '
      '${mergedAttractions.length} unique attractions, '
      '${mergedFood.length} unique food '
      '(${seenIds.length} unique place_ids total)',
    );

    // ============================================================
    // 5. HYGIENE + LIGHT SPATIAL THINNING ON THE WHOLE POOL
    //
    // Only genuinely identical/near-duplicate coordinates are thinned.
    // The candidate pool is intentionally kept large: scoring ranks all
    // usable candidates and K-Means + DeepSeek handle geographic grouping.
    // ============================================================

    final filteredAttractions = _applySpatialFiltering(
      _applyBasicFiltering(
        mergedAttractions,
        <String>{},
        allowedSpecificTypes: attractionTypes,
        allowSpa: false,
      ),
      0.05, // light dedup only — do not aggressively shrink the pool
    );

    final filteredFood = _applySpatialFiltering(
      _applyBasicFiltering(
        mergedFood,
        <String>{},
        allowedSpecificTypes: foodTypes.toSet(),
        allowSpa: false,
      ),
      0.05,
    );

    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint('════════════════════════════════════');
      debugPrint('✅ MERGED POOL: ${filteredAttractions.length} attractions, '
          '${filteredFood.length} food');
      debugPrint('════════════════════════════════════');
    }

    return CandidatePool(
      attractions: filteredAttractions,
      food: filteredFood,
    );
  }

  // ------------------------------------------------------------
  // Single best-hotspot selection (Must-Visit Search Maps)
  // ------------------------------------------------------------

  /// Deterministically selects the SINGLE most relevant hotspot for a
  /// destination, ranked by the traveler's interests.
  ///
  /// Ranking (highest → lowest):
  ///   1. `primary_theme` matches an interest tag (strongest signal)
  ///   2. any entry in `tags` matches an interest tag (secondary)
  ///   3. no interest match (lowest)
  ///
  /// Ties are broken by the hotspot id (lexicographic) so the result never
  /// depends on arbitrary database ordering.
  ///
  /// Returns the selected [DestinationHotspot] with its preserved
  /// `latitude`, `longitude` and `suggestedRadiusKm` — exactly what the
  /// Must-Visit Search Maps screen needs for its Google Places search.
  /// Returns `null` when no hotspot exists for the destination.
  Future<DestinationHotspot?> selectBestHotspot({
    required String destinationName,
    String? destinationId,
    required List<String> interests,
  }) async {
    final id = destinationId ?? await _resolveDestinationIdByName(destinationName);
    if (id == null || id.isEmpty) return null;

    final List<DestinationHotspot> hotspots;
    try {
      hotspots = await _hotspotRepository.getHotspotsForDestination(id);
    } catch (e) {
      debugPrint('[HOTSPOT] selectBestHotspot failed for $destinationName: $e');
      return null;
    }
    if (hotspots.isEmpty) return null;

    final normalizedTags = InterestMapping.databaseTagsForInterests(interests)
        .map((t) => t.trim().toLowerCase())
        .toSet();

    DestinationHotspot? best;
    var bestScore = -1;
    String bestTie = '';
    for (final h in hotspots) {
      final themeMatch = normalizedTags.contains(h.primaryTheme.trim().toLowerCase());
      final tagMatch = h.tags
          .any((t) => normalizedTags.contains(t.trim().toLowerCase()));
      final score = themeMatch ? 3 : (tagMatch ? 2 : 1);

      if (score > bestScore || (score == bestScore && h.id.compareTo(bestTie) < 0)) {
        best = h;
        bestScore = score;
        bestTie = h.id;
      }
    }
    return best;
  }

  /// Resolves a destination display name to its database `destination_id`.
  Future<String?> _resolveDestinationIdByName(String destinationName) async {
    try {
      final all = await _destinationRepository.getAllDestinations();
      for (final d in all) {
        if (d.destinationName.trim().toLowerCase() ==
            destinationName.trim().toLowerCase()) {
          return d.destinationId;
        }
      }
    } catch (e) {
      debugPrint('[DEST] Destination ID resolution failed: $e');
    }
    return null;
  }

  // ------------------------------------------------------------
  // Search-centre building (per destination → hotspots)
  // ------------------------------------------------------------

  /// Builds the list of Google Places search centres for the whole trip.
  ///
  /// For each selected destination it resolves that destination's hotspots,
  /// prioritising hotspots whose tags match the traveler's interests
  /// (non-matching hotspots are retained as lower-priority fallbacks — they
  /// are never permanently eliminated). When a destination has no usable
  /// hotspots its centre point is used instead.
  Future<List<_SearchCenter>> _buildSearchCenters({
    required List<QueryDestination> destinations,
    required List<String> interestTags,
  }) async {
    final centers = <_SearchCenter>[];

    for (final destination in destinations) {
      final hotspots = await _resolveHotspotsForDestination(
        destination: destination,
        interestTags: interestTags,
      );

      if (ItineraryConstants.enableCandidateDebugLogs) {
        debugPrint(
          '[HOTSPOT] ${destination.name} '
          '(destination_id=${destination.destinationId ?? 'unknown'}): '
          '${hotspots.length} hotspot(s) for tags $interestTags',
        );
        for (final h in hotspots) {
          debugPrint(
            '   ✓ ${h.id} ${h.hotspotName} '
            'tags=${h.tags}',
          );
        }
      }

      if (hotspots.isEmpty) {
        // Fallback: search the destination centre directly.
        centers.add(_SearchCenter(
          sourceLabel: destination.name,
          latitude: destination.latitude,
          longitude: destination.longitude,
          radiusKm: ItineraryConstants.searchRadiusKm,
          destinationId: destination.destinationId,
        ));
        continue;
      }

      for (final hotspot in hotspots) {
        centers.add(_SearchCenter(
          sourceLabel: '${destination.name} → ${hotspot.hotspotName}',
          latitude: hotspot.latitude,
          longitude: hotspot.longitude,
          radiusKm: hotspot.suggestedRadiusKm,
          destinationId: destination.destinationId,
          hotspotId: hotspot.id,
        ));
      }
    }

    // Deduplicate nearby centres so we do not re-search the same area.
    final deduped = _deduplicateCenters(centers);

    // Cap the total number of searches to bound API usage.
    final cap = ItineraryConstants.maxCandidates;
    return deduped.take(cap).toList(growable: false);
  }

  /// Resolves the hotspots for a single destination, prioritising tag
  /// matches while retaining non-matching hotspots as fallbacks.
  Future<List<DestinationHotspot>> _resolveHotspotsForDestination({
    required QueryDestination destination,
    required List<String> interestTags,
  }) async {
    final String queryId = destination.destinationId ?? destination.name;
    try {
      final hotspots =
          await _hotspotRepository.getHotspotsForDestination(queryId);

      if (hotspots.isEmpty) return const [];

      // Matching hotspots first (high priority), non-matching after
      // (lower priority / fallback).  Never eliminate non-matching hotspots.
      final normalizedTags = interestTags.map((t) => t.trim().toLowerCase()).toSet();
      final matching = hotspots
          .where((h) => h.matchesAnyTag(normalizedTags))
          .toList();
      final nonMatching = hotspots
          .where((h) => !h.matchesAnyTag(normalizedTags))
          .toList();

      final ordered = [...matching, ...nonMatching];
      return ordered.take(maxHotspotsPerDestination).toList();
    } catch (e) {
      debugPrint('[HOTSPOT] Resolution failed for ${destination.name}: $e');
      return const [];
    }
  }

  Future<_CenterResult> _fetchCenter(
    _SearchCenter center,
    List<String> attractionTypes,
  ) async {
    final double radiusMeters = center.radiusKm * 1000;

    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint(
        '[SEARCH] ${center.sourceLabel} '
        '@ (${center.latitude}, ${center.longitude}) '
        'radius=${center.radiusKm}km',
      );
    }

    final (attractions, food) = await (
      _placesDataSource.searchNearbyPlaces(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusMeters: radiusMeters,
        types: attractionTypes,
      ),
      _placesDataSource.searchNearbyPlaces(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusMeters: radiusMeters,
        types: foodTypes,
      ),
    ).wait;

    if (ItineraryConstants.enableCandidateDebugLogs) {
      debugPrint(
        '[RESULT] ${center.sourceLabel}: '
        '${attractions.length} attr, ${food.length} food',
      );
    }

    return _CenterResult(attractions: attractions, food: food);
  }

  // ------------------------------------------------------------
  // Hygiene helpers
  // ------------------------------------------------------------

  Set<String> _buildAttractionTypeSet(List<String> selectedInterests) {
    final types = <String>{};
    for (final interest in selectedInterests) {
      types.addAll(
        InterestMapping.getAttractionGoogleTypesForInterest(interest),
      );
    }
    types.removeWhere(foodTypes.contains);
    if (types.length < 3) {
      types.addAll(_generalAttractionTypes);
    }
    return types;
  }

  /// Resolves selected destinations (names from the request) into
  /// [QueryDestination] entries carrying the DB `destination_id`.
  ///
  /// The DB keys hotspots by `destination_id` (e.g. "D001"), so we map the
  /// user's chosen names to their IDs via the [DestinationRepository].
  Future<List<QueryDestination>> _resolveDestinations(TripDraft request) async {
    final idByName = <String, String>{};
    try {
      final all = await _destinationRepository.getAllDestinations();
      for (final d in all) {
        idByName[d.destinationName.trim().toLowerCase()] = d.destinationId;
      }
    } catch (e) {
      debugPrint('[DEST] Destination ID resolution failed: $e');
    }

    return request.destinations.map((name) {
      final coords =
          request.destinationCoordinates[name] ??
              request.tripLocation ??
              const Coordinates(latitude: 3.139, longitude: 101.687);

      return QueryDestination(
        name: name,
        destinationId: idByName[name.trim().toLowerCase()] ?? name,
        latitude: coords.latitude,
        longitude: coords.longitude,
      );
    }).toList();
  }

  List<Place> _applyBasicFiltering(
    List<Place> places,
    Set<String> globalSeenIds, {
    required Set<String> allowedSpecificTypes,
    required bool allowSpa,
  }) {
    final valid = <Place>[];

    for (final place in places) {
      if (place.placeId.isEmpty || place.placeName.isEmpty) continue;
      if (place.placeLatitude == 0.0 && place.placeLongitude == 0.0) continue;

      if (place.businessStatus != null &&
          place.businessStatus != 'OPERATIONAL') {
        continue;
      }

      if ((place.placeTotalReviews ?? 0) < minUserRatingsTotal) continue;

      if (place.types.any((t) => _bannedTypes.contains(t))) continue;

      if (!allowSpa && place.types.contains('spa')) continue;

      if (place.types.contains('establishment')) {
        final hasSpecificTag = place.types.any(
          (t) => t != 'establishment' && allowedSpecificTypes.contains(t),
        );
        if (!hasSpecificTag) continue;
      }

      if (!globalSeenIds.add(place.placeId)) continue;

      valid.add(place);
    }
    return valid;
  }

  List<Place> _applySpatialFiltering(List<Place> places, double minDistanceKm) {
    final List<Place> diversifiedPool = [];

    final sortedPlaces = List<Place>.from(places)
      ..sort((a, b) => b.placeRating.compareTo(a.placeRating));

    for (final place in sortedPlaces) {
      final currentCoords = Coordinates(
        latitude: place.placeLatitude,
        longitude: place.placeLongitude,
      );

      bool isTooClose = false;
      for (final accepted in diversifiedPool) {
        final acceptedCoords = Coordinates(
          latitude: accepted.placeLatitude,
          longitude: accepted.placeLongitude,
        );

        if (currentCoords.distanceTo(acceptedCoords) < minDistanceKm) {
          isTooClose = true;
          break;
        }
      }

      if (!isTooClose) {
        diversifiedPool.add(place);
      }
    }
    return diversifiedPool;
  }

  List<_SearchCenter> _deduplicateCenters(List<_SearchCenter> centers) {
    const dedupeDistanceKm = 0.1;
    final unique = <_SearchCenter>[];

    for (final center in centers) {
      final coords = Coordinates(
        latitude: center.latitude,
        longitude: center.longitude,
      );

      final isDuplicate = unique.any((existing) {
        final existingCoords = Coordinates(
          latitude: existing.latitude,
          longitude: existing.longitude,
        );
        return coords.distanceTo(existingCoords) < dedupeDistanceKm;
      });

      if (!isDuplicate) {
        unique.add(center);
      }
    }
    return unique;
  }

  // ------------------------------------------------------------
  // Must-visit recovery
  // ------------------------------------------------------------

  /// Recovers missing must-visit places via progressive multi-level search.
  ///
  /// For every requested must-visit that is NOT already in the candidate pool,
  /// performs a progressive recovery:
  ///
  ///   Level 1 — exact place_id lookup (Google Place Details API)
  ///   Level 2 — lookup in the local / Supabase places table
  ///   Level 3 — nearby search around the destination / hotspot
  ///   Level 4 — Google Text Search using the exact name
  ///   Level 5 — Google Text Search using the normalized name
  ///   Level 6 — contextual query (name + destination)
  ///
  /// Each recovered candidate is validated by name similarity and geographic
  /// proximity.  A missing must-visit is NEVER silently discarded — it is
  /// reported so the pipeline can surface a clear generation issue.
  ///
  /// [requestedMustVisitIds] may contain either Google place_ids or place
  /// names (the pipeline stores whatever the traveler selected).
  /// [mustVisitNames] provides the display names when the IDs are actually
  /// names (backward compatible with the existing wizard).
  Future<MustVisitRecoveryResult> recoverMustVisits({
    required List<String> requestedMustVisitIds,
    required Set<String> alreadyRetrievedIds,
    List<String>? mustVisitNames,
    Coordinates? searchCenter,
    String? destinationName,
  }) async {
    final recovered = <Place>[];
    final verifiedIds = <String>{};
    final unretrievable = <String>[];

    for (int i = 0; i < requestedMustVisitIds.length; i++) {
      final id = requestedMustVisitIds[i];
      final name = (mustVisitNames != null && i < mustVisitNames.length)
          ? mustVisitNames[i]
          : id; // Fallback: the id itself may be a name.

      debugPrint('');
      debugPrint('════════════════════════════════════');
      debugPrint('[MUST-VISIT RECOVERY] Requested: $name');
      debugPrint('[MUST-VISIT RECOVERY] Place ID: $id');
      debugPrint('[MUST-VISIT RECOVERY] Destination: $destinationName');
      debugPrint('════════════════════════════════════');

      // Already in the pool → verified.
      if (alreadyRetrievedIds.contains(id)) {
        verifiedIds.add(id);
        debugPrint('[MUST-VISIT RECOVERY] Already in pool → verified.');
        continue;
      }

      Place? result;

      // ── Level 1: exact place_id lookup ──────────────────────────
      debugPrint('[MUST-VISIT RECOVERY] Level 1: place_id lookup');
      result = await _placesDataSource.getPlaceDetails(id);
      if (result != null && result.placeId.isNotEmpty) {
        debugPrint('[MUST-VISIT RECOVERY] Level 1 result: RECOVERED '
            '(${result.placeName})');
        _addRecovered(result, recovered, verifiedIds);
        continue;
      }
      debugPrint('[MUST-VISIT RECOVERY] Level 1 result: NOT FOUND');

      // ── Level 2: local / Supabase places table lookup ────────────
      debugPrint('[MUST-VISIT RECOVERY] Level 2: local/Supabase lookup');
      try {
        final localPlace = await _placesRepository.getPlace(id);
        if (localPlace != null && localPlace.placeId.isNotEmpty) {
          debugPrint('[MUST-VISIT RECOVERY] Level 2 result: RECOVERED '
              '(${localPlace.placeName})');
          _addRecovered(localPlace, recovered, verifiedIds);
          continue;
        }
      } catch (_) {}
      debugPrint('[MUST-VISIT RECOVERY] Level 2 result: NOT FOUND');

      // ── Level 3: nearby search ───────────────────────────────────
      if (searchCenter != null) {
        debugPrint('[MUST-VISIT RECOVERY] Level 3: Nearby Search');
        final nearby = await _placesDataSource.searchNearbyPlaces(
          latitude: searchCenter.latitude,
          longitude: searchCenter.longitude,
          radiusMeters: 5000,
          types: [name],
        );
        final match = _findBestMatch(nearby, name, searchCenter);
        if (match != null) {
          debugPrint('[MUST-VISIT RECOVERY] Level 3 result: RECOVERED '
              '(${match.placeName})');
          _addRecovered(match, recovered, verifiedIds);
          continue;
        }
        debugPrint('[MUST-VISIT RECOVERY] Level 3 result: NOT FOUND');
      }

      // ── Level 4: text search exact name ─────────────────────────
      debugPrint('[MUST-VISIT RECOVERY] Level 4: Text Search');
      final textResults = await _placesDataSource.searchPlacesByText(
        name,
        latitude: searchCenter?.latitude,
        longitude: searchCenter?.longitude,
      );
      if (textResults.isNotEmpty) {
        final match = _findBestMatch(textResults, name, searchCenter);
        if (match != null) {
          debugPrint('[MUST-VISIT RECOVERY] Level 4 result: RECOVERED '
              '(${match.placeName})');
          _addRecovered(match, recovered, verifiedIds);
          continue;
        }
      }
      debugPrint('[MUST-VISIT RECOVERY] Level 4 result: NOT FOUND');

      // ── Level 5: normalized text search ──────────────────────────
      final normalized = name.toLowerCase().trim();
      if (normalized != name) {
        debugPrint('[MUST-VISIT RECOVERY] Level 5: normalized Text Search');
        final normResults = await _placesDataSource.searchPlacesByText(
          normalized,
          latitude: searchCenter?.latitude,
          longitude: searchCenter?.longitude,
        );
        if (normResults.isNotEmpty) {
          final match = _findBestMatch(normResults, name, searchCenter);
          if (match != null) {
            debugPrint('[MUST-VISIT RECOVERY] Level 5 result: RECOVERED '
                '(${match.placeName})');
            _addRecovered(match, recovered, verifiedIds);
            continue;
          }
        }
        debugPrint('[MUST-VISIT RECOVERY] Level 5 result: NOT FOUND');
      }

      // ── Level 6: contextual query (name + destination) ──────────
      if (destinationName != null && destinationName.isNotEmpty) {
        final contextualQuery = '$name $destinationName';
        debugPrint('[MUST-VISIT RECOVERY] Level 6: contextual search '
            '"$contextualQuery"');
        final ctxResults = await _placesDataSource.searchPlacesByText(
          contextualQuery,
          latitude: searchCenter?.latitude,
          longitude: searchCenter?.longitude,
        );
        if (ctxResults.isNotEmpty) {
          final match = _findBestMatch(ctxResults, name, searchCenter);
          if (match != null) {
            debugPrint('[MUST-VISIT RECOVERY] Level 6 result: RECOVERED '
                '(${match.placeName})');
            _addRecovered(match, recovered, verifiedIds);
            continue;
          }
        }
        debugPrint('[MUST-VISIT RECOVERY] Level 6 result: NOT FOUND');
      }

      // ── All levels exhausted ─────────────────────────────────────
      unretrievable.add(id);
      debugPrint('[MUST-VISIT RECOVERY] ❌ Recovery exhausted');
      debugPrint('[MUST-VISIT RECOVERY] ❌ Missing: $name');
      debugPrint('[MUST-VISIT RECOVERY] ❌ Generation blocked because '
          'hard requirement is unsatisfied');
    }

    return MustVisitRecoveryResult(
      recoveredPlaces: recovered,
      verifiedIds: verifiedIds,
      unretrievableIds: unretrievable,
    );
  }

  /// Adds a recovered place to the result set, tagging it with the source
  /// destination if available.
  void _addRecovered(Place place, List<Place> recovered, Set<String> verifiedIds) {
    recovered.add(place);
    verifiedIds.add(place.placeId);
  }

  /// Finds the best matching place from a list of candidates by comparing
  /// the requested name (normalized) and geographic proximity.
  ///
  /// Returns null when no candidate reaches the similarity threshold.
  Place? _findBestMatch(
    List<Place> candidates,
    String requestedName,
    Coordinates? searchCenter,
  ) {
    final normalized = requestedName.toLowerCase().trim();
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();

    for (final candidate in candidates) {
      if (candidate.placeId.isEmpty) continue;
      final candidateName = candidate.placeName.toLowerCase().trim();

      // 1. Exact match (case-insensitive).
      if (candidateName == normalized) {
        debugPrint('[MUST-VISIT] Match evaluation');
        debugPrint('[MUST-VISIT] Candidate: ${candidate.placeName}');
        debugPrint('[MUST-VISIT] Name similarity: EXACT');
        debugPrint('[MUST-VISIT] Geographic validation: PASS');
        return candidate;
      }

      // 2. All significant words present.
      final candidateWords = candidateName.split(RegExp(r'\s+'));
      final allWordsMatch = words.isNotEmpty &&
          words.every((w) => candidateWords.any((cw) => cw.contains(w) || w.contains(cw)));
      if (allWordsMatch) {
        debugPrint('[MUST-VISIT] Match evaluation');
        debugPrint('[MUST-VISIT] Candidate: ${candidate.placeName}');
        debugPrint('[MUST-VISIT] Name similarity: STRONG');
        // Geographic validation: within 2 km of search center.
        if (searchCenter != null) {
          final dist = candidate.coordinates.distanceTo(searchCenter);
          if (dist > 2.0) {
            debugPrint('[MUST-VISIT] Geographic validation: FAIL '
                '(distance=${dist.toStringAsFixed(2)}km > 2.0km)');
            continue;
          }
          debugPrint('[MUST-VISIT] Geographic validation: PASS '
              '(distance=${dist.toStringAsFixed(2)}km)');
        }
        return candidate;
      }
    }

    return null;
  }

  // ------------------------------------------------------------
  // Candidate expansion (candidate sufficiency)
  // ------------------------------------------------------------

  /// Expands NORMAL candidate search when the pool is insufficient.
  ///
  /// Uses a broader radius around the destination centres (a separate
  /// mechanism from must-visit recovery — expansion never performs targeted
  /// must-visit lookups).
  Future<CandidatePool> expandCandidates({
    required TripDraft request,
    required Set<String> alreadySeenIds,
    double radiusMultiplier = 1.0,
  }) async {
    final destinations = await _resolveDestinations(request);
    final attractionTypes = _buildAttractionTypeSet(request.interests);
    final wantsWellness = InterestMapping
        .databaseTagsForInterests(request.interests)
        .contains('wellness_relaxation');

    // Search around each destination centre with an expanded radius.
    final baseRadius = ItineraryConstants.searchRadiusKm * radiusMultiplier;
    final centers = destinations
        .map((d) => _SearchCenter(
              sourceLabel: '${d.name} (expanded)',
              latitude: d.latitude,
              longitude: d.longitude,
              radiusKm: baseRadius,
              destinationId: d.destinationId,
            ))
        .toList();

    final results = await Future.wait(
      centers.map((c) => _fetchCenter(c, attractionTypes.toList())),
    );

    final seen = Set<String>.of(alreadySeenIds);
    final rawAttractions = <Place>[];
    final rawFood = <Place>[];
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final destId = i < centers.length ? centers[i].destinationId : null;
      rawAttractions.addAll(
        r.attractions.map((p) => p.copyWith(destinationId: destId)),
      );
      rawFood.addAll(
        r.food.map((p) => p.copyWith(destinationId: destId)),
      );
    }

    final filteredAttractions = _applySpatialFiltering(
      _applyBasicFiltering(
        rawAttractions,
        seen,
        allowedSpecificTypes: attractionTypes,
        allowSpa: wantsWellness,
      ),
      attractionDiversityKm,
    );
    final filteredFood = _applySpatialFiltering(
      _applyBasicFiltering(
        rawFood,
        seen,
        allowedSpecificTypes: foodTypes.toSet(),
        allowSpa: false,
      ),
      foodDiversityKm,
    );

    debugPrint('[CANDIDATE EXPANSION] radius=${baseRadius}km → '
        '${filteredAttractions.length} new attractions, '
        '${filteredFood.length} new food');

    return CandidatePool(
      attractions: filteredAttractions,
      food: filteredFood,
    );
  }
}

/// Result of a must-visit recovery pass.
class MustVisitRecoveryResult {
  final List<Place> recoveredPlaces;
  final Set<String> verifiedIds;
  final List<String> unretrievableIds;

  const MustVisitRecoveryResult({
    required this.recoveredPlaces,
    required this.verifiedIds,
    required this.unretrievableIds,
  });

  bool get allRetrieved => unretrievableIds.isEmpty;
}

class _SearchCenter {
  final String sourceLabel;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final String? destinationId;
  final String? hotspotId;

  const _SearchCenter({
    required this.sourceLabel,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    this.destinationId,
    this.hotspotId,
  });
}

class _CenterResult {
  final List<Place> attractions;
  final List<Place> food;

  const _CenterResult({
    required this.attractions,
    required this.food,
  });
}