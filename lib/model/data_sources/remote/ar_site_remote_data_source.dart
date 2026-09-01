import 'dart:math' as math;

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
    final rawSites = await _client
        .from('ar_sites')
        .select()
        .eq('is_active', true)
        .gte('latitude', box.minLat)
        .lte('latitude', box.maxLat)
        .gte('longitude', box.minLng)
        .lte('longitude', box.maxLng)
        .order('display_name');

    final siteDtos = rawSites
        .map((row) => ARSiteDto.fromJson(Map<String, dynamic>.from(row)))
        .toList();

    // Fetch Marker first so ungrouped experiences remain bounded by the same
    // geographic radius as parent sites. A teammate can keep inserting the
    // existing Marker + Attraction pair without creating an ar_sites row.
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

    final linkedAttractions = <ARSiteExperienceDto>[];
    final siteIds = siteDtos.map((site) => site.siteId).toList();
    if (siteIds.isNotEmpty) {
      final rows = await _client
          .from('Attraction')
          .select('attraction_id, site_id, marker_id, name')
          .inFilter('site_id', siteIds);
      linkedAttractions.addAll(
        rows.map(
          (row) => ARSiteExperienceDto.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
    }

    final unlinkedAttractions = <ARSiteExperienceDto>[];
    final nearbyMarkerIds = markerById.keys
        .where((markerId) => markerId.isNotEmpty)
        .toList();
    if (nearbyMarkerIds.isNotEmpty) {
      final rows = await _client
          .from('Attraction')
          .select('attraction_id, site_id, marker_id, name')
          .inFilter('marker_id', nearbyMarkerIds)
          .isFilter('site_id', null);
      unlinkedAttractions.addAll(
        rows.map(
          (row) => ARSiteExperienceDto.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
    }

    // Normally every experience belonging to an in-range site is nearby too.
    // Fetch any missing linked markers explicitly so a site sheet still lists
    // every child even when one sits just outside the bounding-box edge.
    final missingLinkedMarkerIds = linkedAttractions
        .map((attraction) => attraction.markerId)
        .where(
          (markerId) =>
              markerId.isNotEmpty && !markerById.containsKey(markerId),
        )
        .toSet()
        .toList();
    if (missingLinkedMarkerIds.isNotEmpty) {
      final rows = await _client
          .from('Marker')
          .select('marker_id, latitude, longitude, activation_radius')
          .inFilter('marker_id', missingLinkedMarkerIds);
      for (final row in rows) {
        final json = Map<String, dynamic>.from(row);
        markerById[json['marker_id']?.toString() ?? ''] = json;
      }
    }

    final experiencesBySite = <String, List<ARSiteExperience>>{};
    for (final attraction in linkedAttractions) {
      final experience = _toExperience(attraction, markerById);
      if (experience == null) continue;
      experiencesBySite
          .putIfAbsent(attraction.siteId, () => [])
          .add(experience);
    }

    final groupedSites = siteDtos
        .map(
          (site) => site.toEntity(
            experiences: experiencesBySite[site.siteId] ?? const [],
          ),
        )
        .toList();

    // Several Attraction rows can share one Marker. Keep one fallback pin per
    // marker and list every linked experience in that pin's details sheet.
    final fallbackSites = groupUngroupedARExperiences(
      unlinkedAttractions
          .map((attraction) => _toExperience(attraction, markerById))
          .whereType<ARSiteExperience>(),
    );

    return [...groupedSites, ...fallbackSites];
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
