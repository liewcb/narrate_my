import '../../entities/itinerary_stop.dart';

/// Contract for itinerary stop data access.
abstract class ItineraryStopRepository {
  /// Fetch all stops for a given itinerary, ordered by day and stop order.
  Future<List<ItineraryStop>> getStopsForItinerary(String itineraryId);

  /// Add a new stop (saves to local and optionally remote).
  Future<ItineraryStop> addStop(ItineraryStop stop);

  /// Update an existing stop.
  Future<ItineraryStop> updateStop(ItineraryStop stop);

  /// Delete a stop by its ID.
  Future<void> deleteStop(int stopId);

  /// Save a list of stops (e.g., after reordering) – convenience method.
  Future<void> saveStops(List<ItineraryStop> stops);

  /// Replace all stops for a single day atomically (local batch):
  /// deletes the existing day's stops and inserts [newStops] in one
  /// operation, protecting against partial updates. Remote is best-effort.
  Future<void> replaceDayStops({
    required String itineraryId,
    required int dayIndex,
    required List<ItineraryStop> newStops,
  });
}