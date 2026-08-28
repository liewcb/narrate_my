import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/destination_dto.dart';

class DestinationRemoteSource {
  final SupabaseClient _client;

  DestinationRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<DestinationDto>> fetchAll() async {
    final data = await _client.from('destinations').select();
    if (data == null) return [];
    final list = data as List<dynamic>;
    return list
        .map((json) => DestinationDto.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<DestinationDto?> fetchById(String id) async {
    final data = await _client
        .from('destinations')
        .select()
        .eq('destination_id', id)
        .maybeSingle();
    if (data == null) return null;
    return DestinationDto.fromJson(data as Map<String, dynamic>);
  }

  Future<List<DestinationDto>> fetchByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final data = await _client
        .from('destinations')
        .select()
        .inFilter('destination_id', ids);
    if (data == null) return [];
    final list = data as List<dynamic>;
    return list
        .map((json) => DestinationDto.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}