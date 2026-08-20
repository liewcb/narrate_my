import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/heritage_site_dto.dart';

/// Talks to Supabase for AR Exploration data (UC100, BF-4).
///
/// [C2] Geofence & Scan Radius Boundary: the query is bounded by a
/// lat/lng bounding box derived from [radiusMeters] so we never pull the
/// whole `Marker` table — Postgres/PostgREST filters server-side, we only
/// pay for rows actually near the tourist.
class ARRemoteDataSource {
  final SupabaseClient _client;

  ARRemoteDataSource({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  Future<List<HeritageSiteDto>> fetchNearbyMarkers({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    final box = _boundingBox(latitude, longitude, radiusMeters);

    final rows = await _client
        .from('Marker')
        .select('*, Attraction(*)')
        .gte('latitude', box.minLat)
        .lte('latitude', box.maxLat)
        .gte('longitude', box.minLng)
        .lte('longitude', box.maxLng);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(HeritageSiteDto.fromJson)
        .toList();
  }

  _BoundingBox _boundingBox(double lat, double lng, double radiusMeters) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng = 111320.0 * math.cos(lat * math.pi / 180.0);

    final dLat = radiusMeters / metersPerDegreeLat;
    // Guard against divide-by-~0 near the poles (irrelevant for this app,
    // but keeps the math safe).
    final dLng = radiusMeters / (metersPerDegreeLng.abs() < 1 ? 1 : metersPerDegreeLng);

    return _BoundingBox(
      minLat: lat - dLat,
      maxLat: lat + dLat,
      minLng: lng - dLng,
      maxLng: lng + dLng,
    );
  }
}

class _BoundingBox {
  final double minLat, maxLat, minLng, maxLng;
  const _BoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });
}
