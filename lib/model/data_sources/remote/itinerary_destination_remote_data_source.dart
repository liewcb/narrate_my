import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/itinerary_destination_dto.dart';
import '../../entities/itinerary_destination.dart';

class ItineraryDestinationRemoteSource {
  final SupabaseClient _client;

  ItineraryDestinationRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<ItineraryDestination>> fetchForItinerary(String itineraryId) async {
    final data = await _client
        .from('itinerary_selected_destinations')
        .select()
        .eq('itinerary_id', itineraryId);
    if (data == null) return [];
    final list = data as List<dynamic>;
    return list
        .map((json) => ItineraryDestinationDTO.fromMap(json as Map<String, dynamic>).toEntity())
        .toList();
  }

  Future<void> insert(ItineraryDestination destination) async {
    final dto = ItineraryDestinationDTO.fromEntity(destination);
    await _client
        .from('itinerary_selected_destinations')
        .insert(dto.toMap());
  }

  Future<void> update(ItineraryDestination destination) async {
    final dto = ItineraryDestinationDTO.fromEntity(destination);
    await _client
        .from('itinerary_selected_destinations')
        .update(dto.toMap())
        .eq('itinerary_id', destination.itineraryId)
        .eq('destination_id', destination.destinationId);
  }

  Future<void> delete(String itineraryId, String destinationId) async {
    await _client
        .from('itinerary_selected_destinations')
        .delete()
        .eq('itinerary_id', itineraryId)
        .eq('destination_id', destinationId);
  }

  Future<void> deleteForItinerary(String itineraryId) async {
    await _client
        .from('itinerary_selected_destinations')
        .delete()
        .eq('itinerary_id', itineraryId);
  }
}