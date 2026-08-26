import '../../dto/itinerary_selected_destination_dto.dart';

abstract class ItinerarySelectedDestinationRepository {
  /// Fetch all destinations selected for a specific itinerary
  Future<List<ItinerarySelectedDestinationDTO>> getSelectedDestinations(String itineraryId);

  /// Add a new destination to the itinerary
  Future<void> addSelectedDestination(ItinerarySelectedDestinationDTO destination);

  /// Update allocated days for a specific destination
  Future<void> updateAllocatedDays(String itineraryId, String destinationId, int allocatedDays);

  /// Remove a destination from the itinerary
  Future<void> removeSelectedDestination(String itineraryId, String destinationId);
}