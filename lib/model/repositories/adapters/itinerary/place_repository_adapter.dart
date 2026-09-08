import 'package:flutter/foundation.dart';

import '../../../data_sources/local/places_local_data_source.dart';
import '../../../data_sources/remote/place_remote_source.dart';
import '../../../entities/place.dart';
import '../../interfaces/itinerary/place_repository.dart';

class PlaceRepositoryAdapter implements PlaceRepository {
  final PlaceLocalSource _local;
  final PlaceRemoteSource _remote;

  PlaceRepositoryAdapter({
    PlaceLocalSource? local,
    PlaceRemoteSource? remote,
  })  : _local = local ?? PlaceLocalSource(),
        _remote = remote ?? PlaceRemoteSource();

  @override
  Future<void> savePlace(Place place) async {
    // 1. Save to Supabase first (source of truth).
    await _remote.upsertPlace(place);

    // 2. Update local cache after remote success.
    try {
      await _local.savePlace(place);
    } catch (e) {
      debugPrint('[PlaceRepo] Local cache write failed: $e');
    }
  }

  @override
  Future<Place?> getPlace(String placeId) async {
    // 1. Remote first.
    try {
      final remote = await _remote.getPlaceByPlaceId(placeId);

      if (remote != null) {
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

    // 2. Local cache fallback.
    try {
      final local = await _local.getPlace(placeId);

      if (local != null) {
        return local;
      }
    } catch (e) {
      debugPrint('[PlaceRepo] Local getPlace failed: $e');
    }

    return null;
  }

  @override
  Future<List<Place>> getAllPlaces() async {
    // 1. Remote first.
    try {
      final remote = await _remote.getAllPlaces();

      if (remote.isNotEmpty) {
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

    // 2. Local cache fallback.
    try {
      return await _local.getAllPlaces();
    } catch (e) {
      debugPrint('[PlaceRepo] Local getAllPlaces failed: $e');
      return [];
    }
  }

  @override
  Future<void> deletePlace(String placeId) async {
    // 1. Delete remotely first.
    try {
      await _remote.deletePlace(placeId);
    } catch (e) {
      debugPrint('[PlaceRepo] Remote delete failed: $e');
      rethrow;
    }

    // 2. Delete locally after remote success.
    try {
      await _local.deletePlace(placeId);
    } catch (e) {
      debugPrint('[PlaceRepo] Local delete failed: $e');
    }
  }

  @override
  Future<bool> exists(String placeId) async {
    // 1. Check remote first.
    try {
      final remote = await _remote.getPlaceByPlaceId(placeId);

      if (remote != null) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[PlaceRepo] Remote exists check failed: $e');
    }

    // 2. Local cache fallback.
    try {
      return await _local.exists(placeId);
    } catch (e) {
      debugPrint('[PlaceRepo] Local exists check failed: $e');
      return false;
    }
  }

  @override
  Future<List<Place>> searchPlaces(String query) async {
    final searchQuery = query.trim().toLowerCase();

    // Empty query → return all places.
    if (searchQuery.isEmpty) {
      return await getAllPlaces();
    }

    try {
      // Get the latest places from the repository.
      final places = await getAllPlaces();

      // Search by place name.
      return places.where((place) {
        final placeName = place.name.toLowerCase();

        return placeName.contains(searchQuery);
      }).toList();
    } catch (e) {
      debugPrint('[PlaceRepo] Search places failed: $e');

      // Local fallback.
      try {
        final localPlaces = await _local.getAllPlaces();

        return localPlaces.where((place) {
          final placeName = place.name.toLowerCase();

          return placeName.contains(searchQuery);
        }).toList();
      } catch (localError) {
        debugPrint(
          '[PlaceRepo] Local search fallback failed: $localError',
        );

        return [];
      }
    }
  }
}