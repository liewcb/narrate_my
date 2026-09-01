import 'dart:math' as math;

import '../../data_sources/local/recommendation_cache_local_data_source.dart';
import '../../data_sources/remote/recommendation_data_source.dart';
import '../../data_sources/remote/recommendation_places_remote_data_source.dart';
import '../../data_sources/remote/recommendation_preference_context_data_source.dart';
import '../../DTO/recommendation_place_dto.dart';
import '../../dto/recommendation_dto.dart';
import '../../entities/coordinates.dart';
import '../../entities/recommendation.dart';
import '../interfaces/recommendation_repository.dart';

class RecommendationRepositoryAdapter implements RecommendationRepository {
  final RecommendationRemoteDataSource _remoteDataSource;
  final RecommendationPlacesRemoteDataSource _placesDataSource;
  final RecommendationCacheLocalDataSource _cacheDataSource;
  final RecommendationPreferenceContextDataSource _preferenceContextDataSource;

  RecommendationRepositoryAdapter(
    this._remoteDataSource, {
    RecommendationPlacesRemoteDataSource? placesDataSource,
    RecommendationCacheLocalDataSource? cacheDataSource,
    RecommendationPreferenceContextDataSource? preferenceContextDataSource,
  }) : _placesDataSource =
           placesDataSource ?? RecommendationPlacesRemoteDataSource(),
       _cacheDataSource =
           cacheDataSource ?? RecommendationCacheLocalDataSource(),
       _preferenceContextDataSource =
           preferenceContextDataSource ??
           RecommendationPreferenceContextDataSource();

  @override
  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    String? cacheIdentity;
    try {
      cacheIdentity = await _preferenceContextDataSource.getCacheIdentity();
    } catch (_) {
      // Caching is an optimisation. A local/context lookup failure must not
      // prevent the live recommendation request.
    }
    final cacheKey = cacheIdentity == null
        ? null
        : _buildCacheKey(
            cacheIdentity: cacheIdentity,
            latitude: latitude,
            longitude: longitude,
          );
    RecommendationCacheEntry? cached;
    if (cacheKey != null) {
      try {
        cached = await _cacheDataSource.read(cacheKey);
      } catch (_) {
        // Continue without a phone cache; Supabase still has the shared cache.
      }
    }

    if (!forceRefresh && cached?.isFresh == true) {
      return cached!.recommendations;
    }

    try {
      final dtos = await _remoteDataSource.getNearbyRecommendations(
        latitude: latitude,
        longitude: longitude,
      );

      final origin = Coordinates(latitude: latitude, longitude: longitude);
      final resolved = await Future.wait(
        dtos.map((dto) => _resolveRecommendation(dto, origin)),
      );

      final unique = <String, Recommendation>{};
      for (final recommendation in resolved.whereType<Recommendation>()) {
        unique[recommendation.placeId] = recommendation;
      }

      final recommendations = unique.values.toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));

      if (dtos.isNotEmpty && recommendations.isEmpty) {
        throw const RecommendationResolutionException(
          'Recommendations were found, but their map locations could not be '
          'verified. Check Places API access and try again.',
        );
      }

      if (recommendations.isEmpty && cached != null) {
        return cached.recommendations;
      }

      if (cacheKey != null && recommendations.isNotEmpty) {
        try {
          await _cacheDataSource.write(
            cacheKey: cacheKey,
            recommendations: recommendations,
          );
        } catch (_) {
          // A cache write failure must not discard valid live results.
        }
      }
      return recommendations;
    } on RecommendationResolutionException {
      if (cached != null) return cached.recommendations;
      rethrow;
    } on RecommendationRemoteException catch (error) {
      if (cached != null) return cached.recommendations;
      throw RecommendationUnavailableException(
        error.isQuotaLimited
            ? 'AI recommendation quota has been reached. Please try again '
                  'later.'
            : error.message,
      );
    } catch (_) {
      if (cached != null) return cached.recommendations;
      rethrow;
    }
  }

  String _buildCacheKey({
    required String cacheIdentity,
    required double latitude,
    required double longitude,
  }) {
    // The phone cache is intentionally more precise than the shared server
    // bucket so distances do not remain stale after the tourist moves.
    final latitudeBucket = latitude.toStringAsFixed(3);
    final longitudeBucket = longitude.toStringAsFixed(3);
    return 'nearby:v2:$cacheIdentity:$latitudeBucket:$longitudeBucket';
  }

  Future<Recommendation?> _resolveRecommendation(
    RecommendationDto dto,
    Coordinates origin,
  ) async {
    RecommendationPlaceDto? place;
    try {
      final query = [
        dto.name,
        if (dto.address != null) dto.address!,
      ].join(', ');
      final places = await _placesDataSource.searchText(
        query: query,
        latitude: origin.latitude,
        longitude: origin.longitude,
        radiusMeters: 50000,
      );
      place = _bestPlaceMatch(dto.name, places);
    } catch (_) {
      // Coordinates supplied by the Edge Function remain usable even when
      // Google Places enrichment is temporarily unavailable.
    }

    final resolvedLatitude = dto.latitude ?? place?.latitude;
    final resolvedLongitude = dto.longitude ?? place?.longitude;
    if (resolvedLatitude == null || resolvedLongitude == null) return null;

    final destination = Coordinates(
      latitude: resolvedLatitude,
      longitude: resolvedLongitude,
    );
    final distanceKm = origin.distanceTo(destination);

    return dto.toEntity(
      resolvedPlaceId:
          dto.placeId ?? place?.placeId ?? '${dto.rank}-${dto.name}',
      resolvedLatitude: resolvedLatitude,
      resolvedLongitude: resolvedLongitude,
      resolvedAddress: dto.address ?? place?.address ?? 'Address unavailable',
      resolvedImageUrl:
          dto.imageUrl ??
          _placesDataSource.buildPhotoUrl(dto.photoReference) ??
          _placesDataSource.buildPhotoUrl(place?.photoResourceName),
      resolvedRating: dto.rating ?? place?.rating,
      distanceKm: distanceKm,
      estimatedTravelMinutes: math.max(1, (distanceKm / 35 * 60).round()),
    );
  }

  RecommendationPlaceDto? _bestPlaceMatch(
    String recommendationName,
    List<RecommendationPlaceDto> places,
  ) {
    if (places.isEmpty) return null;
    final target = _normaliseName(recommendationName);
    for (final place in places) {
      final candidate = _normaliseName(place.name);
      if (candidate == target ||
          candidate.contains(target) ||
          target.contains(candidate)) {
        return place;
      }
    }
    return places.first;
  }

  String _normaliseName(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
}
