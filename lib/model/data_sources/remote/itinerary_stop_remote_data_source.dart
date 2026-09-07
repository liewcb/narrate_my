import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/itinerary_stop_dto.dart';
import '../../entities/itinerary_stop.dart';

class ItineraryStopRemoteSource {
  final SupabaseClient _client;

  ItineraryStopRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<ItineraryStop>> fetchForItinerary(String itineraryId) async {
    final data = await _client
        .from('itinerary_stops')
        .select('*, places(*)')
        .eq('itinerary_id', itineraryId)
        .order('day_index', ascending: true)
        .order('stop_order', ascending: true);
    final list = data as List<dynamic>;
    return list
        .map((json) => ItineraryStopDTO.fromMap(json as Map<String, dynamic>).toEntity())
        .toList();
  }

  Future<ItineraryStop> insert(ItineraryStop stop) async {
    final dto = ItineraryStopDTO.fromEntity(stop);
    final payload = dto.toMap()..remove('stop_id');
    final response = await _client
        .from('itinerary_stops')
        .insert(payload)
        .select()
        .single();
    return ItineraryStopDTO.fromMap(response as Map<String, dynamic>).toEntity();
  }

  Future<ItineraryStop> update(ItineraryStop stop) async {
    // 1. Get the full map (which keeps SQLite happy)
    final data = stop.toMap();

    // 2. Remove the locked fields so Supabase doesn't crash!
    data.remove('stop_id');
    data.remove('created_at');

    // 3. Send the safe data to Supabase
    final response = await _client
        .from('itinerary_stops')
        .update(data)
        .eq('stop_id', stop.stopId)
        .select()
        .single();

    // ✅ FIXED: Route the response through the DTO so times are parsed correctly
    return ItineraryStopDTO.fromMap(response).toEntity();
  }

  Future<void> delete(int stopId) async {
    await _client
        .from('itinerary_stops')
        .delete()
        .eq('stop_id', stopId);
  }

  Future<void> deleteForItinerary(String itineraryId) async {
    await _client
        .from('itinerary_stops')
        .delete()
        .eq('itinerary_id', itineraryId);
  }

  Future<void> deleteForDay(String itineraryId, int dayIndex) async {
    await _client
        .from('itinerary_stops')
        .delete()
        .eq('itinerary_id', itineraryId)
        .eq('day_index', dayIndex);
  }
}