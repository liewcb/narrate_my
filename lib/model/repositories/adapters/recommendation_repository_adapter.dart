import 'dart:math' as math;

import '../../../core/services/google_maps_service.dart';
import '../../data_sources/remote/recommendation_data_source.dart';
import '../../dto/recommendation_dto.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import '../../entities/recommendation.dart';
import '../interfaces/recommendation_repository.dart';

class RecommendationRepositoryAdapter implements RecommendationRepository {
  final RecommendationRemoteDataSource _remoteDataSource;
  final GoogleMapsService _mapsService;

  RecommendationRepositoryAdapter(
    this._remoteDataSource, {
    GoogleMapsService? mapsService,
  }) : _mapsService = mapsService ?? GoogleMapsService();

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
    Place? place;
    try {
      final query = [
        dto.name,
        if (dto.address != null) dto.address!,
      ].join(', ');
      final places = await _mapsService.searchTextPlaces(
        query: query,
        latitude: origin.latitude,
        longitude: origin.longitude,
        radius: 50000,
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
    final photoReference = dto.photoReference ?? place?.photoReference;

    return dto.toEntity(
      resolvedPlaceId:
          dto.placeId ?? place?.placeId ?? '${dto.rank}-${dto.name}',
      resolvedLatitude: resolvedLatitude,
      resolvedLongitude: resolvedLongitude,
      resolvedAddress: dto.address ?? place?.address ?? 'Address unavailable',
      resolvedImageUrl:
          dto.imageUrl ?? _mapsService.getPlacePhotoUrl(photoReference),
      resolvedRating: dto.rating ?? place?.rating,
      distanceKm: distanceKm,
      estimatedTravelMinutes: math.max(1, (distanceKm / 35 * 60).round()),
    );
  }

  Place? _bestPlaceMatch(String recommendationName, List<Place> places) {
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
