class ItineraryDestination {
  final String itineraryId;
  final String destinationId;   // references destinations(destination_id)
  final int allocatedDays;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ItineraryDestination({
    required this.itineraryId,
    required this.destinationId,
    required this.allocatedDays,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
    itineraryId,
    destinationId,
    allocatedDays,
    createdAt,
    updatedAt,
  ];
}