import '../../../data_sources/remote/ar_site_place_remote_data_source.dart';
import '../../../entities/ar_site.dart';
import '../../../entities/place.dart';
import '../../interfaces/ar_exploration/ar_site_place_repository.dart';

class SupabaseARSitePlaceRepositoryAdapter implements ARSitePlaceRepository {
  final ARSitePlaceRemoteDataSource _dataSource;

  SupabaseARSitePlaceRepositoryAdapter({
    ARSitePlaceRemoteDataSource? dataSource,
  }) : _dataSource = dataSource ?? ARSitePlaceRemoteDataSource();

  @override
  Future<Place?> resolvePlace(ARSite site) => _dataSource.resolvePlace(site);
}
