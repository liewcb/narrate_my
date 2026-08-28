import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/itinerary_selected_destination_dto.dart';

class ItinerarySelectedDestinationRemoteSource {
  final SupabaseClient _client;

  ItinerarySelectedDestinationRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<ItinerarySelectedDestinationDTO>> fetchForItinerary(
      String itineraryId,
      ) async {
    final response = await _client
        .from('itinerary_selected_destinations')
        .select('*, destinations(*)')
        .eq('itinerary_id', itineraryId);
    return (response as List)
        .map((json) => ItinerarySelectedDestinationDTO.fromMap(json))
        .toList();
  }

  Future<void> insert(ItinerarySelectedDestinationDTO dto) async {
    await _client
        .from('itinerary_selected_destinations')
        .insert(dto.toMap());
  }

  Future<void> updateAllocatedDays(
      String itineraryId,
      String destinationId,
      int allocatedDays,
      ) async {
    await _client
        .from('itinerary_selected_destinations')
        .update({
      'allocated_days': allocatedDays,
      'updated_at': DateTime.now().toIso8601String(),
    })
        .match({
      'itinerary_id': itineraryId,
      'destination_id': destinationId,
    });
  }

  Future<void> delete(String itineraryId, String destinationId) async {
    await _client
        .from('itinerary_selected_destinations')
        .delete()
        .match({
      'itinerary_id': itineraryId,
      'destination_id': destinationId,
    });
  }

  Future<void> deleteForItinerary(String itineraryId) async {
    await _client
        .from('itinerary_selected_destinations')
        .delete()
        .eq('itinerary_id', itineraryId);
  }
}