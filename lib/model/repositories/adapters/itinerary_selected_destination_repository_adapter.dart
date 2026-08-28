import 'package:flutter/foundation.dart';
import '../../data_sources/local/itinerary_selected_destination_local_data_source.dart';
import '../../data_sources/remote/itinerary_selected_destination_remote_data_source.dart';
import '../../dto/itinerary_selected_destination_dto.dart';
import '../interfaces/itinerary_selected_destination_repository.dart';

class ItinerarySelectedDestinationRepositoryImpl
    implements ItinerarySelectedDestinationRepository {
  final ItinerarySelectedDestinationLocalSource _local;
  final ItinerarySelectedDestinationRemoteSource _remote;

  ItinerarySelectedDestinationRepositoryImpl({
    ItinerarySelectedDestinationLocalSource? local,
    ItinerarySelectedDestinationRemoteSource? remote,
  })  : _local = local ?? ItinerarySelectedDestinationLocalSource(),
        _remote = remote ?? ItinerarySelectedDestinationRemoteSource();

  @override
  Future<List<ItinerarySelectedDestinationDTO>> getSelectedDestinations(
      String itineraryId,
      ) async {
    // Local-first
    try {
      final localList = await _local.getForItinerary(itineraryId);
      if (localList.isNotEmpty) {
        return localList;
      }
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local read failed: $e');
    }

    // Remote fallback
    try {
      final remoteList = await _remote.fetchForItinerary(itineraryId);
      if (remoteList.isNotEmpty) {
        await _local.cacheAll(remoteList);
      }
      return remoteList;
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote fetch failed: $e');
      return [];
    }
  }

  @override
  Future<void> addSelectedDestination(ItinerarySelectedDestinationDTO destination) async {
    // Insert locally
    try {
      await _local.insert(destination);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local insert failed: $e');
    }
    // Insert remotely
    try {
      await _remote.insert(destination);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote insert failed: $e');
    }
  }

  @override
  Future<void> updateAllocatedDays(
      String itineraryId,
      String destinationId,
      int allocatedDays,
      ) async {
    // Update locally
    try {
      await _local.updateAllocatedDays(itineraryId, destinationId, allocatedDays);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local update failed: $e');
    }
    // Update remotely
    try {
      await _remote.updateAllocatedDays(itineraryId, destinationId, allocatedDays);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote update failed: $e');
    }
  }

  @override
  Future<void> removeSelectedDestination(
      String itineraryId,
      String destinationId,
      ) async {
    // Delete locally
    try {
      await _local.delete(itineraryId, destinationId);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local delete failed: $e');
    }
    // Delete remotely
    try {
      await _remote.delete(itineraryId, destinationId);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote delete failed: $e');
    }
  }
}