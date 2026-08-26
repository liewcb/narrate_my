import '../../entities/ar_placement.dart';
import '../../repositories/interfaces/ar_heritage_repository.dart';
import '../../repositories/adapters/ar_heritage_repository_adapter.dart';

/// Business logic service matching `GetAttractionContentService` in architecture diagram
class GetAttractionContentService {
  final ARHeritageRepository _repository;

  GetAttractionContentService({ARHeritageRepository? repository})
      : _repository = repository ?? SupabaseARHeritageRepositoryAdapter();

  Future<StoryScript> fetchContent({
    required String markerId,
    required String landmarkName,
  }) async {
    return _repository.getHeritageStory(markerId, landmarkName);
  }
}
