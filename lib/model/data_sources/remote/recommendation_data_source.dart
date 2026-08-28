import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_manager.dart';
import '../../dto/recommendation_dto.dart';

class RecommendationRemoteDataSource {
  final SupabaseClient _supabase;

  RecommendationRemoteDataSource({SupabaseClient? client})
    : _supabase = client ?? DatabaseManager().remote.client;

  Future<List<RecommendationDto>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'recommend-nearby',
        body: {'latitude': latitude, 'longitude': longitude},
      );

      if (response.status < 200 || response.status >= 300) {
        throw Exception(
          'Failed to get recommendations. Status: ${response.status}',
        );
      }

      final data = response.data;

      if (data == null) {
        return [];
      }

      final recommendations = data is Map ? data['recommendations'] : data;

      if (recommendations == null || recommendations is! List) {
        return [];
      }

      final result = <RecommendationDto>[];
      for (final item in recommendations) {
        if (item is Map) {
          result.add(
            RecommendationDto.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
      return result;
    } catch (e) {
      throw Exception('Unable to retrieve nearby recommendations: $e');
    }
  }
}
