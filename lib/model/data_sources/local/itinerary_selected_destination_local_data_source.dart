import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/itinerary_selected_destination_dto.dart';

class ItinerarySelectedDestinationLocalSource {
  final LocalDatabaseService _local;

  ItinerarySelectedDestinationLocalSource({LocalDatabaseService? local})
      : _local = local ?? LocalDatabaseService();

  Future<Database> get _db => _local.database;

  Future<List<ItinerarySelectedDestinationDTO>> getForItinerary(
      String itineraryId,
      ) async {
    final db = await _db;
    final result = await db.query(
      'itinerary_selected_destinations',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
    );
    return result.map((map) => ItinerarySelectedDestinationDTO.fromMap(map)).toList();
  }

  Future<void> insert(ItinerarySelectedDestinationDTO dto) async {
    final db = await _db;
    await db.insert(
      'itinerary_selected_destinations',
      dto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateAllocatedDays(
      String itineraryId,
      String destinationId,
      int allocatedDays,
      ) async {
    final db = await _db;
    await db.update(
      'itinerary_selected_destinations',
      {
        'allocated_days': allocatedDays,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'itinerary_id = ? AND destination_id = ?',
      whereArgs: [itineraryId, destinationId],
    );
  }

  Future<void> delete(String itineraryId, String destinationId) async {
    final db = await _db;
    await db.delete(
      'itinerary_selected_destinations',
      where: 'itinerary_id = ? AND destination_id = ?',
      whereArgs: [itineraryId, destinationId],
    );
  }

  Future<void> deleteForItinerary(String itineraryId) async {
    final db = await _db;
    await db.delete(
      'itinerary_selected_destinations',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
    );
  }

  Future<void> cacheAll(List<ItinerarySelectedDestinationDTO> dtos) async {
    final db = await _db;
    final batch = db.batch();
    for (final dto in dtos) {
      batch.insert(
        'itinerary_selected_destinations',
        dto.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit();
  }
}