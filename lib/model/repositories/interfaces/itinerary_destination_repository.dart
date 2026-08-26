

import '../../entities/itinerary_destination.dart';

abstract class ItineraryDestinationRepository {
  Future<List<ItineraryDestination>> getSelectedDestinations(String itineraryId);
  Future<void> addDestination(ItineraryDestination destination);
  Future<void> updateDestination(ItineraryDestination destination);
  Future<void> removeDestination(String itineraryId, String destinationId);
}