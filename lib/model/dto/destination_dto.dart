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
      imageUrl: (map['image_url'] as String?) ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  // ---------- Supabase (remote) ----------
  //
  // The remote "destinations" table declares its primary-key column as
  // `destination_id`. Older snapshots may use `destinationId` or `id`,
  // so parsing tolerates all three spellings.
  factory DestinationDto.fromJson(Map<String, dynamic> json) {
    final rawId = json['destination_id'] ??
        json['destinationId'] ??
        json['id'];
    return DestinationDto(
      destinationId: rawId?.toString() ?? '',
      destinationName: json['destination_name']?.toString() ?? '',
      imageUrl: (json['image_url'] as String?) ?? '',
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
