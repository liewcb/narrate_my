import '../../entities/ar_object.dart';

abstract class ARRepository {
  /// [C2] Query all landmark markers within [radiusMeters] of
  /// (latitude, longitude). Returned entities have no computed
  /// distance/bearing yet — that's applied per compass tick in the
  /// service layer, not re-fetched from the DB every frame.
  Future<List<ARMarker>> getNearbyMarkers({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  });
}
