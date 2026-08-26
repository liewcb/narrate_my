class ItinerarySelectedDestinationDTO {
  final String itineraryId;
  final String destinationId;
  final int allocatedDays;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ItinerarySelectedDestinationDTO({
    required this.itineraryId,
    required this.destinationId,
    required this.allocatedDays,
    this.createdAt,
    this.updatedAt,
  });

  factory ItinerarySelectedDestinationDTO.fromMap(Map<String, dynamic> map) {
    return ItinerarySelectedDestinationDTO(
      itineraryId: map['itinerary_id'] as String,
      destinationId: map['destination_id'] as String,
      allocatedDays: (map['allocated_days'] as num).toInt(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itinerary_id': itineraryId,
      'destination_id': destinationId,
      'allocated_days': allocatedDays,
      // Let the database handle created_at and updated_at via defaults/triggers
    };
  }
}