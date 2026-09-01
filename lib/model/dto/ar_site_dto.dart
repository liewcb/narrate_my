import '../entities/ar_site.dart';

class ARSiteDto {
  final String siteId;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final String? category;
  final List<String> googlePlaceIds;
  final List<String> matchAliases;
  final double matchRadiusMeters;

  const ARSiteDto({
    required this.siteId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.category,
    this.googlePlaceIds = const [],
    this.matchAliases = const [],
    required this.matchRadiusMeters,
  });

  factory ARSiteDto.fromJson(Map<String, dynamic> json) {
    return ARSiteDto(
      siteId: json['site_id']?.toString() ?? '',
      name: json['display_name']?.toString() ?? 'AR location',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      address: _optionalString(json['address']),
      category: _optionalString(json['category']),
      googlePlaceIds: _toStrings(json['google_place_ids']),
      matchAliases: _toStrings(json['match_aliases']),
      matchRadiusMeters: _toDouble(json['match_radius_meters'], fallback: 150),
    );
  }

  ARSite toEntity({List<ARSiteExperience> experiences = const []}) {
    return ARSite(
      siteId: siteId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      address: address,
      category: category,
      googlePlaceIds: googlePlaceIds,
      matchAliases: matchAliases,
      matchRadiusMeters: matchRadiusMeters,
      experiences: experiences,
    );
  }

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String? _optionalString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _toStrings(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

class ARSiteExperienceDto {
  final String attractionId;
  final String siteId;
  final String markerId;
  final String name;

  const ARSiteExperienceDto({
    required this.attractionId,
    required this.siteId,
    required this.markerId,
    required this.name,
  });

  factory ARSiteExperienceDto.fromJson(Map<String, dynamic> json) {
    return ARSiteExperienceDto(
      attractionId: json['attraction_id']?.toString() ?? '',
      siteId: json['site_id']?.toString() ?? '',
      markerId: json['marker_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'AR experience',
    );
  }
}
