// lib/data/data_sources/local/place_local_source.dart

import 'package:sqflite/sqflite.dart';

import '../../../core/services/local_database_service.dart';
import '../../dto/place_dto.dart';
import '../../entities/place.dart';

class PlaceLocalSource {
  final LocalDatabaseService _local;

  PlaceLocalSource({
    LocalDatabaseService? local,
  }) : _local = local ?? LocalDatabaseService();

  // ============================================================
  // DATABASE
  // ============================================================

  Future<Database> get _db =>
      _local.database;

  // ============================================================
  // SAVE PLACE
  // ============================================================

  Future<void> savePlace(
      Place place,
      ) async {
    final db = await _db;

    await db.insert(
      'places',
      PlaceDto
          .fromEntity(place)
          .toMap(),
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // GET PLACE BY GOOGLE PLACE ID
  // ============================================================

  Future<Place?> getPlace(
      String placeId,
      ) async {
    final db = await _db;

    final result = await db.query(
      'places',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );

    if (result.isEmpty) {
      return null;
    }

    return PlaceDto
        .fromMap(result.first)
        .toEntity();
  }

  // ============================================================
  // GET PLACE BY DATABASE ID
  // ============================================================

  Future<Place?> getPlaceById(
      String id,
      ) async {
    final db = await _db;

    final result = await db.query(
      'places',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) {
      return null;
    }

    return PlaceDto
        .fromMap(result.first)
        .toEntity();
  }

  // ============================================================
  // GET ALL PLACES
  // ============================================================

  Future<List<Place>> getAllPlaces() async {
    final db = await _db;

    final result = await db.query(
      'places',
    );

    return result
        .map(
          (map) => PlaceDto
          .fromMap(map)
          .toEntity(),
    )
        .toList();
  }

  // ============================================================
  // DELETE PLACE BY GOOGLE PLACE ID
  // ============================================================

  Future<void> deletePlace(
      String placeId,
      ) async {
    final db = await _db;

    await db.delete(
      'places',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );
  }

  // ============================================================
  // DELETE PLACE BY DATABASE ID
  // ============================================================

  Future<void> deletePlaceById(
      String id,
      ) async {
    final db = await _db;

    await db.delete(
      'places',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // CHECK PLACE EXISTS
  // ============================================================

  Future<bool> exists(
      String placeId,
      ) async {
    final db = await _db;

    final result = await db.query(
      'places',
      where: 'place_id = ?',
      whereArgs: [placeId],
    );

    return result.isNotEmpty;
  }
}