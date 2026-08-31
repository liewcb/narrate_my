import '../../data_sources/remote/ar_site_remote_data_source.dart';
import '../../entities/ar_site.dart';
import '../interfaces/ar_site_repository.dart';

class SupabaseARSiteRepositoryAdapter implements ARSiteRepository {
  final ARSiteRemoteDataSource _dataSource;

  SupabaseARSiteRepositoryAdapter({ARSiteRemoteDataSource? dataSource})
    : _dataSource = dataSource ?? ARSiteRemoteDataSource();

  @override
  Future<List<ARSite>> getNearbySites({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) {
    return _dataSource.fetchNearbySites(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }
}
