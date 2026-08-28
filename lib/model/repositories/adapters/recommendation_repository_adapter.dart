import '../../data_sources/remote/recommendation_data_source.dart';
import '../../entities/recommendation.dart';
import '../interfaces/recommendation_repository.dart';

class RecommendationRepositoryAdapter
    implements RecommendationRepository {
  final RecommendationRemoteDataSource _remoteDataSource;

  RecommendationRepositoryAdapter(this._remoteDataSource);

  @override
  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
  }) async {
    return await _remoteDataSource.getNearbyRecommendations(
      latitude: latitude,
      longitude: longitude,
    );
  }
}