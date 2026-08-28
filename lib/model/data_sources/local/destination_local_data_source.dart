import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/destination_dto.dart';

class DestinationLocalSource {
  final LocalDatabaseService _local;

  DestinationLocalSource({LocalDatabaseService? local})
      : _local = local ?? LocalDatabaseService();

  Future<Database> get _db => _local.database;

  Future<List<DestinationDto>> getAll() async {
    final db = await _db;
    final result = await db.query('destinations', orderBy: 'destination_name ASC');
    return result.map((map) => DestinationDto.fromMap(map)).toList();
  }

  Future<DestinationDto?> getById(String id) async {
    final db = await _db;
    final result = await db.query(
      'destinations',
      where: 'destination_id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return DestinationDto.fromMap(result.first);
  }

  Future<List<DestinationDto>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await _db;
    final placeholders = ids.map((_) => '?').join(',');
    final result = await db.query(
      'destinations',
      where: 'destination_id IN ($placeholders)',
      whereArgs: ids,
    );
    return result.map((map) => DestinationDto.fromMap(map)).toList();
  }

  Future<void> insertDto(DestinationDto dto) async {
    final db = await _db;
    await db.insert('destinations', dto.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertDtos(List<DestinationDto> dtos) async {
    final db = await _db;
    final batch = db.batch();
    for (final dto in dtos) {
      batch.insert('destinations', dto.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit();
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('destinations');
  }
}