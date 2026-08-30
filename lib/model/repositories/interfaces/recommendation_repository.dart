import '../../entities/recommendation.dart';

abstract class RecommendationRepository {
  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  });
}

class RecommendationResolutionException implements Exception {
  final String message;

  const RecommendationResolutionException(this.message);

  @override
  String toString() => message;
}

class RecommendationUnavailableException implements Exception {
  final String message;

  const RecommendationUnavailableException(this.message);

  @override
  String toString() => message;
}
