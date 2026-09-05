import 'dart:math' as math;

/// Domain entity for a landmark marker rendered in the AR Exploration
/// scene (UC100). Combines the static geo/anchor data from the `Marker`
/// table with the display info from its linked `Attraction` row.
///
/// `distanceMeters`, `bearingFromUser` and `isFacing` are NOT stored — they
/// are computed live against the tourist's current GPS position + compass
/// heading (see [ARMarker.withComputedGeometry]).
class ARMarker {
  final String markerId;
  final String? attractionId;
  final double latitude;
  final double longitude;
  final double? altitude;

  /// Authored "expected viewing" bearing for this marker, if the site
  /// surveyor set one. Used only as a fallback when live bearing can't be
  /// computed (e.g. user position unavailable).
  final double? targetBearing;

  /// Per-marker override for how close the tourist must be before this
  /// marker is considered active/relevant.
  final double activationRadiusMeters;

  final String name;
  final String? description;
  final List<String> labels;

  /// Live-computed distance from the tourist to this marker, in meters.
  final double? distanceMeters;

  /// Live-computed initial bearing (0-360°) from the tourist to this
  /// marker.
  final double? bearingFromUser;

  /// True when the device compass heading is within
  /// [AppConfig.headingToleranceDegrees] of [bearingFromUser] — i.e. the
  /// tourist is "directly facing" this landmark (BF-6).
  final bool isFacing;

  const ARMarker({
    required this.markerId,
    this.attractionId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.targetBearing,
    required this.activationRadiusMeters,
    required this.name,
    this.description,
    this.labels = const [],
    this.distanceMeters,
    this.bearingFromUser,
    this.isFacing = false,
  });

  /// Returns a copy with distance/bearing/isFacing computed against the
  /// tourist's current position + device heading.
  ARMarker withComputedGeometry({
    required double userLat,
    required double userLng,
    required double deviceHeadingDegrees,
    required double headingToleranceDegrees,
  }) {
    final distance = _haversineMeters(userLat, userLng, latitude, longitude);
    final bearing = _initialBearingDegrees(userLat, userLng, latitude, longitude);
    final diff = _angularDifference(deviceHeadingDegrees, bearing);

    return ARMarker(
      markerId: markerId,
      attractionId: attractionId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      targetBearing: targetBearing,
      activationRadiusMeters: activationRadiusMeters,
      name: name,
      description: description,
      labels: labels,
      distanceMeters: distance,
      bearingFromUser: bearing,
      isFacing: diff <= headingToleranceDegrees,
    );
  }

  ARMarker copyWith({
    String? markerId,
    String? attractionId,
    double? latitude,
    double? longitude,
    double? altitude,
    double? targetBearing,
    double? activationRadiusMeters,
    String? name,
    String? description,
    List<String>? labels,
    double? distanceMeters,
    double? bearingFromUser,
    bool? isFacing,
  }) {
    return ARMarker(
      markerId: markerId ?? this.markerId,
      attractionId: attractionId ?? this.attractionId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      targetBearing: targetBearing ?? this.targetBearing,
      activationRadiusMeters: activationRadiusMeters ?? this.activationRadiusMeters,
      name: name ?? this.name,
      description: description ?? this.description,
      labels: labels ?? this.labels,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      bearingFromUser: bearingFromUser ?? this.bearingFromUser,
      isFacing: isFacing ?? this.isFacing,
    );
  }

  /// Whether the tourist is currently within this marker's own activation
  /// radius (falls back to "unknown" -> false if distance hasn't been
  /// computed yet).
  bool get isWithinActivationRadius =>
      distanceMeters != null && distanceMeters! <= activationRadiusMeters;

  static double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _initialBearingDegrees(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _degToRad(lat1);
    final phi2 = _degToRad(lat2);
    final deltaLambda = _degToRad(lon2 - lon1);

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (_radToDeg(theta) + 360) % 360;
  }

  static double _angularDifference(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);
}
