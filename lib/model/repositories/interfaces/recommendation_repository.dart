import '../../entities/recommendation.dart';

abstract class RecommendationRepository {
  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
  });
}