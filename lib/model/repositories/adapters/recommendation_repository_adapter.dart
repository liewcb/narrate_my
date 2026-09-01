import 'dart:math' as math;

import '../../data_sources/local/recommendation_cache_local_data_source.dart';
import '../../data_sources/remote/recommendation_data_source.dart';
import '../../data_sources/remote/recommendation_preference_context_data_source.dart';
import '../../dto/recommendation_dto.dart';
import '../../entities/coordinates.dart';
import '../../entities/recommendation.dart';
import '../interfaces/recommendation_repository.dart';

class RecommendationRepositoryAdapter implements RecommendationRepository {
  final RecommendationRemoteDataSource _remoteDataSource;
  final RecommendationCacheLocalDataSource _cacheDataSource;
  final RecommendationPreferenceContextDataSource _preferenceContextDataSource;

  RecommendationRepositoryAdapter(
    this._remoteDataSource, {
    RecommendationCacheLocalDataSource? cacheDataSource,
    RecommendationPreferenceContextDataSource? preferenceContextDataSource,
  }) : _cacheDataSource =
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
          'verified. Please try again.',
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
    return 'nearby:v3:$cacheIdentity:$latitudeBucket:$longitudeBucket';
  }

  Future<Recommendation?> _resolveRecommendation(
    RecommendationDto dto,
    Coordinates origin,
  ) async {
    // Google Places enrichment is performed by the Edge Function. The mobile
    // app never receives or needs the Places web-service API key.
    final resolvedLatitude = dto.latitude;
    final resolvedLongitude = dto.longitude;
    if (resolvedLatitude == null || resolvedLongitude == null) return null;

    final destination = Coordinates(
      latitude: resolvedLatitude,
      longitude: resolvedLongitude,
    );
    final distanceKm = origin.distanceTo(destination);

    return dto.toEntity(
      resolvedPlaceId: dto.placeId ?? '${dto.rank}-${dto.name}',
      resolvedLatitude: resolvedLatitude,
      resolvedLongitude: resolvedLongitude,
      resolvedAddress: dto.address ?? 'Address unavailable',
      resolvedImageUrl: dto.imageUrl,
      resolvedRating: dto.rating,
      distanceKm: distanceKm,
      estimatedTravelMinutes: math.max(1, (distanceKm / 35 * 60).round()),
    );
  }
}
