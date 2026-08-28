import '../../entities/recommendation.dart';

abstract class RecommendationRepository {
  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
  });
}

class RecommendationResolutionException implements Exception {
  final String message;

  const RecommendationResolutionException(this.message);

  @override
  String toString() => message;
}
