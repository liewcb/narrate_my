import '../../../entities/ar_site.dart';
import '../../../entities/place.dart';

/// Resolves an AR site to the verified Google Place used by Nearby details.
abstract class ARSitePlaceRepository {
  Future<Place?> resolvePlace(ARSite site);
}
