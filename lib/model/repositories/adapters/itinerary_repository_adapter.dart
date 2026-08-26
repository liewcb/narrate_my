import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/itinerary_dto.dart';
import '../../entities/itinerary.dart';
import '../interfaces/itinerary_repository.dart';

class ItineraryRepositoryImpl implements ItineraryRepository {
  final SupabaseClient _remoteClient;
  final LocalDatabaseService _localDbService;

  ItineraryRepositoryImpl({
    SupabaseClient? remoteClient,
    LocalDatabaseService? localDbService,
  })  : _remoteClient = remoteClient ?? Supabase.instance.client,
        _localDbService = localDbService ?? LocalDatabaseService();

  // ---------- Local-First Reads ----------

  @override
  Future<List<Itinerary>> getUserItineraries(String userId) async {
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
      // Missing/stale table — fall through to the remote source.
      debugPrint('[ItineraryRepo] Local read failed: $e');
    }

    // Fallback to remote fetch if local cache is empty or unavailable
    return await fetchUserItinerariesFromRemote(userId);
  }

  @override
  Future<Itinerary> getItinerary(String itineraryId) async {
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
      // Missing/stale table — fall through to the remote source.
      debugPrint('[ItineraryRepo] Local read failed: $e');
    }

    // Fallback to remote fetch if not found locally
    return await fetchItineraryFromRemote(itineraryId);
  }

  // ---------- Remote Direct Fetching & Sync ----------

  @override
  Future<List<Itinerary>> fetchUserItinerariesFromRemote(String userId) async {
    List<Itinerary> itineraries = [];

    try {
      final response = await _remoteClient
          .from('itineraries')
          .select()
          .eq('id', userId)
          .order('created_at', ascending: false);

      itineraries = (response as List)
          .map((json) => ItineraryDTO.fromMap(json).toEntity())
          .toList();
    } catch (e) {
      // Remote unavailable — fall back to the local cache below.
      debugPrint('[ItineraryRepo] Remote fetch failed: $e');
      return await getUserItineraries(userId);
    }

    // Cache results locally (best-effort — a stale-schema DB must not
    // prevent returning the remote results).
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
    final response = await _remoteClient
        .from('itineraries')
        .select()
        .eq('itinerary_id', itineraryId)
        .single();

    final itinerary = ItineraryDTO.fromMap(response).toEntity();

    // Cache locally (best-effort)
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

  // ---------- Writes (Dual Sync) ----------

  @override
  Future<Itinerary> createItinerary(Itinerary itinerary) async {
    final dto = ItineraryDTO.fromEntity(itinerary);

    // Save locally (source of truth for offline-first UX)
    final db = await _localDbService.database;
    await db.insert(
      'itineraries',
      dto.toMapForLocal(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Sync to Remote (best-effort — local save must never fail the flow)
    try {
      final response = await _remoteClient
          .from('itineraries')
          .insert(dto.toMapForRemote())
          .select()
          .single();
      return ItineraryDTO.fromMap(response).toEntity();
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote create failed: $e');
      return itinerary;
    }
  }

  @override
  Future<Itinerary> updateItinerary(Itinerary itinerary) async {
    final dto = ItineraryDTO.fromEntity(itinerary);

    // Save locally (source of truth)
    final db = await _localDbService.database;
    await db.update(
      'itineraries',
      dto.toMapForLocal(),
      where: 'itinerary_id = ?',
      whereArgs: [itinerary.itineraryId],
    );

    // Sync to Remote (best-effort)
    try {
      final response = await _remoteClient
          .from('itineraries')
          .update(dto.toMapForRemote())
          .eq('itinerary_id', itinerary.itineraryId)
          .select()
          .single();
      return ItineraryDTO.fromMap(response).toEntity();
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote update failed: $e');
      return itinerary;
    }
  }

  @override
  Future<void> deleteItinerary(String itineraryId) async {
    // Delete locally
    final db = await _localDbService.database;
    await db.delete(
      'itineraries',
      where: 'itinerary_id = ?',
      whereArgs: [itineraryId],
    );

    // Delete remotely (best-effort)
    try {
      await _remoteClient
          .from('itineraries')
          .delete()
          .eq('itinerary_id', itineraryId);
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote delete failed: $e');
    }
  }

  @override
  Future<void> refreshItineraries(String userId) async {
    await fetchUserItinerariesFromRemote(userId);
  }
}