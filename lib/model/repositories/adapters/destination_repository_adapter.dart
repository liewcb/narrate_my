import 'package:sqflite/sqflite.dart';
import '../../../core/services/database_manager.dart';
import '../../dto/destination_dto.dart';
import '../../entities/destination.dart';
import '../interfaces/destination_repository.dart';

class DestinationRepositoryImpl implements DestinationRepository {
  final DatabaseManager _db = DatabaseManager();

  // ─── Public API ──────────────────────────────────────────────

  @override
  Future<List<Destination>> getAllDestinations() async {
    print('🔄 getAllDestinations() called');

    final localDtos = await _getAllFromLocal();
    print('📦 Local cache has ${localDtos.length} items');

    if (localDtos.isNotEmpty) {
      print('✅ Returning ${localDtos.length} from local cache');
      return localDtos.map((dto) => dto.toDomain()).toList();
    }

    print('🌐 Fetching from remote...');
    final remoteDtos = await _fetchAllFromRemote();
    print('🌐 Remote returned ${remoteDtos.length} items');

    if (remoteDtos.isNotEmpty) {
      await _cacheDtos(remoteDtos);
      print('✅ Cached ${remoteDtos.length} items locally');
    } else {
      print('⚠️ Remote returned empty!');
    }

    return remoteDtos.map((dto) => dto.toDomain()).toList();
  }

  @override
  Future<Destination?> getDestinationById(String id) async {
    final local = await _getByIdFromLocal(id);
    if (local != null) return local.toDomain();

    final remote = await _fetchByIdFromRemote(id);
    if (remote != null) {
      await _cacheDto(remote);
    }
    return remote?.toDomain();
  }

  @override
  Future<List<Destination>> searchDestinations(String query) async {
    final db = await _db.local.database;
    final result = await db.query(
      'destinations',
      where: 'destination_name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'destination_name ASC',
    );
    return result.map((map) => DestinationDto.fromMap(map).toDomain()).toList();
  }

  @override
  Future<List<Destination>> getDestinationsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    final localList = await _getByIdsFromLocal(ids);
    final foundIds = localList.map((d) => d.destinationId).toSet();
    final missingIds = ids.where((id) => !foundIds.contains(id)).toList();

    if (missingIds.isEmpty) {
      return localList.map((dto) => dto.toDomain()).toList();
    }

    final remoteDtos = await _fetchByIdsFromRemote(missingIds);
    if (remoteDtos.isNotEmpty) {
      for (final dto in remoteDtos) {
        await _cacheDto(dto);
      }
      final allDtos = [...localList, ...remoteDtos];
      return allDtos.map((dto) => dto.toDomain()).toList();
    }
    return localList.map((dto) => dto.toDomain()).toList();
  }

  @override
  Future<List<Destination>> getPopularDestinations({int limit = 6}) async {
    final db = await _db.local.database;
    final result = await db.query(
      'destinations',
      orderBy: 'destination_name ASC',
      limit: limit,
    );
    return result.map((map) => DestinationDto.fromMap(map).toDomain()).toList();
  }

  @override
  Future<bool> exists(String id) async {
    final db = await _db.local.database;
    final result = await db.query(
      'destinations',
      where: 'destination_id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty;
  }

  @override
  Future<int> count() async {
    final db = await _db.local.database;
    final result = await db.query('destinations');
    return result.length;
  }

  @override
  Future<void> refreshDestinations() async {
    final remoteDtos = await _fetchAllFromRemote();
    if (remoteDtos.isNotEmpty) {
      final db = await _db.local.database;
      await db.delete('destinations');
      await _cacheDtos(remoteDtos);
    }
  }

  // ─── Private Local Helpers ──────────────────────────────────

  Future<List<DestinationDto>> _getAllFromLocal() async {
    final db = await _db.local.database;
    final result = await db.query(
      'destinations',
      orderBy: 'destination_name ASC',
    );
    return result.map((map) => DestinationDto.fromMap(map)).toList();
  }

  Future<DestinationDto?> _getByIdFromLocal(String id) async {
    final db = await _db.local.database;
    final result = await db.query(
      'destinations',
      where: 'destination_id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return DestinationDto.fromMap(result.first);
  }

  Future<List<DestinationDto>> _getByIdsFromLocal(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await _db.local.database;
    final placeholders = ids.map((_) => '?').join(',');
    final result = await db.query(
      'destinations',
      where: 'destination_id IN ($placeholders)',
      whereArgs: ids,
    );
    return result.map((map) => DestinationDto.fromMap(map)).toList();
  }

  // ─── Private Remote Helpers ─────────────────────────────────

  Future<List<DestinationDto>> _fetchAllFromRemote() async {
    try {
      print('📡 Making Supabase request to "destinations" table');
      final data = await _db.remote.client.from('destinations').select();
      print('📡 Supabase response: $data');
      if (data == null) {
        print('⚠️ Supabase returned null');
        return [];
      }
      final list = data as List<dynamic>;
      print('✅ Supabase returned ${list.length} rows');
      return list
          .map((json) => DestinationDto.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Supabase error: $e');
      return [];
    }
  }

  Future<DestinationDto?> _fetchByIdFromRemote(String id) async {
    try {
      final data = await _db.remote.client
          .from('destinations')
          .select()
          .eq('destination_id', id)
          .maybeSingle();
      if (data == null) return null;
      return DestinationDto.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      print('Remote fetch by ID failed: $e');
      return null;
    }
  }

  Future<List<DestinationDto>> _fetchByIdsFromRemote(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final data = await _db.remote.client
          .from('destinations')
          .select()
          .inFilter('destination_id', ids);
      if (data == null) return [];
      final list = data as List<dynamic>;
      return list
          .map((json) => DestinationDto.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Remote batch fetch failed: $e');
      return [];
    }
  }

  // ─── Cache Helpers ──────────────────────────────────────────

  Future<void> _cacheDto(DestinationDto dto) async {
    final db = await _db.local.database;
    await db.insert(
      'destinations',
      dto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _cacheDtos(List<DestinationDto> dtos) async {
    final db = await _db.local.database;
    final batch = db.batch();
    for (final dto in dtos) {
      batch.insert(
        'destinations',
        dto.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit();
  }
}