import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/services/local_database_service.dart';
import '../../../data_sources/remote/itinerary_remote_data_source.dart';
import '../../../dto/itinerary_dto.dart';
import '../../../entities/itinerary.dart';
import '../../interfaces/itinerary/itinerary_repository.dart';

class ItineraryRepositoryImpl implements ItineraryRepository {
  final ItineraryRemoteSource _remoteSource;
  final LocalDatabaseService _localDbService;

  ItineraryRepositoryImpl({
    ItineraryRemoteSource? remoteSource,
    LocalDatabaseService? localDbService,
  })  : _remoteSource = remoteSource ?? ItineraryRemoteSource(),
        _localDbService = localDbService ?? LocalDatabaseService();

  // ---------- Remote-First Reads ----------

  @override
  Future<List<Itinerary>> getUserItineraries(String userId) async {
    try {
      final remote = await fetchUserItinerariesFromRemote(userId);
      if (remote.isNotEmpty) return remote;
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote read failed: $e');
    }

    debugPrint('[ItineraryRepo] Attempting local cache fallback');
    try {
      final db = await _localDbService.database;
      final maps = await db.query(
        'itineraries',
        where: 'id = ?',
        whereArgs: [userId],
        orderBy: 'created_at DESC',
      );
      if (maps.isNotEmpty) {
        return maps.map((map) => ItineraryDTO.fromMap(map).toEntity()).toList();
      }
    } catch (e) {
      debugPrint('[ItineraryRepo] Local read failed: $e');
    }

    return const [];
  }

  @override
  Future<Itinerary> getItinerary(String itineraryId) async {
    try {
      return await fetchItineraryFromRemote(itineraryId);
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote read failed: $e');
    }

    debugPrint('[ItineraryRepo] Attempting local cache fallback');
    try {
      final db = await _localDbService.database;
      final maps = await db.query(
        'itineraries',
        where: 'itinerary_id = ?',
        whereArgs: [itineraryId],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return ItineraryDTO.fromMap(maps.first).toEntity();
      }
    } catch (e) {
      debugPrint('[ItineraryRepo] Local read failed: $e');
    }

    throw Exception('Itinerary not found and remote is unavailable.');
  }

  @override
  Future<List<Itinerary>> fetchUserItinerariesFromRemote(String userId) async {
    List<Itinerary> itineraries = [];

    try {
      final response = await _remoteSource.fetchUserItineraries(userId);
      itineraries = response
          .map((json) => ItineraryDTO.fromMap(json).toEntity())
          .toList();
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote fetch failed: $e');
      rethrow;
    }

    // Cache locally
    try {
      final db = await _localDbService.database;
      final batch = db.batch();
      for (final itinerary in itineraries) {
        batch.insert(
          'itineraries',
          ItineraryDTO.fromEntity(itinerary).toMapForLocal(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[ItineraryRepo] Local cache write failed: $e');
    }

    return itineraries;
  }

  @override
  Future<Itinerary> fetchItineraryFromRemote(String itineraryId) async {
    final response = await _remoteSource.fetchItinerary(itineraryId);
    final itinerary = ItineraryDTO.fromMap(response).toEntity();

    try {
      final db = await _localDbService.database;
      await db.insert(
        'itineraries',
        ItineraryDTO.fromEntity(itinerary).toMapForLocal(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[ItineraryRepo] Local cache write failed: $e');
    }

    return itinerary;
  }

  // ---------- Writes (Remote-First, SQLite cache) ----------

  @override
  Future<Itinerary> createItinerary(Itinerary itinerary) async {
    // ✅ Ensure itineraryId is not null or empty – generate one if needed
    final finalItinerary = _ensureItineraryId(itinerary);
    final dto = ItineraryDTO.fromEntity(finalItinerary);

    debugPrint('[ItineraryRepo] Creating itinerary with ID: ${finalItinerary.itineraryId}');

    try {
      final response = await _remoteSource.insert(dto.toMapForRemote());
      final created = ItineraryDTO.fromMap(response).toEntity();

      debugPrint('[ItineraryRepo] Remote insert succeeded: ${created.itineraryId}');

      // Cache locally
      try {
        final db = await _localDbService.database;
        await db.insert(
          'itineraries',
          ItineraryDTO.fromEntity(created).toMapForLocal(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint('[ItineraryRepo] Local cache write failed: $e');
      }

      return created;
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote create failed: $e');
      rethrow;
    }
  }

  @override
  Future<Itinerary> updateItinerary(Itinerary itinerary) async {
    final dto = ItineraryDTO.fromEntity(itinerary);

    late final Itinerary updated;
    try {
      final response = await _remoteSource.update(
        itinerary.itineraryId,
        dto.toMapForRemote(),
      );
      updated = ItineraryDTO.fromMap(response).toEntity();
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote update failed: $e');
      rethrow;
    }

    try {
      final db = await _localDbService.database;
      await db.update(
        'itineraries',
        ItineraryDTO.fromEntity(updated).toMapForLocal(),
        where: 'itinerary_id = ?',
        whereArgs: [itinerary.itineraryId],
      );
    } catch (e) {
      debugPrint('[ItineraryRepo] Local cache update failed: $e');
    }
    return updated;
  }

  @override
  Future<void> deleteItinerary(String itineraryId) async {
    try {
      await _remoteSource.delete(itineraryId);
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote delete failed: $e');
      rethrow;
    }

    try {
      final db = await _localDbService.database;
      await db.delete(
        'itineraries',
        where: 'itinerary_id = ?',
        whereArgs: [itineraryId],
      );
    } catch (e) {
      debugPrint('[ItineraryRepo] Local delete failed: $e');
    }
  }

  @override
  Future<void> refreshItineraries(String userId) async {
    await fetchUserItinerariesFromRemote(userId);
  }

  // ─── Helper: Ensure itineraryId exists ──────────────────────

  Itinerary _ensureItineraryId(Itinerary itinerary) {
    if (itinerary.itineraryId.isNotEmpty) return itinerary;

    // Generate a unique ID: e.g., "itin_20260906_12345"
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = (10000 + (DateTime.now().microsecond % 90000)).toString();
    final newId = 'itin_${timestamp}_$randomSuffix';

    debugPrint('[ItineraryRepo] Generated itineraryId: $newId');

    return itinerary.copyWith(itineraryId: newId);
  }
}