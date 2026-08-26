import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/config/api_keys.dart';
import '../../entities/place.dart';

/// Talks to the Google Places API for Candidate Retrieval (pipeline Step 1).
///
/// Follows the same pattern as [ARRemoteDataSource]: thin HTTP layer,
/// no business rules here — deduping/filtering/limiting lives in
/// [CandidateRetrievalService].
class PlacesRemoteDataSource {
  static const String _nearbySearchUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  final String _apiKey;
  final http.Client _client;

  PlacesRemoteDataSource({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = apiKey ?? ApiKeys.googleMapsApiKey;

  /// Search for places near a location.
  ///
  /// [radiusMeters] is in meters (Google API unit); callers convert from
  /// [ItineraryConstants.searchRadiusKm].
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

      // ZERO_RESULTS is normal for sparse areas, not an error.
      if (data['status'] != 'ZERO_RESULTS') {
        throw Exception(
          'Google Places API error: ${data['status']}'
          '${data['error_message'] != null ? ' — ${data['error_message']}' : ''}',
        );
      }
      return [];
    } catch (_) {
      // Swallow and return empty so one bad destination doesn't kill
      // the whole retrieval pass; pipeline logs progress upstream.
      return [];
    }
  }
}
