import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_manager.dart';
import '../../entities/ar_site.dart';
import '../../entities/place.dart';

/// Resolves a Nearby AR pin to one verified Google Place.
///
/// The Edge Function keeps the Google Places server key off the device and
/// returns a short-lived signed image URL that is safe to display directly.
class ARSitePlaceRemoteDataSource {
  static final Map<String, Place> _resolvedPlaces = {};
  final SupabaseClient _client;

  ARSitePlaceRemoteDataSource({SupabaseClient? client})
    : _client = client ?? DatabaseManager().remote.client;

  Future<Place?> resolvePlace(ARSite site) async {
    final cacheKey = '${site.siteId}|${site.latitude}|${site.longitude}';
    final cached = _resolvedPlaces[cacheKey];
    if (cached != null) return cached;

    final response = await _client.functions.invoke(
      'resolve-ar-site-place',
      body: {
        'name': site.name,
        'search_names': <String>{
          ...site.matchAliases,
          site.name,
        }.toList(growable: false),
        'latitude': site.latitude,
        'longitude': site.longitude,
        'address': site.address,
        'category': site.category,
        'match_radius_meters': site.matchRadiusMeters,
        'google_place_ids': site.googlePlaceIds,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw ARSitePlaceResolutionException(
        response.data is Map && response.data['error'] != null
            ? response.data['error'].toString()
            : 'Unable to resolve this AR location.',
      );
    }
    if (response.data is! Map) return null;
    final rawPlace = response.data['place'];
    if (rawPlace is! Map) return null;
    final place = placeFromResponse(Map<String, dynamic>.from(rawPlace));
    if (place != null) _resolvedPlaces[cacheKey] = place;
    return place;
  }

  static Place? placeFromResponse(Map<String, dynamic> json) {
    final placeId = _text(json['place_id']);
    final name = _text(json['name']);
    final latitude = _number(json['latitude']);
    final longitude = _number(json['longitude']);
    if (placeId == null ||
        name == null ||
        latitude == null ||
        longitude == null) {
      return null;
    }

    return Place(
      id: placeId,
      placeId: placeId,
      placeName: name,
      placeAddress: _text(json['address']) ?? '',
      placeLatitude: latitude,
      placeLongitude: longitude,
      placeRating: _number(json['rating']) ?? 0,
      placeTypes: _strings(json['types']),
      placePhotoRef: _text(json['photo_reference']),
      placeImageUrl: _text(json['image_url']),
      placePhotoGoogleMapsUri: _text(json['google_maps_uri']),
      category: _text(json['category']),
    );
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static List<String> _strings(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class ARSitePlaceResolutionException implements Exception {
  final String message;

  const ARSitePlaceResolutionException(this.message);

  @override
  String toString() => message;
}
