/// Data Transfer Object representing spatial coordinates (Latitude, Longitude, Altitude).
/// Corresponds to `CoordinateDTO` in the system architecture diagram.
class CoordinateDTO {
  final double latitude;
  final double longitude;
  final double? altitude;

  const CoordinateDTO({
    required this.latitude,
    required this.longitude,
    this.altitude,
  });

  factory CoordinateDTO.fromJson(Map<String, dynamic> json) {
    return CoordinateDTO(
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      altitude: _parseDoubleNullable(json['altitude']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
    };
  }

  static double _parseDouble(dynamic val, {double fallback = 0.0}) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  static double? _parseDoubleNullable(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }
}

/// Backward compatibility alias for CoordinateDTO
typedef CoordinateDto = CoordinateDTO;
