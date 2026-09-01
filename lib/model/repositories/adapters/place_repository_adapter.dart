import 'package:flutter/foundation.dart';

import '../../data_sources/local/places_local_data_source.dart';
import '../../data_sources/remote/place_remote_source.dart';   // ✅ Supabase source
import '../../entities/place.dart';
import '../interfaces/place_repository.dart';

class PlaceRepositoryAdapter implements PlaceRepository {
  final PlaceLocalSource _local;
  final PlaceRemoteSource _remote; // ✅ Supabase, not PlacesRemoteDataSource

  PlaceRepositoryAdapter({
    PlaceLocalSource? local,
    PlaceRemoteSource? remote, // ✅ correct type
  })  : _local = local ?? PlaceLocalSource(),
        _remote = remote ?? PlaceRemoteSource(); // ✅ default to Supabase source

  @override
  Future<void> savePlace(Place place) async {
    // 1. Save to Supabase first (source of truth). On failure, STOP — do
    // not update the local cache so it never looks like the save succeeded.
    await _remote.upsertPlace(place);

    // 2. Update SQLite cache on remote success (best-effort).
    try {
      await _local.savePlace(place);
    } catch (e) {
      debugPrint('[PlaceRepo] Local cache write failed: $e');
    }
  }

  @override
  Future<Place?> getPlace(String placeId) async {
    // 1. Remote first (source of truth)
    try {
      final remote = await _remote.getPlaceByPlaceId(placeId);
      if (remote != null) {
        // Cache locally for next time.
        try {
          await _local.savePlace(remote);
        } catch (e) {
          debugPrint('[PlaceRepo] Local cache save failed: $e');
        }
        return remote;
      }
    } catch (e) {
      debugPrint('[PlaceRepo] Remote getPlace failed: $e');
    }

    // 2. Local cache fallback (offline)
    try {
      final local = await _local.getPlace(placeId);
      if (local != null) return local;
    } catch (e) {
      debugPrint('[PlaceRepo] Local getPlace failed: $e');
    }

    return null;
  }

  @override
  Future<List<Place>> getAllPlaces() async {
    // 1. Remote first (source of truth)
    try {
      final remote = await _remote.getAllPlaces();
      if (remote.isNotEmpty) {
        // Cache the authoritative remote list.
        try {
          for (final place in remote) {
            await _local.savePlace(place);
          }
        } catch (e) {
          debugPrint('[PlaceRepo] Local cache write failed: $e');
        }
        return remote;
      }
    } catch (e) {
      debugPrint('[PlaceRepo] Remote getAllPlaces failed: $e');
    }

    // 2. Local cache fallback (offline)
    try {
      return await _local.getAllPlaces();
    } catch (e) {
      debugPrint('[PlaceRepo] Local getAllPlaces failed: $e');
      return [];
    }
  }

  @override
  Future<void> deletePlace(String placeId) async {
    // 1. Delete remotely first (source of truth)
    try {
      await _remote.deletePlace(placeId);
    } catch (e) {
      debugPrint('[PlaceRepo] Remote delete failed: $e');
      rethrow;
    }

    // 2. Delete locally on remote success (best-effort)
    try {
      await _local.deletePlace(placeId);
    } catch (e) {
      debugPrint('[PlaceRepo] Local delete failed: $e');
    }
  }

  @override
  Future<bool> exists(String placeId) async {
    return await _local.exists(placeId);
  }
}