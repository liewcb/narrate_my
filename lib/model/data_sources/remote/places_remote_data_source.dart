import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/config/api_keys.dart';
import '../../dto/place_dto.dart';
import '../../entities/place.dart';

/// Talks to the Google Places API for Candidate Retrieval (pipeline Step 1).
class PlacesRemoteDataSource {
  static const String _nearbySearchUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';
  static const String _textSearchUrl =
      'https://maps.googleapis.com/maps/api/place/textsearch/json';
  static const String _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';

  final String _apiKey;
  final http.Client _client;

  PlacesRemoteDataSource({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = apiKey ?? ApiKeys.googleMapsApiKey;

  /// Search for places near a location.
  Future<List<Place>> searchNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required List<String> types,
  }) async {
    final url = Uri.parse(
      '$_nearbySearchUrl'
          '?location=$latitude,$longitude'
          '&radius=${radiusMeters.round()}'
          '&types=${types.join('|')}'
          '&key=$_apiKey',
    );

    try {
      final response = await _client.get(url);
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['status'] == 'OK') {
        final results = data['results'] as List? ?? [];
        return results
            .cast<Map<String, dynamic>>()
            .map(Place.fromGooglePlacesJson)
            .toList();
      }

      if (data['status'] != 'ZERO_RESULTS') {
        throw Exception(
          'Google Places API error: ${data['status']}'
              '${data['error_message'] != null ? ' — ${data['error_message']}' : ''}',
        );
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Search for places by text query, optionally biased to a location.
  Future<List<Place>> searchPlacesByText(
      String query, {
        double? latitude,
        double? longitude,
      }) async {
    final url = Uri.parse(
      '$_textSearchUrl'
          '?query=${Uri.encodeComponent(query)}'
          '${latitude != null && longitude != null ? '&location=$latitude,$longitude&radius=50000' : ''}'
          '&key=$_apiKey',
    );

    try {
      final response = await _client.get(url);
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['status'] == 'OK') {
        final results = data['results'] as List? ?? [];
        return results
            .cast<Map<String, dynamic>>()
            .map(Place.fromGooglePlacesJson)
            .toList();
      }

      if (data['status'] != 'ZERO_RESULTS') {
        throw Exception(
          'Google Places API error: ${data['status']}'
              '${data['error_message'] != null ? ' — ${data['error_message']}' : ''}',
        );
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get detailed place information by Google Place ID.
  Future<Place?> getPlaceDetails(String placeId) async {
    final url = Uri.parse(
      '$_detailsUrl'
          '?place_id=${Uri.encodeComponent(placeId)}'
          '&key=$_apiKey',
    );

    try {
      final response = await _client.get(url);
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['status'] == 'OK') {
        final result = data['result'] as Map<String, dynamic>;
        return Place.fromGooglePlacesJson(result);
      }

      throw Exception(
        'Google Places API error: ${data['status']}'
            '${data['error_message'] != null ? ' — ${data['error_message']}' : ''}',
      );
    } catch (_) {
      return null;
    }
  }
}