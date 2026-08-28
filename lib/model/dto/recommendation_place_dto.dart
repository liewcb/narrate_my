/// Transport model for a Google Places API (New) text-search result used only
/// by the Nearby Recommendation module.
class RecommendationPlaceDto {
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double? rating;
  final String? photoResourceName;

  const RecommendationPlaceDto({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.rating,
    this.photoResourceName,
  });

  factory RecommendationPlaceDto.fromPlacesApiNew(Map<String, dynamic> json) {
    final displayName = _asMap(json['displayName']);
    final location = _asMap(json['location']);
    final photos = json['photos'] as List?;
    final firstPhoto = photos != null && photos.isNotEmpty
        ? _asMap(photos.first)
        : null;

    final latitude = _asDouble(location?['latitude']);
    final longitude = _asDouble(location?['longitude']);
    if (latitude == null || longitude == null) {
      throw const FormatException(
        'Google Places result did not include valid coordinates.',
      );
    }

    return RecommendationPlaceDto(
      placeId: _asString(json['id']) ?? '',
      name: _asString(displayName?['text']) ?? 'Unknown attraction',
      address: _asString(json['formattedAddress']) ?? 'Address unavailable',
      latitude: latitude,
      longitude: longitude,
      rating: _asDouble(json['rating']),
      photoResourceName: _asString(firstPhoto?['name']),
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
}
