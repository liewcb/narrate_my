class Recommendation {
  final String placeId;
  final String name;
  final String category;
  final String address;
  final String reason;
  final int rank;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final double? rating;
  final double distanceKm;
  final int estimatedTravelMinutes;

  const Recommendation({
    required this.placeId,
    required this.name,
    required this.category,
    required this.address,
    required this.reason,
    required this.rank,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
    this.rating,
    required this.distanceKm,
    required this.estimatedTravelMinutes,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      placeId: json['place_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown attraction',
      category: json['category']?.toString() ?? 'Attraction',
      address: json['address']?.toString() ?? 'Address unavailable',
      reason: json['reason']?.toString() ?? 'Recommended for your trip.',
      rank: _toInt(json['rank']),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      imageUrl: _nullableString(json['image_url']),
      rating: json['rating'] == null ? null : _toDouble(json['rating']),
      distanceKm: _toDouble(json['distance_km']),
      estimatedTravelMinutes: _toInt(json['estimated_travel_minutes']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place_id': placeId,
      'name': name,
      'category': category,
      'address': address,
      'reason': reason,
      'rank': rank,
      'latitude': latitude,
      'longitude': longitude,
      if (imageUrl != null) 'image_url': imageUrl,
      if (rating != null) 'rating': rating,
      'distance_km': distanceKm,
      'estimated_travel_minutes': estimatedTravelMinutes,
    };
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
