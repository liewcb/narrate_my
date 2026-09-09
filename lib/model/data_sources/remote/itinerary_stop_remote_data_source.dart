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

    // Ensure destination_id is NEVER null to avoid PostgreSQL not-null constraint violation (code: 23502)
    if (payload['destination_id'] == null || payload['destination_id'].toString().isEmpty) {
      try {
        final existing = await _client
            .from('itinerary_stops')
            .select('destination_id')
            .eq('itinerary_id', stop.itineraryId)
            .not('destination_id', 'is', null)
            .limit(1)
            .maybeSingle();
        if (existing != null && existing['destination_id'] != null) {
          payload['destination_id'] = existing['destination_id'];
        } else {
          final selDest = await _client
              .from('itinerary_selected_destinations')
              .select('destination_id')
              .eq('itinerary_id', stop.itineraryId)
              .limit(1)
              .maybeSingle();
          if (selDest != null && selDest['destination_id'] != null) {
            payload['destination_id'] = selDest['destination_id'];
          } else {
            payload['destination_id'] = 'D002'; // Penang fallback
          }
        }
      } catch (_) {
        payload['destination_id'] = 'D002';
      }
    }

    final response = await _client
        .from('itinerary_stops')
        .insert(payload)
        .select()
        .single();
    return ItineraryStopDTO.fromMap(response as Map<String, dynamic>).toEntity();
  }

  Future<ItineraryStop> update(ItineraryStop stop) async {
    // Use DTO so start_time and end_time are formatted as 'HH:mm:ss' for PostgreSQL TIME column
    final dto = ItineraryStopDTO.fromEntity(stop);
    final data = dto.toMap();

    // Remove the immutable fields so Supabase doesn't crash
    data.remove('stop_id');
    data.remove('created_at');

    final response = await _client
        .from('itinerary_stops')
        .update(data)
        .eq('stop_id', stop.stopId)
        .select()
        .single();

    return ItineraryStopDTO.fromMap(response as Map<String, dynamic>).toEntity();
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