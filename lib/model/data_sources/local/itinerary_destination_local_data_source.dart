import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/itinerary_destination_dto.dart';
import '../../entities/itinerary_destination.dart';

class ItineraryDestinationLocalSource {
  final LocalDatabaseService _local;

  ItineraryDestinationLocalSource({LocalDatabaseService? local})
      : _local = local ?? LocalDatabaseService();

  Future<Database> get _db => _local.database;

  Future<List<ItineraryDestination>> getForItinerary(String itineraryId) async {
    final db = await _db;
    final result = await db.query(
      'itinerary_selected_destinations',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
    );
    return result
        .map((map) => ItineraryDestinationDTO.fromMap(map).toEntity())
        .toList();
  }

  Future<void> insert(ItineraryDestination destination) async {
    final db = await _db;
    await db.insert(
      'itinerary_selected_destinations',
      ItineraryDestinationDTO.fromEntity(destination).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertAll(List<ItineraryDestination> destinations) async {
    final db = await _db;
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

  Future<void> update(ItineraryDestination destination) async {
    final db = await _db;
    await db.update(
      'itinerary_selected_destinations',
      ItineraryDestinationDTO.fromEntity(destination).toMap(),
      where: 'itinerary_id = ? AND destination_id = ?',
      whereArgs: [destination.itineraryId, destination.destinationId],
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
}