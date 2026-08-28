import 'package:flutter/foundation.dart';
import '../../data_sources/local/itinerary_stop_local_data_source.dart';
import '../../data_sources/remote/itinerary_stop_remote_data_source.dart';
import '../../entities/itinerary_stop.dart';
import '../interfaces/itinerary_stop_repository.dart';

class ItineraryStopRepositoryImpl implements ItineraryStopRepository {
  final ItineraryStopLocalSource _local;
  final ItineraryStopRemoteSource _remote;

  ItineraryStopRepositoryImpl({
    ItineraryStopLocalSource? local,
    ItineraryStopRemoteSource? remote,
  })  : _local = local ?? ItineraryStopLocalSource(),
        _remote = remote ?? ItineraryStopRemoteSource();

  @override
  Future<List<ItineraryStop>> getStopsForItinerary(String itineraryId) async {
    // Local-first
    try {
      final localStops = await _local.getForItinerary(itineraryId);
      if (localStops.isNotEmpty) {
        return localStops;
      }
    } catch (e) {
      debugPrint('[StopRepo] Local read failed: $e');
    }

    // Remote fallback
    try {
      final remoteStops = await _remote.fetchForItinerary(itineraryId);
      if (remoteStops.isNotEmpty) {
        // Cache them locally
        try {
          await _local.clearForItinerary(itineraryId);
          await _local.insertAll(remoteStops);
        } catch (cacheErr) {
          debugPrint('[StopRepo] Local cache write failed: $cacheErr');
        }
      }
      return remoteStops;
    } catch (e) {
      debugPrint('[StopRepo] Remote read failed: $e');
      return [];
    }
  }

  @override
  Future<ItineraryStop> addStop(ItineraryStop stop) async {
    // Insert locally first
    final localId = await _local.insert(stop);
    final localStop = stop.copyWith(stopId: localId);

    // Sync to remote
    try {
      final created = await _remote.insert(stop);
      // Update local with server-generated ID
      await _local.update(created);
      return created;
    } catch (e) {
      debugPrint('[StopRepo] Remote add failed: $e');
      return localStop;
    }
  }

  @override
  Future<ItineraryStop> updateStop(ItineraryStop stop) async {
    // Update locally
    await _local.update(stop);

    // Sync to remote
    try {
      final updated = await _remote.update(stop);
      // Ensure local matches remote
      await _local.update(updated);
      return updated;
    } catch (e) {
      debugPrint('[StopRepo] Remote update failed: $e');
      return stop;
    }
  }

  @override
  Future<void> deleteStop(int stopId) async {
    // Delete locally
    try {
      await _local.delete(stopId);
    } catch (e) {
      debugPrint('[StopRepo] Local delete failed: $e');
    }

    // Delete remotely
    try {
      await _remote.delete(stopId);
    } catch (e) {
      debugPrint('[StopRepo] Remote delete failed: $e');
    }
  }

  @override
  Future<void> saveStops(List<ItineraryStop> stops) async {
    // Clear and re-insert all stops for the itinerary.
    if (stops.isEmpty) return;
    final itineraryId = stops.first.itineraryId;

    // Clear local
    await _local.clearForItinerary(itineraryId);

    // Insert all locally
    for (final stop in stops) {
      await _local.insert(stop);
    }

    // Sync to remote (best-effort)
    try {
      await _remote.deleteForItinerary(itineraryId);
      for (final stop in stops) {
        await _remote.insert(stop);
      }
    } catch (e) {
      debugPrint('[StopRepo] Remote batch save failed: $e');
    }
  }
}