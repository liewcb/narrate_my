

import '../../entities/place.dart';

abstract class PlaceRepository {
  Future<void> savePlace(Place place);
  Future<Place?> getPlace(String placeId);
  Future<List<Place>> getAllPlaces();
  Future<void> deletePlace(String placeId);
  Future<bool> exists(String placeId);
}