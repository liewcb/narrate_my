import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

class RemoteDatabaseService {
  static final RemoteDatabaseService _instance = RemoteDatabaseService._internal();
  factory RemoteDatabaseService() => _instance;
  RemoteDatabaseService._internal();

  late final SupabaseClient _client;
  bool _initialized = false;

  // Must be called once at app startup
  Future<void> init() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    _client = Supabase.instance.client;
    _initialized = true;
  }

  SupabaseClient get client {
    if (!_initialized) {
      throw Exception('RemoteDatabaseService not initialized. Call init() first.');
    }
    return _client;
  }
}