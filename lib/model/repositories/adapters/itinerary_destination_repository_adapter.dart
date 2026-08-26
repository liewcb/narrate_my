// lib/data/repositories/itinerary_destination_repository_impl.dart
import 'package:sqflite/sqflite.dart';
import '../../../core/services/database_manager.dart';
import '../../../core/services/local_database_service.dart';
import '../../../core/services/remote_database_service.dart';
import '../../dto/itinerary_destination_dto.dart';
import '../../entities/itinerary_destination.dart';
import '../interfaces/itinerary_destination_repository.dart';

/// Implementation of [ItineraryDestinationRepository] with local SQLite cache
/// and remote Supabase source.
class ItineraryDestinationRepositoryImpl implements ItineraryDestinationRepository {
  final LocalDatabaseService _local;
  final RemoteDatabaseService _remote;

  ItineraryDestinationRepositoryImpl({
    LocalDatabaseService? local,
    RemoteDatabaseService? remote,
  })  : _local = local ?? DatabaseManager().local,
        _remote = remote ?? DatabaseManager().remote;

  // ─── Public API ──────────────────────────────────────────────

  @override
  Future<List<ItineraryDestination>> getSelectedDestinations(String itineraryId) async {
    final local = await _getDestinationsFromLocal(itineraryId);
    if (local.isNotEmpty) return local;

    final remote = await _fetchDestinationsFromRemote(itineraryId);
    if (remote.isNotEmpty) {
      await _cacheDestinations(remote);
    }
    return remote;
  }

  @override
  Future<void> addDestination(ItineraryDestination destination) async {
    // Convert entity → Map via DTO
    final map = ItineraryDestinationDTO.fromEntity(destination).toMap();
    await _remote.client
        .from('itinerary_selected_destinations')
        .insert(map);

    // Cache locally
    await _cacheDestination(destination);
  }

  @override
  Future<void> updateDestination(ItineraryDestination destination) async {
    final map = ItineraryDestinationDTO.fromEntity(destination).toMap();
    await _remote.client
        .from('itinerary_selected_destinations')
        .update(map)
        .eq('itinerary_id', destination.itineraryId)
        .eq('destination_id', destination.destinationId);

    // Update local
    await _updateDestinationInLocal(destination);
  }

  @override
  Future<void> removeDestination(String itineraryId, String destinationId) async {
    await _remote.client
        .from('itinerary_selected_destinations')
        .delete()
        .eq('itinerary_id', itineraryId)
        .eq('destination_id', destinationId);

    // Delete from local
    await _deleteDestinationFromLocal(itineraryId, destinationId);
  }

  // ─── Private Local Helpers ──────────────────────────────────

  Future<List<ItineraryDestination>> _getDestinationsFromLocal(String itineraryId) async {
    final db = await _local.database;
    final result = await db.query(
      'itinerary_selected_destinations',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
    );
    return result
        .map((map) => ItineraryDestinationDTO.fromMap(map).toEntity())
        .toList();
  }

  Future<void> _cacheDestination(ItineraryDestination destination) async {
    final db = await _local.database;
    await db.insert(
      'itinerary_selected_destinations',
      ItineraryDestinationDTO.fromEntity(destination).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _cacheDestinations(List<ItineraryDestination> destinations) async {
    final db = await _local.database;
    final batch = db.batch();
    for (final dest in destinations) {
      batch.insert(
        'itinerary_selected_destinations',
        ItineraryDestinationDTO.fromEntity(dest).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit();
  }

  Future<void> _updateDestinationInLocal(ItineraryDestination destination) async {
    final db = await _local.database;
    await db.update(
      'itinerary_selected_destinations',
      ItineraryDestinationDTO.fromEntity(destination).toMap(),
      where: 'itinerary_id = ? AND destination_id = ?',
      whereArgs: [destination.itineraryId, destination.destinationId],
    );
  }

  Future<void> _deleteDestinationFromLocal(String itineraryId, String destinationId) async {
    final db = await _local.database;
    await db.delete(
      'itinerary_selected_destinations',
      where: 'itinerary_id = ? AND destination_id = ?',
      whereArgs: [itineraryId, destinationId],
    );
  }

  // ─── Private Remote Helper ──────────────────────────────────

  Future<List<ItineraryDestination>> _fetchDestinationsFromRemote(String itineraryId) async {
    try {
      final data = await _remote.client
          .from('itinerary_selected_destinations')
          .select()
          .eq('itinerary_id', itineraryId);
      if (data == null) return [];
      final list = data as List<dynamic>;
      return list
          .map((json) => ItineraryDestinationDTO.fromMap(json as Map<String, dynamic>).toEntity())
          .toList();
    } catch (e) {
      print('Remote fetch destinations failed: $e');
      return [];
    }
  }
}