import '../../entities/ar_object.dart';
import '../../entities/ar_placement.dart';

abstract class ARHeritageRepository {
  /// Fetch details and story script for a heritage landmark by markerId
  Future<StoryScript> getHeritageStory(String markerId, String landmarkName);

  /// Fetch attraction metadata
  Future<ARMarker?> getHeritageMarkerById(String markerId);
}
