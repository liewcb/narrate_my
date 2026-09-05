// lib/model/entities/place.dart
import 'coordinates.dart';
import 'openning_hours.dart';

/// Canonical Place entity — every field name matches what the pipeline,
/// scoring, clustering and AI services expect.
class Place {
  // ── Canonical fields ─────────────────────────────────────────
  final String placeId; // Google Places API ID
  final String placeName;
  final String placeAddress;
  final double placeLatitude;
  final double placeLongitude;
  final double placeRating;
  final int? placeTotalReviews;
  final String? businessStatus; // 'OPERATIONAL', ...
  final List<String> placeTypes;
  final String? placePhotoRef;
  final String? placeImageUrl;
  final String? placePhotoGoogleMapsUri;
  final String? placePhone;
  final String? placeWebsite;
  final OpeningHours? placeRegularOpeningHours;
  final int? placePriceLevel;

  // ── Pipeline-computed fields ─────────────────────────────────
  final int? visitDurationMinutes;
  final String? category;
  final String? bestTimeSuggestion;

  // ── Source identity ──────────────────────────────────────────
  final String? destinationId; // e.g. "D001"
  final String? hotspotId; // e.g. "H_KL_01"

  // ── Local DB id (optional) ───────────────────────────────────
  final String id;

  const Place({
    this.id = '',
    required this.placeId,
    required this.placeName,
    required this.placeAddress,
    required this.placeLatitude,
    required this.placeLongitude,
    required this.placeRating,
    this.placeTotalReviews,
    this.businessStatus,
    required this.placeTypes,
    this.placePhotoRef,
    this.placeImageUrl,
    this.placePhotoGoogleMapsUri,
    this.placePhone,
    this.placeWebsite,
    this.placeRegularOpeningHours,
    this.placePriceLevel,
    this.visitDurationMinutes,
    this.category,
    this.bestTimeSuggestion,
    this.destinationId,
    this.hotspotId,
  });

  // ── Backward-compatible getters ──────────────────────────────
  String get name => placeName;
  String get address => placeAddress;
  double get latitude => placeLatitude;
  double get longitude => placeLongitude;
  double get rating => placeRating;
  List<String> get types => placeTypes;
  String? get photoReference => placePhotoRef;
  String? get imageUrl => placeImageUrl;
  String? get photoGoogleMapsUri => placePhotoGoogleMapsUri;
  String? get phoneNumber => placePhone;
  String? get website => placeWebsite;
  int? get priceLevel => placePriceLevel;
  OpeningHours? get openingHours => placeRegularOpeningHours;
  String? get placeCategory => category;

  Coordinates get coordinates =>
      Coordinates(latitude: placeLatitude, longitude: placeLongitude);

  /// Fallback placeholder used when a stop's place data is not yet
  /// joined (e.g. editing an itinerary before Places are loaded).
  factory Place.empty(String placeId) => Place(
    placeId: placeId,
    placeName: 'Place $placeId',
    placeAddress: '',
    placeLatitude: 0,
    placeLongitude: 0,
    placeRating: 0,
    placeTypes: const [],
  );

  // ── Factory: Google Places JSON → Place ──────────────────────
  factory Place.fromGooglePlacesJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    final typesList = (json['types'] as List?)?.cast<String>() ?? [];

    return Place(
      id: json['place_id'] as String? ?? '',
      placeId: json['place_id'] as String? ?? '',
      placeName: json['name'] as String? ?? '',
      placeAddress:
          json['vicinity'] as String? ??
          json['formatted_address'] as String? ??
          '',
      placeLatitude: (location?['lat'] as num?)?.toDouble() ?? 0.0,
      placeLongitude: (location?['lng'] as num?)?.toDouble() ?? 0.0,
      placeRating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      placeTotalReviews: json['user_ratings_total'] as int?,
      businessStatus: json['business_status'] as String?,
      placeTypes: typesList,
      placePhotoRef:
          json['photos'] != null && (json['photos'] as List).isNotEmpty
          ? (json['photos'][0] as Map<String, dynamic>)['photo_reference']
                as String?
          : null,
      placePhone: json['formatted_phone_number'] as String?,
      placeWebsite: json['website'] as String?,
      placeRegularOpeningHours: json['opening_hours'] != null
          ? OpeningHours.fromJson(
              Map<String, dynamic>.from(json['opening_hours'] as Map),
            )
          : null,
      placePriceLevel: json['price_level'] as int?,
      visitDurationMinutes: _getDurationByCategory(typesList),
      category: _mapTypeToCategory(typesList),
      bestTimeSuggestion: _getBestTimeByCategory(typesList),
    );
  }

  // ── Copy with (immutable) ────────────────────────────────────
  Place copyWith({
    String? id,
    String? placeId,
    String? placeName,
    String? placeAddress,
    double? placeLatitude,
    double? placeLongitude,
    double? placeRating,
    int? placeTotalReviews,
    String? businessStatus,
    List<String>? placeTypes,
    String? placePhotoRef,
    String? placeImageUrl,
    String? placePhotoGoogleMapsUri,
    String? placePhone,
    String? placeWebsite,
    OpeningHours? placeRegularOpeningHours,
    int? placePriceLevel,
    int? visitDurationMinutes,
    String? category,
    String? bestTimeSuggestion,
    String? destinationId,
    String? hotspotId,
  }) {
    return Place(
      id: id ?? this.id,
      placeId: placeId ?? this.placeId,
      placeName: placeName ?? this.placeName,
      placeAddress: placeAddress ?? this.placeAddress,
      placeLatitude: placeLatitude ?? this.placeLatitude,
      placeLongitude: placeLongitude ?? this.placeLongitude,
      placeRating: placeRating ?? this.placeRating,
      placeTotalReviews: placeTotalReviews ?? this.placeTotalReviews,
      businessStatus: businessStatus ?? this.businessStatus,
      placeTypes: placeTypes ?? this.placeTypes,
      placePhotoRef: placePhotoRef ?? this.placePhotoRef,
      placeImageUrl: placeImageUrl ?? this.placeImageUrl,
      placePhotoGoogleMapsUri:
          placePhotoGoogleMapsUri ?? this.placePhotoGoogleMapsUri,
      placePhone: placePhone ?? this.placePhone,
      placeWebsite: placeWebsite ?? this.placeWebsite,
      placeRegularOpeningHours:
          placeRegularOpeningHours ?? this.placeRegularOpeningHours,
      placePriceLevel: placePriceLevel ?? this.placePriceLevel,
      visitDurationMinutes: visitDurationMinutes ?? this.visitDurationMinutes,
      category: category ?? this.category,
      bestTimeSuggestion: bestTimeSuggestion ?? this.bestTimeSuggestion,
      destinationId: destinationId ?? this.destinationId,
      hotspotId: hotspotId ?? this.hotspotId,
    );
  }

  static String _mapTypeToCategory(List<String> types) {
    const typeMap = <String, String>{
      'museum': 'museum',
      'art_gallery': 'cultural',
      'amusement_park': 'adventure',
      'park': 'nature',
      'natural_feature': 'nature',
      'shopping_mall': 'shopping',
      'restaurant': 'restaurant',
      'cafe': 'restaurant',
      'night_club': 'nightlife',
      'bar': 'nightlife',
    };
    for (final type in types) {
      if (typeMap.containsKey(type)) return typeMap[type]!;
    }
    return 'landmark';
  }

  static int _getDurationByCategory(List<String> types) {
    const durationMap = <String, int>{
      'museum': 120,
      'art_gallery': 120,
      'amusement_park': 180,
      'park': 120,
      'natural_feature': 120,
      'shopping_mall': 120,
      'restaurant': 60,
      'cafe': 60,
      'night_club': 120,
      'bar': 90,
    };
    for (final type in types) {
      if (durationMap.containsKey(type)) return durationMap[type]!;
    }
    return 90;
  }

  static String _getBestTimeByCategory(List<String> types) {
    const bestTimeMap = <String, String>{
      'museum': 'Morning',
      'art_gallery': 'Afternoon',
      'amusement_park': 'Morning',
      'park': 'Morning',
      'natural_feature': 'Morning',
      'shopping_mall': 'Afternoon',
      'restaurant': 'Lunch/Dinner',
      'cafe': 'Morning',
      'night_club': 'Evening',
      'bar': 'Evening',
    };
    for (final type in types) {
      if (bestTimeMap.containsKey(type)) return bestTimeMap[type]!;
    }
    return 'Flexible';
  }
}
