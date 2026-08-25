import '../../entities/recommendation_logs.dart';

abstract class RecommendationLogRepository {
  Future<void> saveRecommendationLog(
      RecommendationLog log,
      );
}