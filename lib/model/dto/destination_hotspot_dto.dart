// lib/model/dto/destination_hotspot_dto.dart
import '../entities/destination_hotspot.dart';

/// Data Transfer Object – used for serialisation to/from local DB and the
/// `destination_hotspots` Supabase table.
///
/// Column names match the Supabase schema exactly:
///   id, destination_id, hotspot_name, latitude, longitude,
///   suggested_radius_km, primary_theme, tags
class DestinationHotspotDto {
  final String id;
  final String destinationId;
  final String hotspotName;
  final double latitude;
  final double longitude;
  final double suggestedRadiusKm;
  final String primaryTheme;
  final List<String> tags;

  const DestinationHotspotDto({
    required this.id,
    required this.destinationId,
    required this.hotspotName,
    required this.latitude,
    required this.longitude,
    this.suggestedRadiusKm = 2.0,
    this.primaryTheme = '',
    this.tags = const [],
  });

  // ---------- Domain conversion ----------

  DestinationHotspot toDomain() {
    return DestinationHotspot(
      id: id,
      destinationId: destinationId,
      hotspotName: hotspotName,
      latitude: latitude,
      longitude: longitude,
      suggestedRadiusKm: suggestedRadiusKm,
      primaryTheme: primaryTheme,
      tags: tags,
    );
  }

  // ---------- SQLite (local) ----------

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'destination_id': destinationId,
      'hotspot_name': hotspotName,
      'latitude': latitude,
      'longitude': longitude,
      'suggested_radius_km': suggestedRadiusKm,
      'primary_theme': primaryTheme,
      'tags': tags.join(','),
    };
  }

  factory DestinationHotspotDto.fromMap(Map<String, dynamic> map) {
    return DestinationHotspotDto(
      id: map['id'] as String,
      destinationId: map['destination_id'] as String,
      hotspotName: map['hotspot_name'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      suggestedRadiusKm:
          ((map['suggested_radius_km'] as num?) ?? 2.0).toDouble(),
      primaryTheme: map['primary_theme'] as String? ?? '',
      tags: _parseTags(map['tags']),
    );
  }

  // ---------- Supabase (remote) ----------

  factory DestinationHotspotDto.fromJson(Map<String, dynamic> json) {
    return DestinationHotspotDto(
      id: json['id'] as String,
      destinationId: json['destination_id'] as String,
      hotspotName: json['hotspot_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      suggestedRadiusKm:
          ((json['suggested_radius_km'] as num?) ?? 2.0).toDouble(),
      primaryTheme: json['primary_theme'] as String? ?? '',
      tags: _parseTags(json['tags']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'destination_id': destinationId,
      'hotspot_name': hotspotName,
      'latitude': latitude,
      'longitude': longitude,
      'suggested_radius_km': suggestedRadiusKm,
      'primary_theme': primaryTheme,
      'tags': tags,
    };
  }

  /// Supabase stores `tags` as TEXT[] which may arrive as a JSON array,
  /// a comma-separated string, or a plain string. Tolerate all three.
  static List<String> _parseTags(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    final text = value.toString().trim();
    if (text.isEmpty || text == '{}') return const [];
    return text
        .replaceAll('{', '')
        .replaceAll('}', '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
