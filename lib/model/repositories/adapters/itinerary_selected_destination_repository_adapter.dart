import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dto/itinerary_selected_destination_dto.dart';
import '../interfaces/itinerary_selected_destination_repository.dart';


class ItinerarySelectedDestinationRepositoryImpl implements ItinerarySelectedDestinationRepository {
  final SupabaseClient _client;

  ItinerarySelectedDestinationRepositoryImpl({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  @override
  Future<List<ItinerarySelectedDestinationDTO>> getSelectedDestinations(String itineraryId) async {
    final response = await _client
        .from('itinerary_selected_destinations')
        .select('*, destinations(*)') // Join with destinations table to get image/name if needed
        .eq('itinerary_id', itineraryId);

    return (response as List)
        .map((json) => ItinerarySelectedDestinationDTO.fromMap(json))
        .toList();
  }

  @override
  Future<void> addSelectedDestination(ItinerarySelectedDestinationDTO destination) async {
    await _client
        .from('itinerary_selected_destinations')
        .insert(destination.toMap());
  }

  @override
  Future<void> updateAllocatedDays(String itineraryId, String destinationId, int allocatedDays) async {
    await _client
        .from('itinerary_selected_destinations')
        .update({'allocated_days': allocatedDays, 'updated_at': DateTime.now().toIso8601String()})
        .match({
      'itinerary_id': itineraryId,
      'destination_id': destinationId,
    });
  }

  @override
  Future<void> removeSelectedDestination(String itineraryId, String destinationId) async {
    await _client
        .from('itinerary_selected_destinations')
        .delete()
        .match({
      'itinerary_id': itineraryId,
      'destination_id': destinationId,
    });
  }
}