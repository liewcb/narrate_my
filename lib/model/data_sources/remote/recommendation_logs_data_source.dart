import 'package:supabase_flutter/supabase_flutter.dart';

import '../../entities/recommendation_logs.dart';

class RecommendationLogRemoteDataSource {
  final SupabaseClient _supabase;

  RecommendationLogRemoteDataSource(this._supabase);

  Future<void> saveRecommendationLog(
      RecommendationLog log,
      ) async {
    await _supabase
        .from('recommendation_logs')
        .insert(log.toJson());
  }
}