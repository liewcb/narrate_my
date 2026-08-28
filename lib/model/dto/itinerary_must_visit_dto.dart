import '../entities/itinerary_must_visit.dart';

/// Data Transfer Object for the `itinerary_must_visits` table.
class ItineraryMustVisitDTO {
  final int mustVisitId;
  final String itineraryId;
  final String? placeId;
  final String placeName;
  final String? destinationId;
  final String source;
  final bool isVerified;
  final DateTime? createdAt;

  const ItineraryMustVisitDTO({
    required this.mustVisitId,
    required this.itineraryId,
    this.placeId,
    required this.placeName,
    this.destinationId,
    this.source = 'GOOGLE_SEARCH',
    this.isVerified = false,
    this.createdAt,
  });

  /// From Supabase/Postgres map.
  factory ItineraryMustVisitDTO.fromMap(Map<String, dynamic> map) {
    return ItineraryMustVisitDTO(
      mustVisitId: (map['must_visit_id'] as num?)?.toInt() ?? 0,
      itineraryId: map['itinerary_id']?.toString() ?? '',
      placeId: map['place_id']?.toString(),
      placeName: map['place_name']?.toString() ?? '',
      destinationId: map['destination_id']?.toString(),
      source: map['source']?.toString() ?? 'GOOGLE_SEARCH',
      isVerified: map['is_verified'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  /// To Supabase map (remote).
  Map<String, dynamic> toJsonForRemote() {
    return {
      'itinerary_id': itineraryId,
      'place_id': placeId,
      'place_name': placeName,
      'destination_id': destinationId,
      'source': source,
      'is_verified': isVerified,
    };
  }

  /// To local SQLite map.
  Map<String, dynamic> toMapForLocal() {
    return {
      'must_visit_id': mustVisitId,
      'itinerary_id': itineraryId,
      'place_id': placeId,
      'place_name': placeName,
      'destination_id': destinationId,
      'source': source,
      'is_verified': isVerified ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// To domain entity.
  ItineraryMustVisit toEntity() {
    return ItineraryMustVisit(
      mustVisitId: mustVisitId,
      itineraryId: itineraryId,
      placeId: placeId,
      placeName: placeName,
      destinationId: destinationId,
      source: source,
      isVerified: isVerified,
      createdAt: createdAt,
    );
  }

  /// From domain entity.
  factory ItineraryMustVisitDTO.fromEntity(ItineraryMustVisit entity) {
    return ItineraryMustVisitDTO(
      mustVisitId: entity.mustVisitId,
      itineraryId: entity.itineraryId,
      placeId: entity.placeId,
      placeName: entity.placeName,
      destinationId: entity.destinationId,
      source: entity.source,
      isVerified: entity.isVerified,
      createdAt: entity.createdAt,
    );
  }
}
