import '../entities/ar_object.dart';
export 'coordinate_dto.dart';

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

/// Standard DTO mapping the `Marker` table in Supabase
class ARMarkerDto {
  final String markerId;
  final String? attractionId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? targetBearing;
  final int? activationRadius;
  final String? attractionName;
  final String? attractionContent;
  final List<String> labels;

  const ARMarkerDto({
    required this.markerId,
    this.attractionId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.targetBearing,
    this.activationRadius,
    this.attractionName,
    this.attractionContent,
    this.labels = const [],
  });

  factory ARMarkerDto.fromJson(Map<String, dynamic> json) {
    String? attractionId;
    String? attractionName;
    String? attractionContent;
    List<String> labels = const [];

    final rawAttraction = json['Attraction'];
    if (rawAttraction is List && rawAttraction.isNotEmpty) {
      final first = rawAttraction.first;
      if (first is Map<String, dynamic>) {
        attractionId = first['attraction_id'] as String?;
        attractionName = first['name'] as String?;
        attractionContent = first['attraction_content'] as String?;
        labels = _parseLabels(first['labels']);
      }
    } else if (rawAttraction is Map<String, dynamic>) {
      attractionId = rawAttraction['attraction_id'] as String?;
      attractionName = rawAttraction['name'] as String?;
      attractionContent = rawAttraction['attraction_content'] as String?;
      labels = _parseLabels(rawAttraction['labels']);
    }

    return ARMarkerDto(
      markerId: json['marker_id'] as String? ?? json['id'] as String? ?? '',
      attractionId: attractionId,
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      altitude: _parseDoubleNullable(json['altitude']),
      targetBearing: _parseDoubleNullable(json['target_bearing']),
      activationRadius: json['activation_radius'] as int?,
      attractionName: attractionName,
      attractionContent: attractionContent,
      labels: labels,
    );
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

  static List<String> _parseLabels(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  ARMarker toEntity({required double fallbackActivationRadiusMeters}) {
    return ARMarker(
      markerId: markerId,
      attractionId: attractionId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      targetBearing: targetBearing,
      activationRadiusMeters: (activationRadius ?? fallbackActivationRadiusMeters).toDouble(),
      name: attractionName ?? 'Heritage Landmark',
      description: attractionContent ?? "The attraction content is currently unavailable.",
      labels: labels,
    );
  }
}
