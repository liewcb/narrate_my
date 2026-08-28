import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_keys.dart';
import '../../DTO/recommendation_place_dto.dart';

/// Google Places API (New) access owned by the Nearby Recommendation module.
///
/// Keeping this separate prevents changes to the itinerary module's legacy
/// Places data source and shared Place entity.
class RecommendationPlacesRemoteDataSource {
  static const String _textSearchUrl =
      'https://places.googleapis.com/v1/places:searchText';
  static const String _fieldMask =
      'places.id,places.displayName,places.formattedAddress,'
      'places.location,places.rating,places.photos';

  final String _apiKey;
  final http.Client _client;

  RecommendationPlacesRemoteDataSource({String? apiKey, http.Client? client})
    : _apiKey = apiKey ?? ApiKeys.googleMapsApiKey,
      _client = client ?? http.Client();

  Future<List<RecommendationPlaceDto>> searchText({
    required String query,
    required double latitude,
    required double longitude,
    double radiusMeters = 50000,
  }) async {
    _ensureApiKey();

    final response = await _client.post(
      Uri.parse(_textSearchUrl),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask': _fieldMask,
      },
      body: jsonEncode({
        'textQuery': query,
        'maxResultCount': 10,
        'locationBias': {
          'circle': {
            'center': {'latitude': latitude, 'longitude': longitude},
            'radius': radiusMeters.clamp(0, 50000).toDouble(),
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      throw RecommendationPlacesException(
        _errorMessage(response, operation: 'Text Search'),
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final places = data['places'] as List? ?? const [];
    return places
        .whereType<Map>()
        .map(
          (place) => RecommendationPlaceDto.fromPlacesApiNew(
            Map<String, dynamic>.from(place),
          ),
        )
        .toList();
  }

  String? buildPhotoUrl(String? photoResourceName, {int maxWidth = 1200}) {
    if (photoResourceName == null || photoResourceName.trim().isEmpty) {
      return null;
    }
    final resourceName = photoResourceName
        .trim()
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/media$'), '');
    if (!resourceName.startsWith('places/') ||
        !resourceName.contains('/photos/')) {
      return null;
    }

    return Uri.https('places.googleapis.com', '/v1/$resourceName/media', {
      'maxWidthPx': maxWidth.clamp(1, 4800).toString(),
      'key': _apiKey,
    }).toString();
  }

  void _ensureApiKey() {
    final key = _apiKey.trim();
    if (key.isEmpty ||
        key == 'YOUR_ACTUAL_KEY' ||
        key == 'DEFAULT_API_KEY' ||
        key == 'YOUR_GOOGLE_MAPS_API_KEY') {
      throw const RecommendationPlacesException(
        'The Google Maps API key was not loaded into Flutter.',
      );
    }
  }

  String _errorMessage(http.Response response, {required String operation}) {
    String? details;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error = data['error'];
      if (error is Map) details = error['message']?.toString();
    } catch (_) {
      // The status code is still useful for a non-JSON response.
    }
    return 'Google Places $operation failed (${response.statusCode})'
        '${details == null ? '' : ': $details'}';
  }
}

class RecommendationPlacesException implements Exception {
  final String message;

  const RecommendationPlacesException(this.message);

  @override
  String toString() => message;
}
