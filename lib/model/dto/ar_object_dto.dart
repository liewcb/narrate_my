/// DTO representing raw 3D / AR Object metadata from remote sources
class ARObjectDto {
  final String id;
  final String name;
  final String modelUrl;
  final double? scale;
  final Map<String, dynamic>? metadata;

  const ARObjectDto({
    required this.id,
    required this.name,
    required this.modelUrl,
    this.scale,
    this.metadata,
  });

  factory ARObjectDto.fromJson(Map<String, dynamic> json) {
    return ARObjectDto(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      modelUrl: json['model_url'] as String? ?? '',
      scale: (json['scale'] as num?)?.toDouble(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'model_url': modelUrl,
      'scale': scale,
      'metadata': metadata,
    };
  }
}

/// DTO representing coordinates (Latitude, Longitude, Altitude)
class CoordinateDto {
  final double latitude;
  final double longitude;
  final double? altitude;

  const CoordinateDto({
    required this.latitude,
    required this.longitude,
    this.altitude,
  });

  factory CoordinateDto.fromJson(Map<String, dynamic> json) {
    return CoordinateDto(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
    };
  }
}