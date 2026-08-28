import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/destination_hotspot_dto.dart';

class DestinationHotspotLocalSource {
  final LocalDatabaseService _local;

  DestinationHotspotLocalSource({LocalDatabaseService? local})
      : _local = local ?? LocalDatabaseService();

  Future<Database> get _db => _local.database;

  Future<List<DestinationHotspotDto>> getForDestination(
      String destinationId,
      ) async {
    final db = await _db;
    final result = await db.query(
      'destination_hotspots',
      where: 'destination_id = ?',
      whereArgs: [destinationId],
    );
    return result.map((map) => DestinationHotspotDto.fromMap(map)).toList();
  }

  Future<DestinationHotspotDto?> getById(String id) async {
    final db = await _db;
    final result = await db.query(
      'destination_hotspots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return DestinationHotspotDto.fromMap(result.first);
  }

  Future<void> insertDtos(List<DestinationHotspotDto> dtos) async {
    final db = await _db;
    final batch = db.batch();
    for (final dto in dtos) {
      batch.insert(
        'destination_hotspots',
        dto.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit();
  }

  Future<void> deleteForDestination(String destinationId) async {
    final db = await _db;
    await db.delete(
      'destination_hotspots',
      where: 'destination_id = ?',
      whereArgs: [destinationId],
    );
  }
}