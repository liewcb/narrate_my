class ItineraryDestination {
  final String itineraryId;
  final String destinationId;
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
}