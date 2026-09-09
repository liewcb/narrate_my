import '../../../../core/services/google_maps_service.dart';
import '../../../data_sources/remote/ai_bookmark_place_remote_data_source.dart';
import '../../../data_sources/remote/ai_nearby_place_remote_data_source.dart';
import '../../../entities/coordinates.dart';
import '../../../entities/place.dart';
import '../../interfaces/ai_assist/ai_place_repository.dart';

class AiPlaceRepositoryAdapter implements AiPlaceRepository {
  final AiBookmarkPlaceRemoteDataSource? _knownPlacesSource;
  final AiNearbyPlaceRemoteDataSource? _nearbyPlaceSource;
  final GoogleMapsService _maps;

  AiPlaceRepositoryAdapter({
    AiBookmarkPlaceRemoteDataSource? knownPlacesSource,
    AiNearbyPlaceRemoteDataSource? nearbyPlaceSource,
    GoogleMapsService? mapsService,
  }) : _knownPlacesSource = knownPlacesSource,
       _nearbyPlaceSource = nearbyPlaceSource,
       _maps = mapsService ?? GoogleMapsService();

  @override
  Future<List<Place>> fetchBookmarkablePlaces() =>
      (_knownPlacesSource ?? AiBookmarkPlaceRemoteDataSource()).fetchBookmarkablePlaces();

  @override
  Future<List<Place>> searchTextPlaces({required String query}) async {
    try {
      return await (_nearbyPlaceSource ?? AiNearbyPlaceRemoteDataSource()).searchTextPlaces(query: query);
    } catch (_) {
      if (_maps.googleMapsApiKey.trim().isEmpty) rethrow;
      return _maps.searchTextPlaces(query: query);
    }
  }

  @override
  Future<List<Place>> searchNearbyPlaces({required Coordinates origin,
    required List<String> includedTypes, required double radiusKm}) async {
    try {
      return await (_nearbyPlaceSource ?? AiNearbyPlaceRemoteDataSource()).searchNearbyPlaces(
          origin: origin, includedTypes: includedTypes, radiusKm: radiusKm);
    } catch (_) {
      if (_maps.googleMapsApiKey.trim().isEmpty) rethrow;
      return _maps.searchTextPlaces(query: includedTypes.join(' '),
          latitude: origin.latitude, longitude: origin.longitude, radius: radiusKm * 1000);
    }
  }
}
