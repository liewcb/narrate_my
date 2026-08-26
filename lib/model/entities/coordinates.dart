// models/coordinates.dart
import 'dart:math' as math;

/// Geographic coordinates (latitude/longitude) with utility methods
/// for distance calculation.
class Coordinates {
  final double latitude;
  final double longitude;

  const Coordinates({
    required this.latitude,
    required this.longitude,
  });

  /// Distance to [other] in kilometers using the Haversine formula.
  double distanceTo(Coordinates other) {
    const double earthRadiusKm = 6371.0;

    double toRadians(double degrees) => degrees * math.pi / 180.0;

    final double dLat = toRadians(other.latitude - latitude);
    final double dLon = toRadians(other.longitude - longitude);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRadians(latitude)) *
            math.cos(toRadians(other.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  /// Convert to a Map for JSON serialization.
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  /// Create from JSON.
  factory Coordinates.fromJson(Map<String, dynamic> json) {
    return Coordinates(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'Coordinates(latitude: $latitude, longitude: $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Coordinates &&
              runtimeType == other.runtimeType &&
              latitude == other.latitude &&
              longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}