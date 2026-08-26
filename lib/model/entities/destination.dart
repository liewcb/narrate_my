
class Destination {
  final String destinationId;
  final String destinationName;
  final String imageUrl;
  final double? latitude;
  final double? longitude;

  const Destination({
    required this.destinationId,
    required this.destinationName,
    required this.imageUrl,
    this.latitude,
    this.longitude,
  });

  // ── Convenience Getters ──
  String get id => destinationId;
  String get name => destinationName;

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

  Map<String, dynamic> toMap() {
    return {
      'destination_id': destinationId,
      'destination_name': destinationName,
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

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