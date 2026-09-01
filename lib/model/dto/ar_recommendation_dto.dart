import '../entities/ar_recommendation.dart';

/// Transport model returned by the `recommend-ar` Edge Function.
class ARRecommendationDto {
  final String attractionId;
  final String markerId;
  final String placeId;
  final String name;
  final String category;
  final String address;
  final String summary;
  final String reason;
  final String relationship;
  final int rank;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String? imageUrl;
  final double? rating;

  const ARRecommendationDto({
    required this.attractionId,
    required this.markerId,
    required this.placeId,
    required this.name,
    required this.category,
    required this.address,
    required this.summary,
    required this.reason,
    required this.relationship,
    required this.rank,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.imageUrl,
    this.rating,
  });

  factory ARRecommendationDto.fromJson(Map<String, dynamic> json) {
    return ARRecommendationDto(
      attractionId: _string(json['attraction_id']),
      markerId: _string(json['marker_id']),
      placeId: _string(json['place_id']),
      name: _string(json['name'], fallback: 'Unknown attraction'),
      category: _string(json['category'], fallback: 'Attraction'),
      address: _string(json['address'], fallback: 'Address unavailable'),
      summary: _string(
        json['summary'],
        fallback: 'More information is available at this attraction.',
      ),
      reason: _string(
        json['reason'],
        fallback: 'This experience complements what you are viewing.',
      ),
      relationship: _string(
        json['relationship'],
        fallback: 'Complementary experience',
      ),
      rank: _integer(json['rank'], fallback: 1),
      latitude: _number(json['latitude']),
      longitude: _number(json['longitude']),
      distanceKm: _number(json['distance_km']),
      imageUrl: _nullableString(json['image_url']),
      rating: json['rating'] == null ? null : _number(json['rating']),
    );
  }

  ARRecommendation toEntity() => ARRecommendation(
    attractionId: attractionId,
    markerId: markerId,
    placeId: placeId,
    name: name,
    category: category,
    address: address,
    summary: summary,
    reason: reason,
    relationship: relationship,
    rank: rank,
    latitude: latitude,
    longitude: longitude,
    distanceKm: distanceKm,
    imageUrl: imageUrl,
    rating: rating,
  );

  static String _string(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _integer(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
