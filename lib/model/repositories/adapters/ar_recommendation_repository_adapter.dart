import '../../data_sources/remote/ar_recommendation_remote_data_source.dart';
import '../../entities/ar_recommendation.dart';
import '../interfaces/ar_recommendation_repository.dart';

class ARRecommendationRepositoryAdapter implements ARRecommendationRepository {
  final ARRecommendationRemoteDataSource _remoteDataSource;

  ARRecommendationRepositoryAdapter(this._remoteDataSource);

  @override
  Future<List<ARRecommendation>> recommend({
    required String currentMarkerId,
    required String currentAttractionName,
    required double latitude,
    required double longitude,
    required List<String> excludedMarkerIds,
  }) async {
    final dtos = await _remoteDataSource.recommend(
      currentMarkerId: currentMarkerId,
      currentAttractionName: currentAttractionName,
      latitude: latitude,
      longitude: longitude,
      excludedMarkerIds: excludedMarkerIds,
    );
    final unique = <String, ARRecommendation>{};
    for (final dto in dtos) {
      unique[dto.attractionId] = dto.toEntity();
    }
    final recommendations = unique.values.toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return recommendations;
  }
}
