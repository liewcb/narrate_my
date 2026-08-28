import 'dart:math' as math;

import '../../data_sources/remote/recommendation_data_source.dart';
import '../../data_sources/remote/recommendation_places_remote_data_source.dart';
import '../../DTO/recommendation_place_dto.dart';
import '../../dto/recommendation_dto.dart';
import '../../entities/coordinates.dart';
import '../../entities/recommendation.dart';
import '../interfaces/recommendation_repository.dart';

class RecommendationRepositoryAdapter implements RecommendationRepository {
  final RecommendationRemoteDataSource _remoteDataSource;
  final RecommendationPlacesRemoteDataSource _placesDataSource;

  RecommendationRepositoryAdapter(
    this._remoteDataSource, {
    RecommendationPlacesRemoteDataSource? placesDataSource,
  }) : _placesDataSource =
           placesDataSource ?? RecommendationPlacesRemoteDataSource();

  @override
  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
  }) async {
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
    return recommendations;
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
