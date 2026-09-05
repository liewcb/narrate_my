import 'dart:math' as math;

/// A visitor-facing AR attraction marker on the Nearby map.
///
/// The current map data source creates one of these for every `Attraction`
/// row. The optional parent-site metadata remains available to other modules.
class ARSite {
  final String siteId;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final String? category;
  final List<String> googlePlaceIds;
  final List<String> matchAliases;
  final double matchRadiusMeters;
  final List<ARSiteExperience> experiences;

  const ARSite({
    required this.siteId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.category,
    this.googlePlaceIds = const [],
    this.matchAliases = const [],
    this.matchRadiusMeters = 150,
    this.experiences = const [],
  });

  ARSite copyWith({List<ARSiteExperience>? experiences}) {
    return ARSite(
      siteId: siteId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      address: address,
      category: category,
      googlePlaceIds: googlePlaceIds,
      matchAliases: matchAliases,
      matchRadiusMeters: matchRadiusMeters,
      experiences: experiences ?? this.experiences,
    );
  }

  /// Exact Google Place IDs are authoritative. Aliases plus proximity are a
  /// conservative fallback while a site's Google IDs are still being filled.
  bool matchesPlace({
    required String googlePlaceId,
    required String placeName,
    required double placeLatitude,
    required double placeLongitude,
  }) {
    final canonicalId = googlePlaceId.trim();
    if (canonicalId.isNotEmpty &&
        googlePlaceIds.any((id) => id.trim() == canonicalId)) {
      return true;
    }

    if (distanceMetersFrom(placeLatitude, placeLongitude) > matchRadiusMeters) {
      return false;
    }

    final normalizedPlaceName = _normalize(placeName);
    if (normalizedPlaceName.isEmpty) return false;
    final names = [name, ...matchAliases].map(_normalize);
    return names.any(
      (candidate) =>
          candidate.isNotEmpty &&
          (normalizedPlaceName.contains(candidate) ||
              candidate.contains(normalizedPlaceName)),
    );
  }

  double distanceMetersFrom(double userLatitude, double userLongitude) {
    return _haversineMeters(userLatitude, userLongitude, latitude, longitude);
  }

  ARSiteExperience? nearestExperienceTo(
    double userLatitude,
    double userLongitude,
  ) {
    if (experiences.isEmpty) return null;
    final sorted = [...experiences]
      ..sort(
        (a, b) => a
            .distanceMetersFrom(userLatitude, userLongitude)
            .compareTo(b.distanceMetersFrom(userLatitude, userLongitude)),
      );
    return sorted.first;
  }

  bool canOpenArAt(double userLatitude, double userLongitude) {
    return experiences.any(
      (experience) => experience.isActiveAt(userLatitude, userLongitude),
    );
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }
}

class ARSiteExperience {
  final String attractionId;
  final String markerId;
  final String name;
  final double latitude;
  final double longitude;
  final double activationRadiusMeters;

  const ARSiteExperience({
    required this.attractionId,
    required this.markerId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.activationRadiusMeters,
  });

  double distanceMetersFrom(double userLatitude, double userLongitude) {
    return _haversineMeters(userLatitude, userLongitude, latitude, longitude);
  }

  bool isActiveAt(double userLatitude, double userLongitude) {
    return distanceMetersFrom(userLatitude, userLongitude) <=
        activationRadiusMeters;
  }
}

/// Converts experiences that have not yet been assigned a parent site into
/// temporary visitor-facing sites. Experiences sharing one Marker produce one
/// pin, so the fallback cannot create stacked duplicate markers.
List<ARSite> groupUngroupedARExperiences(
  Iterable<ARSiteExperience> experiences,
) {
  final byMarker = <String, List<ARSiteExperience>>{};
  for (final experience in experiences) {
    if (experience.markerId.isEmpty) continue;
    byMarker.putIfAbsent(experience.markerId, () => []).add(experience);
  }

  final sites = <ARSite>[];
  for (final entry in byMarker.entries) {
    final markerExperiences = entry.value;
    if (markerExperiences.isEmpty) continue;
    final first = markerExperiences.first;
    final largestActivationRadius = markerExperiences
        .map((experience) => experience.activationRadiusMeters)
        .fold<double>(0, math.max);
    sites.add(
      ARSite(
        siteId: 'UNLINKED_${entry.key}',
        name: first.name,
        latitude: first.latitude,
        longitude: first.longitude,
        category: 'AR location',
        matchAliases: markerExperiences
            .map((experience) => experience.name)
            .toList(),
        matchRadiusMeters: math.max(150, largestActivationRadius),
        experiences: markerExperiences,
      ),
    );
  }
  sites.sort((a, b) => a.name.compareTo(b.name));
  return sites;
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _degreesToRadians(lat2 - lat1);
  final dLon = _degreesToRadians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(lat1)) *
          math.cos(_degreesToRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;
