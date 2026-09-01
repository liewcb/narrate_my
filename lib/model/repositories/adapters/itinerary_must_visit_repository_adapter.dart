import 'package:flutter/foundation.dart';

import '../../data_sources/local/itinerary_must_visit_local_data_source.dart';
import '../../data_sources/remote/itinerary_must_visit_remote_data_source.dart';
import '../../entities/itinerary_must_visit.dart';
import '../interfaces/itinerary_must_visit_repository.dart';

/// Implementation of [ItineraryMustVisitRepository] using local cache
/// and remote sync, separated into dedicated data sources.
class ItineraryMustVisitRepositoryImpl
    implements ItineraryMustVisitRepository {
  final ItineraryMustVisitLocalSource _local;
  final ItineraryMustVisitRemoteSource _remote;

  ItineraryMustVisitRepositoryImpl({
    ItineraryMustVisitLocalSource? local,
    ItineraryMustVisitRemoteSource? remote,
  })  : _local = local ?? ItineraryMustVisitLocalSource(),
        _remote = remote ?? ItineraryMustVisitRemoteSource();

  @override
  Future<List<ItineraryMustVisit>> getMustVisits(String itineraryId) async {
    // 1. Remote first (source of truth)
    try {
      final remoteItems = await _remote.fetchForItinerary(itineraryId);
      if (remoteItems.isNotEmpty) {
        // Cache on remote success (best-effort)
        try {
          await _local.insertAll(remoteItems);
        } catch (e) {
          debugPrint('[MustVisitRepo] Local cache write failed: $e');
        }
        return remoteItems;
      }
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote read failed: $e');
    }

    // 2. Local cache fallback (offline)
    debugPrint('[MustVisitRepo] Attempting local cache fallback');
    try {
      final localItems = await _local.getForItinerary(itineraryId);
      if (localItems.isNotEmpty) {
        return localItems;
      }
    } catch (e) {
      debugPrint('[MustVisitRepo] Local read failed: $e');
    }

    return [];
  }

  @override
  Future<ItineraryMustVisit> addMustVisit(ItineraryMustVisit mustVisit) async {
    // 1. Remote first (source of truth)
    try {
      final created = await _remote.insert(mustVisit);

      // 2. Cache locally on remote success (best-effort)
      try {
        await _local.insert(created);
      } catch (e) {
        debugPrint('[MustVisitRepo] Local cache write failed: $e');
      }
      return created;
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote add failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> addMustVisits(List<ItineraryMustVisit> mustVisits) async {
    for (final item in mustVisits) {
      await addMustVisit(item);
    }
  }

  @override
  Future<void> removeMustVisit(int mustVisitId) async {
    // 1. Delete remotely first (source of truth)
    try {
      await _remote.delete(mustVisitId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote delete failed: $e');
      rethrow;
    }

    // 2. Delete locally on remote success (best-effort)
    try {
      await _local.delete(mustVisitId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Local delete failed: $e');
    }
  }

  @override
  Future<void> removeMustVisitsForItinerary(String itineraryId) async {
    // 1. Clear remotely first (source of truth)
    try {
      await _remote.deleteForItinerary(itineraryId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote clear failed: $e');
      rethrow;
    }

    // 2. Clear locally on remote success (best-effort)
    try {
      await _local.clearForItinerary(itineraryId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Local clear failed: $e');
    }
  }
}