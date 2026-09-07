import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/itinerary_dto.dart';

class ItineraryRemoteSource {
  final SupabaseClient _client;

  ItineraryRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> insert(Map<String, dynamic> data) async {
    final response = await _client
        .from('itineraries')
        .insert(data)
        .select()
        .single();
    return response;
  }

  Future<List<Map<String, dynamic>>> fetchUserItineraries(String userId) async {
    final response = await _client
        .from('itineraries')
        .select()
        .eq('id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> fetchItinerary(String itineraryId) async {
    final response = await _client
        .from('itineraries')
        .select()
        .eq('itinerary_id', itineraryId)
        .single();
    return response;
  }

  Future<Map<String, dynamic>> update(String itineraryId, Map<String, dynamic> data) async {
    final response = await _client
        .from('itineraries')
        .update(data)
        .eq('itinerary_id', itineraryId)
        .select()
        .single();
    return response;
  }

  Future<void> delete(String itineraryId) async {
    await _client.from('itineraries').delete().eq('itinerary_id', itineraryId);
  }
}