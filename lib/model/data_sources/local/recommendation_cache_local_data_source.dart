import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/services/database_manager.dart';
import '../../entities/recommendation.dart';

class RecommendationCacheEntry {
  final List<Recommendation> recommendations;
  final DateTime createdAt;
  final DateTime expiresAt;

  const RecommendationCacheEntry({
    required this.recommendations,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isFresh => expiresAt.isAfter(DateTime.now().toUtc());
}

/// Persistent, recommendation-only cache stored in the app's central SQLite
/// database. The table is created lazily so this feature does not change the
/// schema or migration code owned by the itinerary module.
class RecommendationCacheLocalDataSource {
  static const _table = 'nearby_recommendation_cache';
  static const _staleRetention = Duration(days: 7);

  final Future<Database> Function() _databaseProvider;
  Future<void>? _tableReady;

  RecommendationCacheLocalDataSource({
    Future<Database> Function()? databaseProvider,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseManager().local.database);

  Future<RecommendationCacheEntry?> read(String cacheKey) async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    try {
      final row = rows.single;
      final decoded = jsonDecode(row['recommendations_json'] as String);
      if (decoded is! List) return null;

      final recommendations = decoded
          .whereType<Map>()
          .map(
            (item) => Recommendation.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.placeId.isNotEmpty)
          .toList(growable: false);
      if (recommendations.isEmpty) return null;

      return RecommendationCacheEntry(
        recommendations: recommendations,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at_ms'] as int,
          isUtc: true,
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          row['expires_at_ms'] as int,
          isUtc: true,
        ),
      );
    } catch (_) {
      await db.delete(_table, where: 'cache_key = ?', whereArgs: [cacheKey]);
      return null;
    }
  }

  Future<void> write({
    required String cacheKey,
    required List<Recommendation> recommendations,
    Duration timeToLive = const Duration(hours: 24),
  }) async {
    if (recommendations.isEmpty) return;

    final db = await _database();
    final now = DateTime.now().toUtc();
    await db.insert(_table, {
      'cache_key': cacheKey,
      'recommendations_json': jsonEncode(
        recommendations.map((item) => item.toJson()).toList(),
      ),
      'created_at_ms': now.millisecondsSinceEpoch,
      'expires_at_ms': now.add(timeToLive).millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final staleBefore = now.subtract(_staleRetention).millisecondsSinceEpoch;
    await db.delete(
      _table,
      where: 'created_at_ms < ?',
      whereArgs: [staleBefore],
    );
  }

  Future<Database> _database() async {
    final db = await _databaseProvider();
    _tableReady ??= db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        cache_key TEXT PRIMARY KEY,
        recommendations_json TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL
      )
    ''');
    await _tableReady;
    return db;
  }
}
