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

  // ---------- Remote-First Reads (Supabase is the source of truth) ----------

  @override
  Future<List<Itinerary>> getUserItineraries(String userId) async {
    // 1. Remote first
    try {
      final remote = await fetchUserItinerariesFromRemote(userId);
      if (remote.isNotEmpty) return remote;
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote read failed: $e');
    }

    // 2. Local cache fallback (offline)
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
    // 1. Remote first
    try {
      return await fetchItineraryFromRemote(itineraryId);
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote read failed: $e');
    }

    // 2. Local cache fallback (offline)
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
      // Remote unavailable — rethrow so the caller decides the fallback.
      debugPrint('[ItineraryRepo] Remote fetch failed: $e');
      rethrow;
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

  // ---------- Writes (Remote-First, SQLite cache) ----------

  @override
  Future<Itinerary> createItinerary(Itinerary itinerary) async {
    final dto = ItineraryDTO.fromEntity(itinerary);

    // Save to Remote first (source of truth)
    try {
      final response = await _remoteClient
          .from('itineraries')
          .insert(dto.toMapForRemote())
          .select()
          .single();
      final created = ItineraryDTO.fromMap(response).toEntity();

      // Remote success → write-through to the local cache (best-effort).
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

    // Save to Remote first (source of truth). On failure, STOP — do not
    // touch the local cache so the caller can surface the error.
    late final Itinerary updated;
    try {
      final response = await _remoteClient
          .from('itineraries')
          .update(dto.toMapForRemote())
          .eq('itinerary_id', itinerary.itineraryId)
          .select()
          .single();
      updated = ItineraryDTO.fromMap(response).toEntity();
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote update failed: $e');
      rethrow;
    }

    // Remote success → write-through to the local cache (best-effort).
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
    // 1. Delete remotely first (source of truth)
    try {
      await _remoteClient
          .from('itineraries')
          .delete()
          .eq('itinerary_id', itineraryId);
    } catch (e) {
      debugPrint('[ItineraryRepo] Remote delete failed: $e');
      rethrow;
    }

    // 2. Delete locally on remote success (best-effort)
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
}