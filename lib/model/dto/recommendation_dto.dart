import '../entities/recommendation.dart';

/// Transport model for the `recommend-nearby` Edge Function response.
///
/// Gemini currently guarantees the descriptive fields. Location and photo
/// fields are optional because older function responses do not include them;
/// the repository enriches those responses through Google Places.
class RecommendationDto {
  final String? placeId;
  final String name;
  final String category;
  final String? address;
  final String reason;
  final int rank;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? photoReference;
  final double? rating;

  const RecommendationDto({
    this.placeId,
    required this.name,
    required this.category,
    this.address,
    required this.reason,
    required this.rank,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.photoReference,
    this.rating,
  });

  factory RecommendationDto.fromJson(Map<String, dynamic> json) {
    final geometry = _asMap(json['geometry']);
    final location = _asMap(geometry?['location']) ?? _asMap(json['location']);

    return RecommendationDto(
      placeId: _asString(json['place_id'] ?? json['placeId']),
      name: _asString(json['name']) ?? 'Unknown attraction',
      category: _asString(json['category']) ?? 'Attraction',
      address: _asString(
        json['address'] ?? json['formatted_address'] ?? json['vicinity'],
      ),
      reason: _asString(json['reason']) ?? 'Recommended for your trip.',
      rank: _asInt(json['rank']) ?? 0,
      latitude: _asDouble(json['latitude'] ?? json['lat'] ?? location?['lat']),
      longitude: _asDouble(
        json['longitude'] ?? json['lng'] ?? location?['lng'],
      ),
      imageUrl: _asString(
        json['image_url'] ?? json['imageUrl'] ?? json['photo_url'],
      ),
      photoReference: _asString(
        json['photo_reference'] ?? json['photoReference'],
      ),
      rating: _asDouble(json['rating']),
    );
  }

  Recommendation toEntity({
    required String resolvedPlaceId,
    required double resolvedLatitude,
    required double resolvedLongitude,
    required String resolvedAddress,
    required double distanceKm,
    required int estimatedTravelMinutes,
    String? resolvedImageUrl,
    double? resolvedRating,
  }) {
    return Recommendation(
      placeId: resolvedPlaceId,
      name: name,
      category: category,
      address: resolvedAddress,
      reason: reason,
      rank: rank,
      latitude: resolvedLatitude,
      longitude: resolvedLongitude,
      imageUrl: resolvedImageUrl,
      rating: resolvedRating,
      distanceKm: distanceKm,
      estimatedTravelMinutes: estimatedTravelMinutes,
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _asString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
