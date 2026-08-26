import '../../entities/destination.dart';

/// Contract for destination data access.
abstract class DestinationRepository {
  /// Get all destinations – returns cached or fetches from remote.
  Future<List<Destination>> getAllDestinations();

  /// Get a single destination by its ID.
  Future<Destination?> getDestinationById(String id);

  /// Search destinations by name (local only).
  Future<List<Destination>> searchDestinations(String query);

  /// Batch fetch by list of IDs.
  Future<List<Destination>> getDestinationsByIds(List<String> ids);

  /// Get a limited list of popular destinations (e.g., for home screen).
  Future<List<Destination>> getPopularDestinations({int limit});

  /// Check if a destination exists.
  Future<bool> exists(String id);

  /// Total count of destinations.
  Future<int> count();

  /// Force a full sync from remote, replacing the local cache.
  Future<void> refreshDestinations();
}