import '../entities/ar_object.dart';

/// Raw mapping of a Supabase query result joining `Marker` with its
/// embedded `Attraction` row(s):
///
/// ```
/// supabase.from('Marker').select('*, Attraction(*)')
/// ```
///
/// Kept separate from [ARMarker] so Supabase's on-the-wire JSON shape
/// (snake_case, embedded lists, nullable json labels) never leaks into
/// the rest of the app.
class HeritageSiteDto {
  final String markerId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? targetBearing;
  final int? activationRadius;

  final String? attractionName;
  final String? attractionContent;
  final List<String> labels;

  const HeritageSiteDto({
    required this.markerId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.targetBearing,
    this.activationRadius,
    this.attractionName,
    this.attractionContent,
    this.labels = const [],
  });

  factory HeritageSiteDto.fromJson(Map<String, dynamic> json) {
    // Embedded Attraction comes back as a List (PostgREST convention for
    // one-to-many via FK), even though in practice each Marker has one.
    final attractionsRaw = json['Attraction'];
    final Map<String, dynamic>? attraction = (attractionsRaw is List && attractionsRaw.isNotEmpty)
        ? attractionsRaw.first as Map<String, dynamic>
        : (attractionsRaw is Map<String, dynamic> ? attractionsRaw : null);

    List<String> parseLabels(dynamic raw) {
      if (raw == null) return const [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return const [];
    }

    return HeritageSiteDto(
      markerId: json['marker_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      targetBearing: (json['target_bearing'] as num?)?.toDouble(),
      activationRadius: (json['activation_radius'] as num?)?.toInt(),
      attractionName: attraction?['name'] as String?,
      attractionContent: attraction?['attraction_content'] as String?,
      labels: parseLabels(attraction?['labels']),
    );
  }

  ARMarker toEntity({required double fallbackActivationRadiusMeters}) {
    return ARMarker(
      markerId: markerId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      targetBearing: targetBearing,
      activationRadiusMeters: (activationRadius ?? fallbackActivationRadiusMeters).toDouble(),
      name: attractionName ?? 'Unnamed landmark',
      description: attractionContent,
      labels: labels,
    );
  }
}
