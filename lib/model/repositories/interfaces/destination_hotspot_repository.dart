import '../../entities/destination_hotspot.dart';

/// Contract for hotspot data access.
///
/// Hotspots describe the high-density, high-footfall areas inside each
/// destination that the candidate-retrieval pipeline uses as multi-center
/// search anchors.
abstract class DestinationHotspotRepository {
  /// Get all hotspots for a destination.
  Future<List<DestinationHotspot>> getHotspotsForDestination(
    String destinationId,
  );

  /// Get hotspots for a destination, preferring those matching [tags].
  ///
  /// Returns at most [limit] hotspots; when no direct tag match exists it
  /// falls back to all hotspots in default order.
  Future<List<DestinationHotspot>> getHotspotsForDestinationByTags({
    required String destinationId,
    List<String> tags = const [],
    int limit = 4,
  });

  /// Get a single hotspot by its ID.
  Future<DestinationHotspot?> getHotspotById(String id);

  /// Force a full sync from remote, replacing the local cache.
  Future<void> refreshHotspots(String destinationId);
}
