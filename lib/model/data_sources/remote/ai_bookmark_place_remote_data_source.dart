import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_manager.dart';
import '../../dto/place_dto.dart';
import '../../entities/place.dart';

/// Read-only access to bookmarkable places already stored in Supabase.
///
/// AI chat uses these canonical rows before attempting a Google Places
/// lookup. This makes the bookmark suggestion work in ordinary app launches
/// where a Dart `MAPS_API_KEY` was not supplied with `--dart-define`.
class AiBookmarkPlaceRemoteDataSource {
  AiBookmarkPlaceRemoteDataSource({SupabaseClient? client})
      : _client = client ?? DatabaseManager().remote.client;

  final SupabaseClient _client;

  Future<List<Place>> fetchBookmarkablePlaces() async {
    final rows = await _client
        .from('places')
        .select()
        .order('name', ascending: true)
        .limit(500);

    return rows
        .map(
          (row) => PlaceDto.fromJson(
            Map<String, dynamic>.from(row as Map),
          ).toEntity(),
        )
        .where(
          (place) =>
              place.placeId.trim().isNotEmpty &&
              place.placeName.trim().isNotEmpty &&
              place.placeId.trim() != 'NEW_PLACE_ID',
        )
        .toList(growable: false);
  }
}
