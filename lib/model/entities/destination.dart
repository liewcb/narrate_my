// lib/domain/entities/destination.dart

/// Domain entity for a travel destination (city/region).
class Destination {
  final String destinationId;   // matches table column "destination_id"
  final String destinationName;            // matches "destination_name"
  final String imageUrl;        // matches "image_url"
  final double? latitude;       // matches "latitude" (nullable for safety)
  final double? longitude;      // matches "longitude"

  const Destination({
    required this.destinationId,
    required this.destinationName,
    required this.imageUrl,
    this.latitude,
    this.longitude,
  });

  Destination copyWith({
    String? destinationId,
    String? name,
    String? imageUrl,
    double? latitude,
    double? longitude,
  }) {
    return Destination(
      destinationId: destinationId ?? this.destinationId,
      destinationName: name ?? this.destinationName,
      imageUrl: imageUrl ?? this.imageUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  /// Convert to a Map using the exact table column names.
  Map<String, dynamic> toMap() {
    return {
      'destination_id': destinationId,
      'destination_name': destinationName,
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// Create from a Map (from SQLite or Supabase).
  factory Destination.fromMap(Map<String, dynamic> map) {
    return Destination(
      destinationId: map['destination_id'] as String,
      destinationName: map['destination_name'] as String,
      imageUrl: map['image_url'] as String,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() =>
      'Destination(destinationId: $destinationId, name: $destinationName)';
}
