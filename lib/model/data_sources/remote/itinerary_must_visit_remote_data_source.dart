import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/itinerary_must_visit_dto.dart';
import '../../entities/itinerary_must_visit.dart';

class ItineraryMustVisitRemoteSource {
  final SupabaseClient _client;

  ItineraryMustVisitRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<ItineraryMustVisit>> fetchForItinerary(String itineraryId) async {
    final data = await _client
        .from('itinerary_must_visits')
        .select()
        .eq('itinerary_id', itineraryId);
    final list = data as List<dynamic>;
    return list
        .map((json) => ItineraryMustVisitDTO.fromMap(json as Map<String, dynamic>).toEntity())
        .toList();
  }

  Future<ItineraryMustVisit> insert(ItineraryMustVisit mustVisit) async {
    final dto = ItineraryMustVisitDTO.fromEntity(mustVisit);
    final response = await _client
        .from('itinerary_must_visits')
        .insert(dto.toJsonForRemote())
        .select()
        .single();
    return ItineraryMustVisitDTO.fromMap(response as Map<String, dynamic>).toEntity();
  }

  Future<void> delete(int mustVisitId) async {
    await _client
        .from('itinerary_must_visits')
        .delete()
        .eq('must_visit_id', mustVisitId);
  }

  Future<void> deleteForItinerary(String itineraryId) async {
    await _client
        .from('itinerary_must_visits')
        .delete()
        .eq('itinerary_id', itineraryId);
  }
}