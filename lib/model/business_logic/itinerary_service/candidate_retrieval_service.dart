import 'package:flutter/foundation.dart';
import 'package:narrate_my/model/entities/trip_draft.dart';

import '../../../core/config/interest_mapping.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../data_sources/remote/places_remote_data_source.dart';
import '../../entities/coordinates.dart';
import '../../entities/destination_hotspot.dart';
import '../../entities/place.dart';
import '../../repositories/adapters/destination_hotspot_repository_adapter.dart';
import '../../repositories/adapters/destination_repository_adapter.dart';
import '../../repositories/interfaces/destination_hotspot_repository.dart';
import '../../repositories/interfaces/destination_repository.dart';

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
  })  : _placesDataSource = placesDataSource ?? PlacesRemoteDataSource(),
        _hotspotRepository = hotspotRepository ?? DestinationHotspotRepositoryImpl(),
        _destinationRepository =
            destinationRepository ?? DestinationRepositoryImpl();

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

  /// Recovers missing must-visit places via targeted search.
  ///
  /// For every requested must-visit placeId that is NOT already in the
  /// candidate pool, performs a targeted Google Place Details lookup (or a
  /// free-text search when only a name is available). Returns the recovered
  /// places plus the list of must-visit IDs that could NOT be retrieved.
  ///
  /// A missing must-visit is NEVER silently discarded — it is reported so
  /// the pipeline can surface a clear generation issue.
  Future<MustVisitRecoveryResult> recoverMustVisits({
    required List<String> requestedMustVisitIds,
    required Set<String> alreadyRetrievedIds,
    List<String>? mustVisitNames,
    Coordinates? searchCenter,
  }) async {
    final recovered = <Place>[];
    final verifiedIds = <String>{};
    final unretrievable = <String>[];

    for (int i = 0; i < requestedMustVisitIds.length; i++) {
      final id = requestedMustVisitIds[i];

      // Already in the pool → verified.
      if (alreadyRetrievedIds.contains(id)) {
        verifiedIds.add(id);
        continue;
      }

      // 1. Targeted lookup by Google Place ID.
      final byId = await _placesDataSource.getPlaceDetails(id);
      if (byId != null && byId.placeId.isNotEmpty) {
        recovered.add(byId);
        verifiedIds.add(byId.placeId);
        debugPrint('[MUST-VISIT RECOVERY] Recovered by ID: '
            '${byId.placeName} ($id)');
        continue;
      }

      // 2. Fallback: free-text search using the name.
      final name = (mustVisitNames != null && i < mustVisitNames.length)
          ? mustVisitNames[i]
          : null;
      if (name != null && name.trim().isNotEmpty) {
        final byText = await _placesDataSource.searchPlacesByText(
          name,
          latitude: searchCenter?.latitude,
          longitude: searchCenter?.longitude,
        );
        final match = byText.isNotEmpty ? byText.first : null;
        if (match != null && match.placeId.isNotEmpty) {
          recovered.add(match);
          verifiedIds.add(match.placeId);
          debugPrint('[MUST-VISIT RECOVERY] Recovered by name: '
              '"$name" → ${match.placeName} (${match.placeId})');
          continue;
        }
      }

      // 3. Truly unretrievable.
      unretrievable.add(id);
      debugPrint('[MUST-VISIT RECOVERY] UNRETRIEVABLE: "$id"');
    }

    return MustVisitRecoveryResult(
      recoveredPlaces: recovered,
      verifiedIds: verifiedIds,
      unretrievableIds: unretrievable,
    );
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