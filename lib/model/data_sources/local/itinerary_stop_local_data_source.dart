import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/itinerary_stop_dto.dart';
import '../../entities/itinerary_stop.dart';

class ItineraryStopLocalSource {
  final LocalDatabaseService _local;

  ItineraryStopLocalSource({LocalDatabaseService? local})
      : _local = local ?? LocalDatabaseService();

  Future<Database> get _db => _local.database;

  Future<List<ItineraryStop>> getForItinerary(String itineraryId) async {
    final db = await _db;
    final result = await db.query(
      'itinerary_stops',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
      orderBy: 'day_index ASC, stop_order ASC',
    );
    return result.map((map) => ItineraryStopDTO.fromMap(map).toEntity()).toList();
  }

  Future<int> insert(ItineraryStop stop) async {
    final db = await _db;
    final dto = ItineraryStopDTO.fromEntity(stop);
    final map = dto.toMap()..remove('stop_id');
    final id = await db.insert(
      'itinerary_stops',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<void> update(ItineraryStop stop) async {
    final db = await _db;
    await db.update(
      'itinerary_stops',
      ItineraryStopDTO.fromEntity(stop).toMap(),
      where: 'stop_id = ?',
      whereArgs: [stop.stopId],
    );
  }

  Future<void> delete(int stopId) async {
    final db = await _db;
    await db.delete(
      'itinerary_stops',
      where: 'stop_id = ?',
      whereArgs: [stopId],
    );
  }

  Future<void> clearForItinerary(String itineraryId) async {
    final db = await _db;
    await db.delete(
      'itinerary_stops',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
    );
  }

  Future<void> deleteForDay(String itineraryId, int dayIndex) async {
    final db = await _db;
    await db.delete(
      'itinerary_stops',
      where: 'itinerary_id = ? AND day_index = ?',
      whereArgs: [itineraryId, dayIndex],
    );
  }

  Future<void> insertAll(List<ItineraryStop> stops) async {
    final db = await _db;
    final batch = db.batch();
    for (final stop in stops) {
      final dto = ItineraryStopDTO.fromEntity(stop);
      final map = dto.toMap()..remove('stop_id');
      batch.insert('itinerary_stops', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit();
  }
}