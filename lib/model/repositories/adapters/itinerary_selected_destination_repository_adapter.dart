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
    // 1. Remote first (source of truth)
    try {
      final remoteList = await _remote.fetchForItinerary(itineraryId);
      if (remoteList.isNotEmpty) {
        // Cache on remote success (best-effort)
        try {
          await _local.cacheAll(remoteList);
        } catch (e) {
          debugPrint('[SelectedDestRepo] Local cache write failed: $e');
        }
        return remoteList;
      }
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote fetch failed: $e');
    }

    // 2. Local cache fallback (offline)
    debugPrint('[SelectedDestRepo] Attempting local cache fallback');
    try {
      final localList = await _local.getForItinerary(itineraryId);
      if (localList.isNotEmpty) {
        return localList;
      }
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local read failed: $e');
    }
    return [];
  }

  @override
  Future<void> addSelectedDestination(ItinerarySelectedDestinationDTO destination) async {
    // 1. Insert remotely first (source of truth)
    try {
      await _remote.insert(destination);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote insert failed: $e');
      rethrow;
    }
    // 2. Insert locally on remote success (best-effort)
    try {
      await _local.insert(destination);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local insert failed: $e');
    }
  }

  @override
  Future<void> updateAllocatedDays(
      String itineraryId,
      String destinationId,
      int allocatedDays,
      ) async {
    // 1. Update remotely first (source of truth)
    try {
      await _remote.updateAllocatedDays(itineraryId, destinationId, allocatedDays);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote update failed: $e');
      rethrow;
    }
    // 2. Update locally on remote success (best-effort)
    try {
      await _local.updateAllocatedDays(itineraryId, destinationId, allocatedDays);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local update failed: $e');
    }
  }

  @override
  Future<void> removeSelectedDestination(
      String itineraryId,
      String destinationId,
      ) async {
    // 1. Delete remotely first (source of truth)
    try {
      await _remote.delete(itineraryId, destinationId);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Remote delete failed: $e');
      rethrow;
    }
    // 2. Delete locally on remote success (best-effort)
    try {
      await _local.delete(itineraryId, destinationId);
    } catch (e) {
      debugPrint('[SelectedDestRepo] Local delete failed: $e');
    }
  }
}