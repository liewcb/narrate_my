import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/place_dto.dart';
import '../../entities/place.dart';

class PlaceLocalSource {
  final LocalDatabaseService _local;

  PlaceLocalSource({LocalDatabaseService? local})
      : _local = local ?? LocalDatabaseService();

  Future<Database> get _db => _local.database;

  Future<void> savePlace(Place place) async {
    final db = await _db;
    await db.insert(
      'places',
      PlaceDto.fromEntity(place).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Place?> getPlace(String placeId) async {
    final db = await _db;
    final result = await db.query(
      'places',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );
    if (result.isEmpty) return null;
    return PlaceDto.fromMap(result.first).toEntity();
  }

  Future<List<Place>> getAllPlaces() async {
    final db = await _db;
    final result = await db.query('places');
    return result.map((map) => PlaceDto.fromMap(map).toEntity()).toList();
  }

  Future<void> deletePlace(String placeId) async {
    final db = await _db;
    await db.delete('places', where: 'place_id = ?', whereArgs: [placeId]);
  }

  Future<bool> exists(String placeId) async {
    final db = await _db;
    final result = await db.query(
      'places',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );
    return result.isNotEmpty;
  }
}