// lib/domain/entities/itinerary_selected_destination.dart

class ItinerarySelectedDestination {
  final String itineraryId;
  final String destinationId;    // references destinations.destination_id
  final int allocatedDays;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ItinerarySelectedDestination({
    required this.itineraryId,
    required this.destinationId,
    required this.allocatedDays,
    required this.createdAt,
    required this.updatedAt,
  });

  ItinerarySelectedDestination copyWith({
    String? itineraryId,
    String? destinationId,
    int? allocatedDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ItinerarySelectedDestination(
      itineraryId: itineraryId ?? this.itineraryId,
      destinationId: destinationId ?? this.destinationId,
      allocatedDays: allocatedDays ?? this.allocatedDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}