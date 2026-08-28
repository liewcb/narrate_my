// lib/model/entities/destination_hotspot.dart
//
// A high-density, high-footfall area within a destination that the candidate
// retrieval pipeline uses as a multi-center search anchor.
//
// Mirrors the `destination_hotspots` Supabase table:
//   id                    VARCHAR(15) PRIMARY KEY
//   destination_id        VARCHAR(10) NOT NULL (FK -> destinations.destination_id)
//   hotspot_name          VARCHAR(100) NOT NULL
//   latitude              DECIMAL(9,6) NOT NULL
//   longitude             DECIMAL(9,6) NOT NULL
//   suggested_radius_km   DECIMAL(3,1) DEFAULT 2.0
//   primary_theme         VARCHAR(50) NOT NULL    (e.g. shopping_dining)
//   tags                  TEXT[] NOT NULL         (interest matching tags)

class DestinationHotspot {
  final String id;
  final String destinationId;
  final String hotspotName;
  final double latitude;
  final double longitude;
  final double suggestedRadiusKm;
  final String primaryTheme;
  final List<String> tags;

  const DestinationHotspot({
    required this.id,
    required this.destinationId,
    required this.hotspotName,
    required this.latitude,
    required this.longitude,
    this.suggestedRadiusKm = 2.0,
    this.primaryTheme = '',
    this.tags = const [],
  });

  /// Convenience alias matching [Destination.name].
  String get name => hotspotName;

  /// Whether this hotspot matches any of the given normalized interest tags.
  bool matchesAnyTag(Iterable<String> normalizedTags) {
    for (final tag in normalizedTags) {
      if (tags.contains(tag)) return true;
    }
    return false;
  }

  DestinationHotspot copyWith({
    String? id,
    String? destinationId,
    String? hotspotName,
    double? latitude,
    double? longitude,
    double? suggestedRadiusKm,
    String? primaryTheme,
    List<String>? tags,
  }) {
    return DestinationHotspot(
      id: id ?? this.id,
      destinationId: destinationId ?? this.destinationId,
      hotspotName: hotspotName ?? this.hotspotName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      suggestedRadiusKm: suggestedRadiusKm ?? this.suggestedRadiusKm,
      primaryTheme: primaryTheme ?? this.primaryTheme,
      tags: tags ?? this.tags,
    );
  }

  @override
  String toString() =>
      'DestinationHotspot(id: $id, name: $hotspotName, tags: $tags)';
}
