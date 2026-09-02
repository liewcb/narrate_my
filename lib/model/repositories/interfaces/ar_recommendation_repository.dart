import '../../entities/ar_recommendation.dart';

abstract class ARRecommendationRepository {
  Future<List<ARRecommendation>> recommend({
    required String currentMarkerId,
    required String currentAttractionName,
    required double latitude,
    required double longitude,
    required List<String> excludedMarkerIds,
  });
}
