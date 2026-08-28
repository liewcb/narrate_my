import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/destination_hotspot_dto.dart';

class DestinationHotspotRemoteSource {
  final SupabaseClient _client;

  DestinationHotspotRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<DestinationHotspotDto>> fetchForDestination(
      String destinationId,
      ) async {
    final data = await _client
        .from('destination_hotspots')
        .select()
        .eq('destination_id', destinationId);
    if (data == null) return [];
    final list = data as List<dynamic>;
    return list
        .map((json) =>
        DestinationHotspotDto.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}