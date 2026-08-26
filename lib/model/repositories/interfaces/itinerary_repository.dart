import '../../entities/itinerary.dart';

/// Contract for itinerary data access.
abstract class ItineraryRepository {
  // ---------- Local-first (cache) ----------

  /// Fetch all itineraries for a given user – tries local first, then remote.
  Future<List<Itinerary>> getUserItineraries(String userId);

  /// Fetch a single itinerary by its ID – tries local first, then remote.
  Future<Itinerary> getItinerary(String itineraryId);

  // ---------- Remote direct ----------
  Future<List<Itinerary>> fetchUserItinerariesFromRemote(String userId);
  Future<Itinerary> fetchItineraryFromRemote(String itineraryId);

  // ---------- Write operations ----------

  Future<Itinerary> createItinerary(Itinerary itinerary);
  Future<Itinerary> updateItinerary(Itinerary itinerary);
  Future<void> deleteItinerary(String itineraryId);
  Future<void> refreshItineraries(String userId);
}