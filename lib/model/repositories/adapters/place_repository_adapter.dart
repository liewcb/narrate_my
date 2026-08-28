// lib/data/repositories/place_repository_adapter.dart
import 'package:sqflite/sqflite.dart';
import '../../../core/services/database_manager.dart';
import '../../../core/services/local_database_service.dart';
import '../../../core/services/remote_database_service.dart';
import '../../dto/place_dto.dart';
import '../../entities/place.dart';
import '../interfaces/place_repository.dart';

class PlaceRepositoryAdapter implements PlaceRepository {
  final LocalDatabaseService _local;
  final RemoteDatabaseService _remote;

  PlaceRepositoryAdapter({
    LocalDatabaseService? local,
    RemoteDatabaseService? remote,
  })  : _local = local ?? DatabaseManager().local,
        _remote = remote ?? DatabaseManager().remote;

  @override
  Future<void> savePlace(Place place) async {
    final dto = PlaceDto.fromEntity(place);
    final db = await _local.database;
    await db.insert(
      'places',
      dto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Place?> getPlace(String placeId) async {
    final db = await _local.database;
    final result = await db.query(
      'places',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );
    if (result.isEmpty) return null;
    return PlaceDto.fromMap(result.first).toEntity();
  }

  @override
  Future<List<Place>> getAllPlaces() async {
    final db = await _local.database;
    final result = await db.query('places');
    return result.map((map) => PlaceDto.fromMap(map).toEntity()).toList();
  }

  @override
  Future<void> deletePlace(String placeId) async {
    final db = await _local.database;
    await db.delete('places', where: 'place_id = ?', whereArgs: [placeId]);
  }

  @override
  Future<bool> exists(String placeId) async {
    final db = await _local.database;
    final result = await db.query(
      'places',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );
    return result.isNotEmpty;
  }
}