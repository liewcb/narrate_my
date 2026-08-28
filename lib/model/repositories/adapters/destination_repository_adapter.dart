import '../../data_sources/local/destination_local_data_source.dart';
import '../../data_sources/remote/destination_remote_data_source.dart';
import '../../dto/destination_dto.dart';
import '../../entities/destination.dart';
import '../interfaces/destination_repository.dart';

class DestinationRepositoryImpl implements DestinationRepository {
  final DestinationLocalSource _local;
  final DestinationRemoteSource _remote;

  DestinationRepositoryImpl({
    DestinationLocalSource? local,
    DestinationRemoteSource? remote,
  })  : _local = local ?? DestinationLocalSource(),
        _remote = remote ?? DestinationRemoteSource();

  // ─── Public API ──────────────────────────────────────────────

  @override
  Future<List<Destination>> getAllDestinations() async {
    print('🔄 getAllDestinations() called');

    // 1. Try remote first
    try {
      print('🌐 Fetching from remote...');
      final remoteDtos = await _remote.fetchAll();
      print('🌐 Remote returned ${remoteDtos.length} items');

      if (remoteDtos.isNotEmpty) {
        await _local.insertDtos(remoteDtos);
        print('✅ Cached ${remoteDtos.length} items locally');
        return remoteDtos.map((dto) => dto.toDomain()).toList();
      } else {
        print('⚠️ Remote returned empty – falling back to local cache');
      }
    } catch (e) {
      print('❌ Remote fetch failed: $e – falling back to local cache');
    }

    // 2. Fallback: local cache
    print('📦 Fetching from local cache...');
    final localDtos = await _local.getAll();
    print('📦 Local cache has ${localDtos.length} items');

    if (localDtos.isNotEmpty) {
      print('✅ Returning ${localDtos.length} from local cache');
      return localDtos.map((dto) => dto.toDomain()).toList();
    }

    print('⚠️ No destinations available (remote and local empty)');
    return [];
  }

  @override
  Future<Destination?> getDestinationById(String id) async {
    final local = await _local.getById(id);
    if (local != null) return local.toDomain();

    final remote = await _remote.fetchById(id);
    if (remote != null) {
      await _local.insertDto(remote);
    }
    return remote?.toDomain();
  }

  @override
  Future<List<Destination>> searchDestinations(String query) async {
    // Local-only search (fast)
    final localDtos = await _local.getAll();
    final filtered = localDtos.where((dto) =>
        dto.destinationName.toLowerCase().contains(query.toLowerCase()));
    return filtered.map((dto) => dto.toDomain()).toList();
  }

  @override
  Future<List<Destination>> getDestinationsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    final localList = await _local.getByIds(ids);
    final foundIds = localList.map((d) => d.destinationId).toSet();
    final missingIds = ids.where((id) => !foundIds.contains(id)).toList();

    if (missingIds.isEmpty) {
      return localList.map((dto) => dto.toDomain()).toList();
    }

    final remoteDtos = await _remote.fetchByIds(missingIds);
    if (remoteDtos.isNotEmpty) {
      for (final dto in remoteDtos) {
        await _local.insertDto(dto);
      }
      final allDtos = [...localList, ...remoteDtos];
      return allDtos.map((dto) => dto.toDomain()).toList();
    }
    return localList.map((dto) => dto.toDomain()).toList();
  }

  @override
  Future<List<Destination>> getPopularDestinations({int limit = 6}) async {
    // We can fetch all and take top N by name (or add a popularity field later)
    final all = await getAllDestinations();
    return all.take(limit).toList();
  }

  @override
  Future<bool> exists(String id) async {
    final local = await _local.getById(id);
    if (local != null) return true;

    final remote = await _remote.fetchById(id);
    if (remote != null) {
      await _local.insertDto(remote);
      return true;
    }
    return false;
  }

  @override
  Future<int> count() async {
    final all = await getAllDestinations();
    return all.length;
  }

  @override
  Future<void> refreshDestinations() async {
    final remoteDtos = await _remote.fetchAll();
    if (remoteDtos.isNotEmpty) {
      await _local.deleteAll();
      await _local.insertDtos(remoteDtos);
    }
  }
}