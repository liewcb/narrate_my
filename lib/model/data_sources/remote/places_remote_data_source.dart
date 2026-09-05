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

  /// Guards every Google Places request against a missing API key so a
  /// configuration failure surfaces as a clear error instead of a silent
  /// "0 places found" (which would hide the real problem).
  void _ensureApiKey() {
    if (_apiKey.isEmpty) {
      throw StateError(
        'Google Places API authentication failed. '
        'Please check the GOOGLE_MAPS_API_KEY configuration '
        '(set via --dart-define).',
      );
    }
  }

  /// Search for places near a location.
  Future<List<Place>> searchNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required List<String> types,
  }) async {
    _ensureApiKey();

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
    } catch (e) {
      _rethrowAuthError(e);
      return [];
    }
  }

  /// Search for places by text query, optionally biased to a location.
  Future<List<Place>> searchPlacesByText(
      String query, {
        double? latitude,
        double? longitude,
      }) async {
    _ensureApiKey();

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
    } catch (e) {
      _rethrowAuthError(e);
      return [];
    }
  }

  /// Get detailed place information by Google Place ID.
  Future<Place?> getPlaceDetails(String placeId) async {
    _ensureApiKey();

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
    } catch (e) {
      _rethrowAuthError(e);
      return null;
    }
  }

  /// Distinguishes authentication / configuration failures from transient
  /// network errors. Auth errors propagate so the generation layer can
  /// report the real problem; transient errors are silently returned as
  /// empty results (the caller will either skip or expand).
  void _rethrowAuthError(Object error) {
    final message = error.toString();
    if (message.contains('REQUEST_DENIED') ||
        message.contains('INVALID_REQUEST') ||
        message.contains('OVER_QUERY_LIMIT') ||
        message.contains('API key') ||
        message.contains('not configured')) {
      throw error is Exception ? error : Exception(error.toString());
    }
  }
}