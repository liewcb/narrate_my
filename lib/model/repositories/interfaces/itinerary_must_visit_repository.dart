import '../../entities/itinerary_must_visit.dart';

/// Repository for the `itinerary_must_visits` table.
abstract class ItineraryMustVisitRepository {
  Future<List<ItineraryMustVisit>> getMustVisits(String itineraryId);
  Future<ItineraryMustVisit> addMustVisit(ItineraryMustVisit mustVisit);
  Future<void> addMustVisits(List<ItineraryMustVisit> mustVisits);
  Future<void> removeMustVisit(int mustVisitId);
  Future<void> removeMustVisitsForItinerary(String itineraryId);
}
