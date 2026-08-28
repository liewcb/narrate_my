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
}
