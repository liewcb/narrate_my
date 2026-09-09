import '../../../entities/coordinates.dart';
import '../../../entities/place.dart';

abstract interface class AiPlaceRepository {
  Future<List<Place>> fetchBookmarkablePlaces();
  Future<List<Place>> searchTextPlaces({required String query});
  Future<List<Place>> searchNearbyPlaces({
    required Coordinates origin,
    required List<String> includedTypes,
    required double radiusKm,
  });
}
