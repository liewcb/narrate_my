import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_manager.dart';
import '../../dto/ar_recommendation_dto.dart';

class ARRecommendationRemoteDataSource {
  final SupabaseClient _client;

  ARRecommendationRemoteDataSource({SupabaseClient? client})
    : _client = client ?? DatabaseManager().remote.client;

  Future<List<ARRecommendationDto>> recommend({
    required String currentMarkerId,
    required String currentAttractionName,
    required double latitude,
    required double longitude,
    required List<String> excludedMarkerIds,
  }) async {
    try {
      final token = _client.auth.currentSession?.accessToken;
      final response = await _client.functions.invoke(
        'recommend-ar',
        body: {
          'current_marker_id': currentMarkerId,
          'current_attraction_name': currentAttractionName,
          'latitude': latitude,
          'longitude': longitude,
          'excluded_marker_ids': excludedMarkerIds,
        },
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
      );

      if (response.status < 200 || response.status >= 300) {
        throw ARRecommendationRemoteException(
          _message(response.data),
          statusCode: response.status,
        );
      }

      final raw = response.data is Map
          ? (response.data as Map)['recommendations']
          : response.data;
      if (raw is! List) return [];

      return raw
          .whereType<Map>()
          .map(
            (row) =>
                ARRecommendationDto.fromJson(Map<String, dynamic>.from(row)),
          )
          .where(
            (item) =>
                item.attractionId.isNotEmpty &&
                item.markerId.isNotEmpty &&
                item.placeId.isNotEmpty,
          )
          .toList();
    } on ARRecommendationRemoteException {
      rethrow;
    } catch (error) {
      throw ARRecommendationRemoteException(
        'Unable to retrieve AR recommendations. Please try again.',
        cause: error,
      );
    }
  }

  String _message(dynamic data) {
    if (data is Map) {
      final value = data['error'] ?? data['message'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return 'Unable to retrieve AR recommendations. Please try again.';
  }
}

class ARRecommendationRemoteException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  const ARRecommendationRemoteException(
    this.message, {
    this.statusCode,
    this.cause,
  });

  @override
  String toString() => message;
}
