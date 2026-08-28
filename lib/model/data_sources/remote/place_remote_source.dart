// lib/data/data_sources/remote/place_remote_source.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/remote_database_service.dart';
import '../../dto/place_dto.dart';
import '../../entities/place.dart';

/// Supabase persistence for the `places` table.
class PlaceRemoteSource {
  final SupabaseClient _client;

  PlaceRemoteSource({SupabaseClient? client})
      : _client = client ?? RemoteDatabaseService().client;

  /// Upsert a place (insert or update by 'id').
  Future<void> upsertPlace(Place place) async {
    final dto = PlaceDto.fromEntity(place);
    await _client.from('places').upsert(
      dto.toJsonForRemote(),
      onConflict: 'id',
    );
  }

  /// (Optional) Search nearby places from Supabase `places` table.
  Future<List<Place>> searchNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required List<String> types,
  }) async {
    // Placeholder: you can implement using bounding box + types filter
    // if your table has lat/lng and types array.
    throw UnimplementedError(
      'searchNearbyPlaces from Supabase not yet implemented. '
          'Use PlacesRemoteDataSource (Google) for nearby search instead.',
    );
  }
}