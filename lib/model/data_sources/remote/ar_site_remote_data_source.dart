import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/database_manager.dart';
import '../../dto/ar_site_dto.dart';
import '../../entities/ar_site.dart';

/// Read-only map discovery source. It reuses existing Attraction and Marker
/// rows but does not participate in the AR camera/placement workflow.
class ARSiteRemoteDataSource {
  final SupabaseClient _client;

  ARSiteRemoteDataSource({SupabaseClient? client})
    : _client = client ?? DatabaseManager().remote.client;

  Future<List<ARSite>> fetchNearbySites({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    final box = _boundingBox(latitude, longitude, radiusMeters);
    // The optional site_id remains untouched for other modules, but is not
    // used to merge attractions on the Nearby map. Only attractions whose
    // Marker rows have exactly equal coordinates share a map pin.
    final markerById = <String, Map<String, dynamic>>{};
    final rawNearbyMarkers = await _client
        .from('Marker')
        .select('marker_id, latitude, longitude, activation_radius')
        .gte('latitude', box.minLat)
        .lte('latitude', box.maxLat)
        .gte('longitude', box.minLng)
        .lte('longitude', box.maxLng);
    for (final row in rawNearbyMarkers) {
      final json = Map<String, dynamic>.from(row);
      markerById[json['marker_id']?.toString() ?? ''] = json;
    }

    final nearbyMarkerIds = markerById.keys
        .where((markerId) => markerId.isNotEmpty)
        .toList();
    if (nearbyMarkerIds.isEmpty) return const [];

    final rows = await _client
        .from('Attraction')
        .select('attraction_id, site_id, marker_id, name')
        .inFilter('marker_id', nearbyMarkerIds);

    final parentSitesById = await _fetchParentSites(
      rows
          .map((row) => row['site_id']?.toString().trim() ?? '')
          .where((siteId) => siteId.isNotEmpty)
          .toSet(),
    );

    final experiences = <ARSiteExperience>[];
    for (final row in rows) {
      final dto = ARSiteExperienceDto.fromJson(Map<String, dynamic>.from(row));
      final experience = _toExperience(dto, markerById);
      if (experience == null || experience.attractionId.isEmpty) continue;
      experiences.add(experience);
    }
    return groupNearbyARExperiencesByExactCoordinates(
      experiences,
      parentSitesById: parentSitesById,
    );
  }

  Future<Map<String, ARSite>> _fetchParentSites(Set<String> siteIds) async {
    if (siteIds.isEmpty) return const {};
    try {
      final rows = await _client
          .from('ar_sites')
          .select(
            'site_id, display_name, latitude, longitude, address, category, '
            'google_place_ids, match_aliases, match_radius_meters',
          )
          .inFilter('site_id', siteIds.toList());
      return {
        for (final row in rows)
          if (row['site_id']?.toString().trim().isNotEmpty == true)
            row['site_id'].toString(): ARSiteDto.fromJson(
              Map<String, dynamic>.from(row),
            ).toEntity(),
      };
    } catch (error) {
      // AR markers should still load when optional parent-place metadata has
      // not been configured yet. Photo/bookmark resolution can then fall back
      // to the exact attraction name and coordinates.
      debugPrint('Unable to enrich AR locations from ar_sites: $error');
      return const {};
    }
  }

  ARSiteExperience? _toExperience(
    ARSiteExperienceDto attraction,
    Map<String, Map<String, dynamic>> markerById,
  ) {
    final marker = markerById[attraction.markerId];
    if (marker == null) return null;
    final markerLatitude = _toDouble(marker['latitude']);
    final markerLongitude = _toDouble(marker['longitude']);
    if (markerLatitude == null || markerLongitude == null) return null;
    final activationRadius =
        _toDouble(marker['activation_radius']) ??
        AppConfig.fallbackActivationRadiusMeters;
    return ARSiteExperience(
      attractionId: attraction.attractionId,
      parentSiteId: attraction.siteId.isEmpty ? null : attraction.siteId,
      markerId: attraction.markerId,
      name: attraction.name,
      latitude: markerLatitude,
      longitude: markerLongitude,
      activationRadiusMeters: activationRadius,
    );
  }

  _BoundingBox _boundingBox(double lat, double lng, double radiusMeters) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng = 111320.0 * math.cos(lat * math.pi / 180.0);
    final dLat = radiusMeters / metersPerDegreeLat;
    final dLng =
        radiusMeters / (metersPerDegreeLng.abs() < 1 ? 1 : metersPerDegreeLng);
    return _BoundingBox(
      minLat: lat - dLat,
      maxLat: lat + dLat,
      minLng: lng - dLng,
      maxLng: lng + dLng,
    );
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _BoundingBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const _BoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });
}
