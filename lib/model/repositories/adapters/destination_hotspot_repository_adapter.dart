import 'package:flutter/foundation.dart';

import '../../data_sources/local/destination_hotspot_local_data_source.dart';
import '../../data_sources/remote/destination_hotspot_remote_source.dart';
import '../../dto/destination_hotspot_dto.dart';
import '../../entities/destination_hotspot.dart';
import '../interfaces/destination_hotspot_repository.dart';

class DestinationHotspotRepositoryImpl
    implements DestinationHotspotRepository {
  final DestinationHotspotLocalSource _local;
  final DestinationHotspotRemoteSource _remote;

  DestinationHotspotRepositoryImpl({
    DestinationHotspotLocalSource? local,
    DestinationHotspotRemoteSource? remote,
  })  : _local = local ?? DestinationHotspotLocalSource(),
        _remote = remote ?? DestinationHotspotRemoteSource();

  // ─── Public API ──────────────────────────────────────────────

  @override
  Future<List<DestinationHotspot>> getHotspotsForDestination(
      String destinationId,
      ) async {
    // Local-first
    try {
      final localDtos = await _local.getForDestination(destinationId);
      if (localDtos.isNotEmpty) {
        return localDtos.map((dto) => dto.toDomain()).toList();
      }
    } catch (e) {
      debugPrint('[HotspotRepo] Local read failed: $e');
    }

    // Remote fallback
    try {
      final remoteDtos = await _remote.fetchForDestination(destinationId);
      if (remoteDtos.isNotEmpty) {
        await _local.insertDtos(remoteDtos);
      }
      return remoteDtos.map((dto) => dto.toDomain()).toList();
    } catch (e) {
      debugPrint('[HotspotRepo] Remote fetch failed: $e');
      return [];
    }
  }

  @override
  Future<List<DestinationHotspot>> getHotspotsForDestinationByTags({
    required String destinationId,
    List<String> tags = const [],
    int limit = 4,
  }) async {
    final hotspots = await getHotspotsForDestination(destinationId);
    if (hotspots.isEmpty) return hotspots;

    final normalized = tags.map((t) => t.trim().toLowerCase()).toList();
    final matched = hotspots
        .where((h) => h.matchesAnyTag(normalized))
        .toList();

    final selection = matched.isNotEmpty ? matched : hotspots;
    return selection.take(limit).toList();
  }

  @override
  Future<DestinationHotspot?> getHotspotById(String id) async {
    final dto = await _local.getById(id);
    return dto?.toDomain();
  }

  @override
  Future<void> refreshHotspots(String destinationId) async {
    try {
      final remoteDtos = await _remote.fetchForDestination(destinationId);
      if (remoteDtos.isEmpty) return;

      await _local.deleteForDestination(destinationId);
      await _local.insertDtos(remoteDtos);
    } catch (e) {
      debugPrint('[HotspotRepo] Refresh failed: $e');
    }
  }
}