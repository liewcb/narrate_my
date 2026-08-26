

import '../entities/itinerary_destination.dart';

/// Data Transfer Object for the `itinerary_selected_destinations` table.
class ItineraryDestinationDTO {
  final String itineraryId;
  final String destinationId;
  final int allocatedDays;
  final String createdAt;
  final String updatedAt;

  const ItineraryDestinationDTO({
    required this.itineraryId,
    required this.destinationId,
    required this.allocatedDays,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create from Supabase/Postgres map.
  factory ItineraryDestinationDTO.fromMap(Map<String, dynamic> map) {
    return ItineraryDestinationDTO(
      itineraryId: map['itinerary_id'] as String,
      destinationId: map['destination_id'] as String,
      allocatedDays: map['allocated_days'] as int,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  /// Convert to Supabase/Postgres map.
  Map<String, dynamic> toMap() {
    return {
      'itinerary_id': itineraryId,
      'destination_id': destinationId,
      'allocated_days': allocatedDays,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Convert to domain entity.
  ItineraryDestination toEntity() {
    return ItineraryDestination(
      itineraryId: itineraryId,
      destinationId: destinationId,
      allocatedDays: allocatedDays,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  /// Create DTO from domain entity.
  factory ItineraryDestinationDTO.fromEntity(ItineraryDestination entity) {
    return ItineraryDestinationDTO(
      itineraryId: entity.itineraryId,
      destinationId: entity.destinationId,
      allocatedDays: entity.allocatedDays,
      createdAt: entity.createdAt.toIso8601String(),
      updatedAt: entity.updatedAt.toIso8601String(),
    );
  }
}