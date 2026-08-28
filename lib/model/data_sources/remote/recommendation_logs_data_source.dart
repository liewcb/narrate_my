import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_manager.dart';
import '../../entities/recommendation_logs.dart';

class RecommendationLogRemoteDataSource {
  final SupabaseClient _supabase;

  RecommendationLogRemoteDataSource({SupabaseClient? client})
    : _supabase = client ?? DatabaseManager().remote.client;

  Future<void> saveRecommendationLog(RecommendationLog log) async {
    await _supabase.from('recommendation_logs').insert(log.toJson());
  }
}
