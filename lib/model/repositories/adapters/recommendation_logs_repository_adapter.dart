import '../../data_sources/remote/recommendation_logs_data_source.dart';
import '../../entities/recommendation_logs.dart';
import '../interfaces/recommendation_logs_repository.dart';

class RecommendationLogRepositoryAdapter
    implements RecommendationLogRepository {
  final RecommendationLogRemoteDataSource _remoteDataSource;

  RecommendationLogRepositoryAdapter(
      this._remoteDataSource,
      );

  @override
  Future<void> saveRecommendationLog(
      RecommendationLog log,
      ) async {
    await _remoteDataSource.saveRecommendationLog(log);
  }
}