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
    // 1. Remote first (source of truth)
    try {
      final remoteStops = await _remote.fetchForItinerary(itineraryId);
      if (remoteStops.isNotEmpty) {
        // Cache them locally on remote success (best-effort).
        try {
          await _local.clearForItinerary(itineraryId);
          await _local.insertAll(remoteStops);
        } catch (cacheErr) {
          debugPrint('[StopRepo] Local cache write failed: $cacheErr');
        }
        return remoteStops;
      }
    } catch (e) {
      debugPrint('[StopRepo] Remote read failed: $e');
    }

    // 2. Local cache fallback (offline)
    debugPrint('[StopRepo] Attempting local cache fallback');
    try {
      final localStops = await _local.getForItinerary(itineraryId);
      if (localStops.isNotEmpty) {
        return localStops;
      }
    } catch (e) {
      debugPrint('[StopRepo] Local read failed: $e');
    }
    return [];
  }

  @override
  Future<ItineraryStop> addStop(ItineraryStop stop) async {
    // Insert remote first (source of truth)
    try {
      final created = await _remote.insert(stop);
      // Cache locally on remote success, with the server-generated ID
      await _local.insert(created);
      return created;
    } catch (e) {
      debugPrint('[StopRepo] Remote add failed: $e');
      rethrow;
    }
  }

  @override
  Future<ItineraryStop> updateStop(ItineraryStop stop) async {
    // Update remote first (source of truth)
    try {
      final updated = await _remote.update(stop);
      // Cache locally on remote success
      await _local.update(updated);
      return updated;
    } catch (e) {
      debugPrint('[StopRepo] Remote update failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteStop(int stopId) async {
    // Delete remote first (source of truth)
    try {
      await _remote.delete(stopId);
    } catch (e) {
      debugPrint('[StopRepo] Remote delete failed: $e');
      rethrow;
    }

    // Delete locally on remote success (best-effort)
    try {
      await _local.delete(stopId);
    } catch (e) {
      debugPrint('[StopRepo] Local delete failed: $e');
    }
  }

  @override
  Future<void> saveStops(List<ItineraryStop> stops) async {
    // Clear and re-insert all stops for the itinerary.
    if (stops.isEmpty) return;
    final itineraryId = stops.first.itineraryId;

    // Sync to remote first (source of truth). On failure, STOP — do not
    // touch the local cache so the caller can surface the error.
    try {
      await _remote.deleteForItinerary(itineraryId);
      for (final stop in stops) {
        await _remote.insert(stop);
      }
    } catch (e) {
      debugPrint('[StopRepo] Remote batch save failed: $e');
      rethrow;
    }

    // Remote success → write-through to the local cache (best-effort).
    try {
      await _local.clearForItinerary(itineraryId);
      for (final stop in stops) {
        await _local.insert(stop);
      }
    } catch (e) {
      debugPrint('[StopRepo] Local cache write failed: $e');
    }
  }

  @override
  Future<void> replaceDayStops({
    required String itineraryId,
    required int dayIndex,
    required List<ItineraryStop> newStops,
  }) async {
    // Remote: delete the day's stops, then batch-insert the new ones.
    // Remote-first (source of truth). On failure, STOP — do not touch the
    // local cache so the caller can surface the error.
    try {
      await _remote.deleteForDay(itineraryId, dayIndex);
      for (final stop in newStops) {
        await _remote.insert(stop);
      }
    } catch (e) {
      debugPrint('[StopRepo] Remote day replace failed: $e');
      rethrow;
    }

    // Remote success → write-through to the local cache (best-effort).
    try {
      await _local.deleteForDay(itineraryId, dayIndex);
      await _local.insertAll(newStops);
    } catch (e) {
      debugPrint('[StopRepo] Local day insert failed: $e');
    }
  }
}