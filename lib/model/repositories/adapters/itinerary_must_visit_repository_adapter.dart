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
    // Local-first
    try {
      final localItems = await _local.getForItinerary(itineraryId);
      if (localItems.isNotEmpty) {
        return localItems;
      }
    } catch (e) {
      debugPrint('[MustVisitRepo] Local read failed: $e');
    }

    // Remote fallback
    try {
      final remoteItems = await _remote.fetchForItinerary(itineraryId);
      if (remoteItems.isNotEmpty) {
        await _local.insertAll(remoteItems);
      }
      return remoteItems;
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote read failed: $e');
      return [];
    }
  }

  @override
  Future<ItineraryMustVisit> addMustVisit(ItineraryMustVisit mustVisit) async {
    // Insert locally first
    await _local.insert(mustVisit);

    // Sync to remote (best-effort)
    try {
      final created = await _remote.insert(mustVisit);
      // Update local with server‑generated ID
      await _local.insert(created);
      return created;
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote add failed: $e');
      // Return the locally‑inserted item (with temporary ID)
      return mustVisit;
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
    // Delete locally
    try {
      await _local.delete(mustVisitId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Local delete failed: $e');
    }

    // Delete remotely
    try {
      await _remote.delete(mustVisitId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote delete failed: $e');
    }
  }

  @override
  Future<void> removeMustVisitsForItinerary(String itineraryId) async {
    // Clear locally
    try {
      await _local.clearForItinerary(itineraryId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Local clear failed: $e');
    }

    // Clear remotely
    try {
      await _remote.deleteForItinerary(itineraryId);
    } catch (e) {
      debugPrint('[MustVisitRepo] Remote clear failed: $e');
    }
  }
}