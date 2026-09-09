

import '../../../entities/place.dart';

abstract class PlaceRepository {
  Future<Place?> getPlaceDetails(String placeId);
  Future<List<Place>> searchPlacesByText(String query, {double? latitude, double? longitude});
  Future<void> savePlace(Place place);
  Future<Place?> getPlace(String placeId);
  Future<List<Place>> getAllPlaces();
  Future<void> deletePlace(String placeId);
  Future<bool> exists(String placeId);

  Future<List<Place>> searchNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    List<String>? types,
  });

  Future<List<Place>> searchDatabaseNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    List<String>? types,
  });
}