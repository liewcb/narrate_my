class RecommendationLog {
  final String? id;
  final String? userId;

  final String recommendationType;

  final double? currentLatitude;
  final double? currentLongitude;

  final String? currentAttractionId;

  final Map<String, dynamic> preferencesSnapshot;

  final String prompt;

  final Map<String, dynamic>? responseJson;

  final String status;

  final String? modelName;

  final int? latencyMs;

  final DateTime? createdAt;

  const RecommendationLog({
    this.id,
    this.userId,
    required this.recommendationType,
    this.currentLatitude,
    this.currentLongitude,
    this.currentAttractionId,
    this.preferencesSnapshot = const {},
    required this.prompt,
    this.responseJson,
    this.status = 'success',
    this.modelName,
    this.latencyMs,
    this.createdAt,
  });

  factory RecommendationLog.fromJson(Map<String, dynamic> json) {
    return RecommendationLog(
      id: json['id'] as String?,
      userId: json['user_id'] as String?,
      recommendationType: json['recommendation_type'] as String,
      currentLatitude: _toDouble(json['current_latitude']),
      currentLongitude: _toDouble(json['current_longitude']),
      currentAttractionId: json['current_attraction_id'] as String?,
      preferencesSnapshot:
      Map<String, dynamic>.from(
        json['preferences_snapshot'] ?? {},
      ),
      prompt: json['prompt'] as String,
      responseJson:
      json['response_json'] != null
          ? Map<String, dynamic>.from(json['response_json'])
          : null,
      status: json['status'] as String? ?? 'success',
      modelName: json['model_name'] as String?,
      latencyMs: json['latency_ms'] as int?,
      createdAt:
      json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,

      'recommendation_type': recommendationType,

      if (currentLatitude != null)
        'current_latitude': currentLatitude,

      if (currentLongitude != null)
        'current_longitude': currentLongitude,

      if (currentAttractionId != null)
        'current_attraction_id': currentAttractionId,

      'preferences_snapshot': preferencesSnapshot,

      'prompt': prompt,

      if (responseJson != null)
        'response_json': responseJson,

      'status': status,

      if (modelName != null)
        'model_name': modelName,

      if (latencyMs != null)
        'latency_ms': latencyMs,
    };
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }
}