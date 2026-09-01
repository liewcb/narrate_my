import '../../entities/ar_site.dart';

abstract class ARSiteRepository {
  Future<List<ARSite>> getNearbySites({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  });
}
