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
    // 1. Save locally first (SQLite)
    await _local.savePlace(place);

    // 2. Sync to Supabase (best-effort)
    try {
      await _remote.upsertPlace(place);
    } catch (e) {
      debugPrint('[PlaceRepo] Remote upsert failed: $e');
    }
  }

  @override
  Future<Place?> getPlace(String placeId) async {
    return await _local.getPlace(placeId);
  }

  @override
  Future<List<Place>> getAllPlaces() async {
    return await _local.getAllPlaces();
  }

  @override
  Future<void> deletePlace(String placeId) async {
    await _local.deletePlace(placeId);
  }

  @override
  Future<bool> exists(String placeId) async {
    return await _local.exists(placeId);
  }
}