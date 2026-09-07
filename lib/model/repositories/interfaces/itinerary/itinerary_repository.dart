import '../../../entities/itinerary.dart';

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

  /// Recalculates the itinerary's status (UPCOMING / ONGOING / PAST) from the
  /// current calendar date and its start/end dates, and persists it to
  /// Supabase ONLY when the stored status is outdated.
  ///
  /// Always returns an itinerary carrying the freshly computed status so the
  /// UI never trusts a stale stored value. If the write fails, the corrected
  /// status is still returned (kept in memory for the session) and the failure
  /// is logged — it must never crash the caller.
  Future<Itinerary> refreshItineraryStatus(Itinerary itinerary);
}