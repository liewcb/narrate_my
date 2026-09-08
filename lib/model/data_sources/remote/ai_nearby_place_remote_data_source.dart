import '../../../core/services/database_manager.dart';
import '../../dto/place_dto.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';

/// Server-side Google Places lookup used by AI chat place requests.
///
/// The Places Web Service key stays in Supabase. The mobile application sends
/// either a direct text query or search coordinates, radius, and an
/// allow-listed place type.
class AiNearbyPlaceRemoteDataSource {
  AiNearbyPlaceRemoteDataSource({DatabaseManager? databaseManager})
    : _databaseManager = databaseManager ?? DatabaseManager();

  final DatabaseManager _databaseManager;

  Future<List<Place>> searchTextPlaces({required String query}) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const [];

    return _invoke({'query': trimmedQuery});
  }

  Future<List<Place>> searchNearbyPlaces({
    required Coordinates origin,
    required List<String> includedTypes,
    required double radiusKm,
  }) async {
    return _invoke({
      'latitude': origin.latitude,
      'longitude': origin.longitude,
      'radius_km': radiusKm,
      'included_types': includedTypes,
    });
  }

  Future<List<Place>> _invoke(Map<String, Object> body) async {
    final response = await _databaseManager.remote.client.functions.invoke(
      'search-nearby-places',
      body: body,
    );

    if (response.status < 200 || response.status >= 300) {
      throw AiNearbyPlaceRemoteException(_errorMessage(response.data));
    }

    final data = response.data;
    if (data is! Map || data['places'] is! List) {
      throw const AiNearbyPlaceRemoteException(
        'Invalid verified-place response.',
      );
    }

    return (data['places'] as List)
        .whereType<Map>()
        .map(
          (row) => PlaceDto.fromJson(Map<String, dynamic>.from(row)).toEntity(),
        )
        .where(
          (place) =>
              place.placeId.trim().isNotEmpty &&
              place.placeName.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  String _errorMessage(dynamic data) {
    if (data is Map) {
      final message = data['error'] ?? data['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return 'Unable to retrieve verified places.';
  }
}

class AiNearbyPlaceRemoteException implements Exception {
  const AiNearbyPlaceRemoteException(this.message);

  final String message;

  @override
  String toString() => message;
}
