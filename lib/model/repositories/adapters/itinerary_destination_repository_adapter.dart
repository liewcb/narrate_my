
import '../../data_sources/local/itinerary_destination_local_data_source.dart';
import '../../data_sources/remote/itinerary_destination_remote_data_source.dart';
import '../../entities/itinerary_destination.dart';
import '../interfaces/itinerary_destination_repository.dart';

class ItineraryDestinationRepositoryImpl implements ItineraryDestinationRepository {
  final ItineraryDestinationLocalSource _local;
  final ItineraryDestinationRemoteSource _remote;

  ItineraryDestinationRepositoryImpl({
    ItineraryDestinationLocalSource? local,
    ItineraryDestinationRemoteSource? remote,
  })  : _local = local ?? ItineraryDestinationLocalSource(),
        _remote = remote ?? ItineraryDestinationRemoteSource();

  // ─── Public API ──────────────────────────────────────────────

  @override
  Future<List<ItineraryDestination>> getSelectedDestinations(String itineraryId) async {
    // Local first
    final local = await _local.getForItinerary(itineraryId);
    if (local.isNotEmpty) return local;

    // Remote fallback
    final remote = await _remote.fetchForItinerary(itineraryId);
    if (remote.isNotEmpty) {
      await _local.insertAll(remote);
    }
    return remote;
  }

  @override
  Future<void> addDestination(ItineraryDestination destination) async {
    // Remote first
    await _remote.insert(destination);
    // Local cache
    await _local.insert(destination);
  }

  @override
  Future<void> updateDestination(ItineraryDestination destination) async {
    await _remote.update(destination);
    await _local.update(destination);
  }

  @override
  Future<void> removeDestination(String itineraryId, String destinationId) async {
    await _remote.delete(itineraryId, destinationId);
    await _local.delete(itineraryId, destinationId);
  }
}