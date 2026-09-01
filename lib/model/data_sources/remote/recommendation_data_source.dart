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
      final accessToken = _supabase.auth.currentSession?.accessToken;
      final response = await _supabase.functions.invoke(
        'recommend-nearby',
        body: {'latitude': latitude, 'longitude': longitude},
        headers: accessToken == null
            ? null
            : {'Authorization': 'Bearer $accessToken'},
      );

      if (response.status < 200 || response.status >= 300) {
        throw RecommendationRemoteException(
          _errorMessage(response.data),
          statusCode: response.status,
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
    } on RecommendationRemoteException {
      rethrow;
    } catch (e) {
      throw RecommendationRemoteException(
        'Unable to retrieve nearby recommendations.',
        cause: e,
      );
    }
  }

  String _errorMessage(dynamic data) {
    if (data is Map) {
      final message = data['error'] ?? data['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return 'Unable to retrieve nearby recommendations.';
  }
}

class RecommendationRemoteException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  const RecommendationRemoteException(
    this.message, {
    this.statusCode,
    this.cause,
  });

  bool get isQuotaLimited => statusCode == 429;

  @override
  String toString() => message;
}
