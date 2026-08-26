import 'package:equatable/equatable.dart';

class ItineraryDestination extends Equatable {
  final String itineraryId;
  final String destinationId;   // references destinations(id)
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