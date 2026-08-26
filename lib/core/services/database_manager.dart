import 'package:narrate_my/core/services/local_database_service.dart';
import 'package:narrate_my/core/services/remote_database_service.dart';

class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  factory DatabaseManager() => _instance;
  DatabaseManager._internal();

  final LocalDatabaseService local = LocalDatabaseService();
  final RemoteDatabaseService remote = RemoteDatabaseService();

  bool _initialized = false;

  /// Initialize both local and remote database services.
  /// Call this once at app startup.
  Future<void> init() async {
    if (_initialized) return;

    // Initialize Supabase Remote
    await remote.init();

    // Warm-up local SQLite DB connection
    await local.database;

    _initialized = true;
  }
}