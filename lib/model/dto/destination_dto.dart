import '../entities/destination.dart';

/// Data Transfer Object – used for serialisation to/from local DB and remote API.
class DestinationDto {
  final String destinationId;
  final String destinationName;
  final String imageUrl;
  final double? latitude;
  final double? longitude;

  const DestinationDto({
    required this.destinationId,
    required this.destinationName,
    required this.imageUrl,
    this.latitude,
    this.longitude,
  });

  // ---------- Domain conversion ----------
  Destination toDomain() {
    return Destination(
      destinationId: destinationId,
      destinationName: destinationName,
      imageUrl: imageUrl,
      latitude: latitude,
      longitude: longitude,
    );
  }

  // ---------- SQLite (local) ----------
  Map<String, dynamic> toMap() {
    return {
      'destination_id': destinationId,
      'destination_name': destinationName,
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory DestinationDto.fromMap(Map<String, dynamic> map) {
    return DestinationDto(
      destinationId: map['destination_id'] as String,
      destinationName: map['destination_name'] as String,
      imageUrl: map['image_url'] as String,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  // ---------- Supabase (remote) ----------
  factory DestinationDto.fromJson(Map<String, dynamic> json) {
    return DestinationDto(
      destinationId: json['destination_id'] as String,
      destinationName: json['destination_name'] as String,
      imageUrl: json['image_url'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'destination_id': destinationId,
      'destination_name': destinationName,
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
