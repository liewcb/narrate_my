import '../../../core/config/app_config.dart';
import '../../data_sources/remote/ar_remote_data_source.dart';
import '../../entities/ar_object.dart';
import '../interfaces/ar_repository.dart';

class SupabaseARRepositoryAdapter implements ARRepository {
  final ARRemoteDataSource _dataSource;

  SupabaseARRepositoryAdapter({ARRemoteDataSource? dataSource})
      : _dataSource = dataSource ?? ARRemoteDataSource();

  @override
  Future<List<ARMarker>> getNearbyMarkers({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    final dtos = await _dataSource.fetchNearbyMarkers(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );

    return dtos
        .map((dto) => dto.toEntity(
              fallbackActivationRadiusMeters: AppConfig.fallbackActivationRadiusMeters,
            ))
        .toList();
  }
}
