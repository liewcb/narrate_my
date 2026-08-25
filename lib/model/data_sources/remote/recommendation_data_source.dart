import 'package:supabase_flutter/supabase_flutter.dart';

import '../../entities/recommendation.dart';

class RecommendationRemoteDataSource {
  final SupabaseClient _supabase;

  RecommendationRemoteDataSource(this._supabase);

  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'recommend-nearby',
        body: {
          'latitude': latitude,
          'longitude': longitude,
        },
      );

      if (response.status != 200) {
        throw Exception(
          'Failed to get recommendations. Status: ${response.status}',
        );
      }

      final data = response.data;

      if (data == null) {
        return [];
      }

      final recommendations = data['recommendations'];

      if (recommendations == null || recommendations is! List) {
        return [];
      }

      return recommendations
          .map(
            (item) => Recommendation.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
          .toList();
    } catch (e) {
      throw Exception(
        'Unable to retrieve nearby recommendations: $e',
      );
    }
  }
}