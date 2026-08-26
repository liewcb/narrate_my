import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/itinerary_stop_dto.dart';
import '../../entities/itinerary_stop.dart';
import '../interfaces/itinerary_stop_repository.dart';


class ItineraryStopRepositoryImpl implements ItineraryStopRepository {
  final SupabaseClient _remoteClient;
  final LocalDatabaseService _localDbService;

  ItineraryStopRepositoryImpl({
    SupabaseClient? remoteClient,
    LocalDatabaseService? localDbService,
  })  : _remoteClient = remoteClient ?? Supabase.instance.client,
        _localDbService = localDbService ?? LocalDatabaseService();

  @override
  Future<List<ItineraryStop>> getStopsForItinerary(String itineraryId) async {
    List<Map<String, Object?>>? maps;
    try {
      final db = await _localDbService.database;
      maps = await db.query(
        'itinerary_stops',
        where: 'itinerary_id = ?',
        whereArgs: [itineraryId],
        orderBy: 'day_index ASC, stop_order ASC',
      );
    } catch (e) {
      debugPrint('[StopRepo] Local read failed: $e');
    }

    if (maps != null && maps.isNotEmpty) {
      return maps.map((map) => ItineraryStopDTO.fromMap(map).toEntity()).toList();
    }

    // Fetch from Remote if cache missed
    final response = await _remoteClient
        .from('itinerary_stops')
        .select('*, places(*)')
        .eq('itinerary_id', itineraryId)
        .order('day_index', ascending: true)
        .order('stop_order', ascending: true);

    final stops = (response as List)
        .map((json) => ItineraryStopDTO.fromMap(json).toEntity())
        .toList();

    // Populate local cache (best-effort)
    try {
      final db = await _localDbService.database;
      final batch = db.batch();
      for (final stop in stops) {
        batch.insert(
          'itinerary_stops',
          ItineraryStopDTO.fromEntity(stop).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[StopRepo] Local cache write failed: $e');
    }

    return stops;
  }

  @override
  Future<ItineraryStop> addStop(ItineraryStop stop) async {
    final dto = ItineraryStopDTO.fromEntity(stop);

    // 1. Insert locally first so the stop always exists (offline-first)
    final db = await _localDbService.database;
    final localMap = dto.toMap()..remove('stop_id');
    final localId = await db.insert(
      'itinerary_stops',
      localMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final localStop = stop.copyWith(stopId: localId);

    // 2. Remote insert to generate Postgres auto-increment identity ID (best-effort)
    try {
      final payload = ItineraryStopDTO.fromEntity(localStop).toMap()
        ..remove('stop_id');
      final response = await _remoteClient
          .from('itinerary_stops')
          .insert(payload)
          .select()
          .single();

      final createdStop = ItineraryStopDTO.fromMap(response).toEntity();

      // 3. Update local with final server-generated stop_id
      await db.insert(
        'itinerary_stops',
        ItineraryStopDTO.fromEntity(createdStop).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return createdStop;
    } catch (e) {
      debugPrint('[StopRepo] Remote add failed: $e');
      return localStop;
    }
  }

  @override
  Future<ItineraryStop> updateStop(ItineraryStop stop) async {
    // 1. Update local DB
    final db = await _localDbService.database;
    await db.update(
      'itinerary_stops',
      ItineraryStopDTO.fromEntity(stop).toMap(),
      where: 'stop_id = ?',
      whereArgs: [stop.stopId],
    );

    // 2. Update Remote DB (best-effort)
    try {
      final response = await _remoteClient
          .from('itinerary_stops')
          .update(ItineraryStopDTO.fromEntity(stop).toMap())
          .eq('stop_id', stop.stopId)
          .select()
          .single();

      return ItineraryStopDTO.fromMap(response).toEntity();
    } catch (e) {
      debugPrint('[StopRepo] Remote update failed: $e');
      return stop;
    }
  }

  @override
  Future<void> deleteStop(int stopId) async {
    // 1. Delete locally
    final db = await _localDbService.database;
    await db.delete(
      'itinerary_stops',
      where: 'stop_id = ?',
      whereArgs: [stopId],
    );

    // 2. Delete remotely (best-effort)
    try {
      await _remoteClient
          .from('itinerary_stops')
          .delete()
          .eq('stop_id', stopId);
    } catch (e) {
      debugPrint('[StopRepo] Remote delete failed: $e');
    }
  }

  @override
  Future<void> saveStops(List<ItineraryStop> stops) async {
    for (final stop in stops) {
      if (stop.stopId == 0) {
        await addStop(stop);
      } else {
        await updateStop(stop);
      }
    }
  }
}