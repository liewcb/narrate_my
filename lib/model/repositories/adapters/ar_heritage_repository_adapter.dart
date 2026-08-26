import 'package:flutter/foundation.dart';
import '../../../core/config/app_config.dart';
import '../../data_sources/remote/ar_remote_data_source.dart';
import '../../entities/ar_object.dart';
import '../../entities/ar_placement.dart';
import '../interfaces/ar_heritage_repository.dart';

class SupabaseARHeritageRepositoryAdapter implements ARHeritageRepository {
  final ARRemoteDataSource _dataSource;

  SupabaseARHeritageRepositoryAdapter({ARRemoteDataSource? dataSource})
      : _dataSource = dataSource ?? ARRemoteDataSource();

  @override
  Future<StoryScript> getHeritageStory(String markerId, String landmarkName) async {
    try {
      final dto = await _dataSource.fetchAttractionByMarkerId(markerId);
      if (dto != null) {
        return dto.toStoryScript(fallbackLandmarkName: landmarkName);
      }
    } catch (e) {
      debugPrint('Supabase getHeritageStory error: $e');
    }

    // If not found in database or query failed, return an Error Message StoryScript
    return StoryScript(
      id: 'error_$markerId',
      markerId: markerId,
      landmarkName: landmarkName,
      initialGreeting: "Error: Attraction content could not be found for $landmarkName in the database.",
      narrationParagraphs: [
        "Error: Attraction content for \"$landmarkName\" (Marker ID: $markerId) could not be found in the database. Please check your network connection or ensure the landmark record exists in Supabase.",
      ],
      model3dPath: null,
      videoUrl: null,
    );
  }

  @override
  Future<ARMarker?> getHeritageMarkerById(String markerId) async {
    try {
      final dto = await _dataSource.fetchMarkerById(markerId);
      if (dto != null) {
        return dto.toEntity(
          fallbackActivationRadiusMeters: AppConfig.fallbackActivationRadiusMeters,
        );
      }
    } catch (e) {
      debugPrint('Supabase getHeritageMarkerById error: $e');
    }
    return null;
  }
}
