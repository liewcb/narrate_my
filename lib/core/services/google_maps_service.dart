// lib/services/google_maps_service.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../../model/entities/coordinates.dart';
import '../../model/entities/place.dart';
import '../../model/entities/travel_info.dart';
import '../config/api_keys.dart';

/// Service for interacting with Google Maps Platform APIs:
/// - Places API (search nearby, get details)
/// - Directions API (travel time/distance)
/// - Fallback distance calculations (Haversine formula)
class GoogleMapsService {
  final String googleMapsApiKey = ApiKeys.googleMapsApiKey;

  // ==================== GOOGLE PLACES API ====================

  /// Search for places near a location using Google Places API.
  Future<List<Place>> searchNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radius,
    required List<String> types,
  }) async {
    _ensureApiKey();

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$latitude,$longitude'
      '&radius=$radius'
      '&types=${types.join('|')}'
      '&key=$googleMapsApiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final results = data['results'] as List;
      return results.map((json) => Place.fromGooglePlacesJson(json)).toList();
    } else {
      throw Exception('Failed to load places');
    }
  }

  /// Text search places using Google Places API (Places Text Search).
  ///
  /// Supports free-form queries such as "museum", "restaurant",
  /// "shopping mall", or a specific place name. When [latitude] and
  /// [longitude] are provided the search is biased/restricted to that
  /// location via the `location` + `radius` parameters.
  Future<List<Place>> searchTextPlaces({
    required String query,
    double? latitude,
    double? longitude,
    double radius = 50000, // 50 km bias around the destination
  }) async {
    _ensureApiKey();

    final params = StringBuffer('query=${Uri.encodeQueryComponent(query)}');
    if (latitude != null && longitude != null) {
      params.write('&location=$latitude,$longitude');
      params.write('&radius=$radius');
    }
    params.write('&key=$googleMapsApiKey');

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json?$params',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Google Places request failed (${response.statusCode})');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final status = data['status']?.toString();
    if (status == 'ZERO_RESULTS') return [];
    if (status != 'OK') {
      final details = data['error_message']?.toString();
      throw Exception(
        'Google Places API error: $status'
        '${details == null ? '' : ' - $details'}',
      );
    }

    final results = data['results'] as List? ?? const [];
    return results
        .map(
          (item) => Place.fromGooglePlacesJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  /// Compute the great-circle distance in km between two coordinates.
  double distanceKm(Coordinates a, Coordinates b) => _calculateDistance(a, b);

  /// Build a Google Places photo URL for a photo reference returned by a
  /// Places search. Returns null when the place has no photo.
  String? getPlacePhotoUrl(String? photoReference, {int maxWidth = 1200}) {
    if (photoReference == null || photoReference.trim().isEmpty) return null;
    return Uri.https('maps.googleapis.com', '/maps/api/place/photo', {
      'maxwidth': maxWidth.toString(),
      'photo_reference': photoReference,
      'key': googleMapsApiKey,
    }).toString();
  }

  // ==================== GEOCODING API ====================

  /// Resolve a free-form address / city name to coordinates using the
  /// Google Geocoding API. Returns null when the query cannot be
  /// geocoded or the API call fails.
  Future<Coordinates?> geocode(String query) async {
    if (query.trim().isEmpty) return null;

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?address=${Uri.encodeQueryComponent(query)}'
      '&key=$googleMapsApiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;

      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final location = (results.first as Map)['geometry']['location'] as Map;
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      return Coordinates(latitude: lat, longitude: lng);
    } catch (_) {
      return null;
    }
  }

  /// Get detailed place information by Google Place ID.
  Future<Place> getPlaceDetails(String placeId) async {
    _ensureApiKey();

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&key=$googleMapsApiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final result = data['result'];
      return Place.fromGooglePlacesJson(result);
    } else {
      throw Exception('Failed to get place details');
    }
  }

  // ==================== GOOGLE DIRECTIONS API ====================

  /// Get travel time and distance between two locations.
  /// Uses Google Directions API. Falls back to Haversine estimation if the API fails.
  Future<TravelInfo> getTravelTime({
    required Coordinates origin,
    required Coordinates destination,
    required String mode, // 'walking' or 'driving'
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=$mode'
      '&key=$googleMapsApiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final route = data['routes'][0];
      final leg = route['legs'][0];
      return TravelInfo(
        distanceKm: leg['distance']['value'] / 1000.0,
        durationMinutes: leg['duration']['value'] / 60.0,
        durationText: leg['duration']['text'],
      );
    } else {
      // Fallback: Estimate travel time using Haversine distance.
      return TravelInfo(
        distanceKm: _calculateDistance(origin, destination),
        durationMinutes: _estimateTravelTime(origin, destination, mode),
        durationText:
            '${_estimateTravelTime(origin, destination, mode).toInt()} min',
      );
    }
  }

  // ==================== PRIVATE HELPERS ====================

  /// Guards every Google Places request against a missing API key so a
  /// configuration failure surfaces as a clear error instead of a silent
  /// "0 places found" (which would hide the real problem).
  void _ensureApiKey() {
    if (googleMapsApiKey.isEmpty) {
      throw StateError(
        'Google Places API authentication failed. '
        'Please check the GOOGLE_MAPS_API_KEY configuration '
        '(set via --dart-define).',
      );
    }
  }

  /// Calculate the great-circle distance between two coordinates using the Haversine formula.
  double _calculateDistance(Coordinates a, Coordinates b) {
    const double R = 6371.0; // Earth's radius in km

    final double dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final double dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final double lat1 = a.latitude * math.pi / 180.0;
    final double lat2 = b.latitude * math.pi / 180.0;

    final double aVal =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) *
            math.sin(dLon / 2) *
            math.cos(lat1) *
            math.cos(lat2);

    final double c = 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));

    return R * c;
  }

  /// Estimate travel time in minutes based on distance and mode (walking/driving).
  double _estimateTravelTime(Coordinates a, Coordinates b, String mode) {
    final distance = _calculateDistance(a, b);
    final speed = mode == 'walking' ? 5.0 : 40.0; // km/h
    return (distance / speed) * 60; // minutes
  }
}
