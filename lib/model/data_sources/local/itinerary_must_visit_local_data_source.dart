import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/itinerary_must_visit_dto.dart';
import '../../entities/itinerary_must_visit.dart';

class ItineraryMustVisitLocalSource {
  final LocalDatabaseService _local;

  ItineraryMustVisitLocalSource({LocalDatabaseService? local})
      : _local = local ?? LocalDatabaseService();

  Future<Database> get _db => _local.database;

  Future<List<ItineraryMustVisit>> getForItinerary(String itineraryId) async {
    final db = await _db;
    final result = await db.query(
      'itinerary_must_visits',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
      orderBy: 'must_visit_id ASC',
    );
    return result
        .map((map) => ItineraryMustVisitDTO.fromMap(map).toEntity())
        .toList();
  }

  Future<void> insert(ItineraryMustVisit mustVisit) async {
    final db = await _db;
    final dto = ItineraryMustVisitDTO.fromEntity(mustVisit);
    await db.insert(
      'itinerary_must_visits',
      dto.toMapForLocal(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertAll(List<ItineraryMustVisit> items) async {
    final db = await _db;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        'itinerary_must_visits',
        ItineraryMustVisitDTO.fromEntity(item).toMapForLocal(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit();
  }

  Future<void> delete(int mustVisitId) async {
    final db = await _db;
    await db.delete(
      'itinerary_must_visits',
      where: 'must_visit_id = ?',
      whereArgs: [mustVisitId],
    );
  }

  Future<void> deleteForItinerary(String itineraryId) async {
    final db = await _db;
    await db.delete(
      'itinerary_must_visits',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
    );
  }

  Future<void> clearForItinerary(String itineraryId) async {
    await deleteForItinerary(itineraryId);
  }
}