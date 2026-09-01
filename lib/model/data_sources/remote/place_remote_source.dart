import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/remote_database_service.dart';
import '../../dto/place_dto.dart';
import '../../entities/place.dart';

/// Handles persistence and retrieval of places
/// from the Supabase `places` table.
///
/// This class is responsible ONLY for Supabase.
///
/// Google Places API should continue to be handled
/// by PlacesRemoteDataSource.
class PlaceRemoteSource {
  final SupabaseClient _client;

  PlaceRemoteSource({
    SupabaseClient? client,
  }) : _client =
      client ?? RemoteDatabaseService().client;

  // ============================================================
  // GET ALL PLACES
  // ============================================================

  Future<List<Place>> getAllPlaces() async {
    try {
      final response = await _client
          .from('places')
          .select()
          .order(
        'created_at',
        ascending: false,
      );

      return (response as List)
          .map(
            (json) => PlaceDto.fromJson(
          Map<String, dynamic>.from(json),
        ).toEntity(),
      )
          .toList();
    } catch (e) {
      throw Exception(
        'Failed to get all places: $e',
      );
    }
  }

  // ============================================================
  // GET PLACE BY DATABASE ID
  // ============================================================

  Future<Place?> getPlaceById(
      String id,
      ) async {
    try {
      final response = await _client
          .from('places')
          .select()
          .eq(
        'id',
        id,
      )
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return PlaceDto.fromJson(
        Map<String, dynamic>.from(response),
      ).toEntity();
    } catch (e) {
      throw Exception(
        'Failed to get place by ID: $e',
      );
    }
  }

  // ============================================================
  // GET PLACE BY GOOGLE PLACE ID
  // ============================================================

  Future<Place?> getPlaceByPlaceId(
      String placeId,
      ) async {
    try {
      final response = await _client
          .from('places')
          .select()
          .eq(
        'place_id',
        placeId,
      )
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return PlaceDto.fromJson(
        Map<String, dynamic>.from(response),
      ).toEntity();
    } catch (e) {
      throw Exception(
        'Failed to get place by place ID: $e',
      );
    }
  }

  // ============================================================
  // UPSERT PLACE
  // ============================================================

  Future<Place> upsertPlace(
      Place place,
      ) async {
    try {
      final dto =
      PlaceDto.fromEntity(place);

      final response = await _client
          .from('places')
          .upsert(
        dto.toJsonForRemote(),
        onConflict: 'id',
      )
          .select()
          .single();

      return PlaceDto.fromJson(
        Map<String, dynamic>.from(response),
      ).toEntity();
    } catch (e) {
      throw Exception(
        'Failed to upsert place: $e',
      );
    }
  }

  // ============================================================
  // DELETE PLACE BY ID
  // ============================================================

  Future<void> deletePlace(
      String id,
      ) async {
    try {
      await _client
          .from('places')
          .delete()
          .eq(
        'id',
        id,
      );
    } catch (e) {
      throw Exception(
        'Failed to delete place: $e',
      );
    }
  }

  // ============================================================
  // CHECK WHETHER PLACE EXISTS
  // ============================================================

  Future<bool> placeExists(
      String placeId,
      ) async {
    try {
      final response = await _client
          .from('places')
          .select('id')
          .eq(
        'place_id',
        placeId,
      )
          .maybeSingle();

      return response != null;
    } catch (e) {
      throw Exception(
        'Failed to check place existence: $e',
      );
    }
  }

  // ============================================================
  // SEARCH PLACES BY NAME
  // ============================================================

  Future<List<Place>> searchPlacesByName(
      String name,
      ) async {
    try {
      final response = await _client
          .from('places')
          .select()
          .ilike(
        'name',
        '%$name%',
      )
          .order(
        'name',
        ascending: true,
      );

      return (response as List)
          .map(
            (json) => PlaceDto.fromJson(
          Map<String, dynamic>.from(json),
        ).toEntity(),
      )
          .toList();
    } catch (e) {
      throw Exception(
        'Failed to search places by name: $e',
      );
    }
  }

  // ============================================================
  // GET PLACES BY CATEGORY
  // ============================================================

  Future<List<Place>> getPlacesByCategory(
      String category,
      ) async {
    try {
      final response = await _client
          .from('places')
          .select()
          .eq(
        'category',
        category,
      )
          .order(
        'name',
        ascending: true,
      );

      return (response as List)
          .map(
            (json) => PlaceDto.fromJson(
          Map<String, dynamic>.from(json),
        ).toEntity(),
      )
          .toList();
    } catch (e) {
      throw Exception(
        'Failed to get places by category: $e',
      );
    }
  }

  // ============================================================
  // GET PLACES BY TYPE
  // ============================================================

  Future<List<Place>> getPlacesByType(
      String type,
      ) async {
    try {
      final response = await _client
          .from('places')
          .select()
          .contains(
        'types',
        [type],
      )
          .order(
        'name',
        ascending: true,
      );

      return (response as List)
          .map(
            (json) => PlaceDto.fromJson(
          Map<String, dynamic>.from(json),
        ).toEntity(),
      )
          .toList();
    } catch (e) {
      throw Exception(
        'Failed to get places by type: $e',
      );
    }
  }

  // ============================================================
  // SEARCH NEARBY PLACES
  // ============================================================
  //
  // This uses the latitude/longitude stored in Supabase.
  //
  // NOTE:
  // This is a simple bounding-box search.
  // It is NOT an exact circular distance calculation.
  //
  // For Google Nearby Search, continue using
  // PlacesRemoteDataSource.
  // ============================================================

  Future<List<Place>> searchNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    List<String>? types,
  }) async {
    try {
      // Approximate conversion:
      // 1 degree latitude ≈ 111,000 meters.
      final latitudeDelta =
          radiusMeters / 111000;

      final longitudeDelta =
          radiusMeters /
              (111000 *
                  _cosLatitude(latitude));

      final minLatitude =
          latitude - latitudeDelta;

      final maxLatitude =
          latitude + latitudeDelta;

      final minLongitude =
          longitude - longitudeDelta;

      final maxLongitude =
          longitude + longitudeDelta;

      var query = _client
          .from('places')
          .select()
          .gte(
        'latitude',
        minLatitude,
      )
          .lte(
        'latitude',
        maxLatitude,
      )
          .gte(
        'longitude',
        minLongitude,
      )
          .lte(
        'longitude',
        maxLongitude,
      );

      final response = await query;

      List<Place> places = (response as List)
          .map(
            (json) => PlaceDto.fromJson(
          Map<String, dynamic>.from(json),
        ).toEntity(),
      )
          .toList();

      // Optional type filtering.
      if (types != null && types.isNotEmpty) {
        places = places.where((place) {
          if (place.types == null) {
            return false;
          }

          return types.any(
                (type) =>
                place.types!.contains(type),
          );
        }).toList();
      }

      return places;
    } catch (e) {
      throw Exception(
        'Failed to search nearby places: $e',
      );
    }
  }

  // ============================================================
  // PRIVATE HELPER
  // ============================================================

  double _cosLatitude(
      double latitude,
      ) {
    // Convert degrees to radians.
    final radians =
        latitude * 3.141592653589793 / 180;

    // Avoid importing dart:math just for cos
    // by using a simple approximation.
    //
    // For Malaysia this approximation is sufficient
    // for the bounding-box calculation.
    final x = radians;

    return 1 -
        (x * x / 2) +
        (x * x * x * x / 24);
  }
}