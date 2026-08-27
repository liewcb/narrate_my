import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/remote_database_service.dart';
import '../../dto/heritage_site_dto.dart';

/// Talks to Supabase for AR Exploration & Heritage data (UC100, BF-4).
///
/// [C2] Geofence & Scan Radius Boundary: the query is bounded by a
/// lat/lng bounding box derived from [radiusMeters] so we never pull the
/// whole `Marker` table — Postgres/PostgREST filters server-side, we only
/// pay for rows actually near the tourist.
class ARRemoteDataSource {
  final SupabaseClient _client;

  /// Depends on the app's single central RemoteDatabaseService instance
  /// (initialized once via DatabaseManager at startup) rather than
  /// reaching for Supabase.instance.client independently — keeps client
  /// lifecycle owned in exactly one place.
  ARRemoteDataSource({SupabaseClient? client})
      : _client = client ?? RemoteDatabaseService().client;

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

  /// Fetch attraction and marker data by [markerId] (e.g. 'MK001')
  Future<HeritageSiteDto?> fetchAttractionByMarkerId(String markerId) async {
    // 1. Try querying Marker joined with Attraction
    final markerRow = await _client
        .from('Marker')
        .select('*, Attraction(*)')
        .eq('marker_id', markerId)
        .maybeSingle();

    if (markerRow != null) {
      return HeritageSiteDto.fromJson(Map<String, dynamic>.from(markerRow));
    }

    // 2. Fallback: Query Attraction table directly by marker_id
    final attractionRow = await _client
        .from('Attraction')
        .select('*')
        .eq('marker_id', markerId)
        .maybeSingle();

    if (attractionRow != null) {
      return HeritageSiteDto.fromAttractionJson(
        Map<String, dynamic>.from(attractionRow),
      );
    }

    return null;
  }

  /// Fetch attraction by attraction_id (e.g. 'AD001')
  Future<HeritageSiteDto?> fetchAttractionById(String attractionId) async {
    final row = await _client
        .from('Attraction')
        .select('*, Marker(*)')
        .eq('attraction_id', attractionId)
        .maybeSingle();

    if (row != null) {
      return HeritageSiteDto.fromAttractionJson(
        Map<String, dynamic>.from(row),
      );
    }
    return null;
  }

  /// Fetch single marker by [markerId]
  Future<HeritageSiteDto?> fetchMarkerById(String markerId) async {
    final row = await _client
        .from('Marker')
        .select('*, Attraction(*)')
        .eq('marker_id', markerId)
        .maybeSingle();

    if (row != null) {
      return HeritageSiteDto.fromJson(Map<String, dynamic>.from(row));
    }
    return null;
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