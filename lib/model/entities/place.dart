// lib/model/entities/place.dart
//
// Central immutable Place model — the single source of truth for every
// place that enters the pipeline.  All field names match the canonical
// naming requested by the architecture.  Backward-compatible getters
// (name, address, coordinates, rating, types, …) delegate to the
// canonical fields so existing code compiles without changes.
//
// NEW field (not in the original entity):
//   - placeTotalReviews  (int?) – populated from Google's user_ratings_total
//   - businessStatus     (String?) – Google's business_status (e.g. OPERATIONAL)

import 'coordinates.dart';
import 'openning_hours.dart';

class Place {
  // ── Canonical fields (architecture requirement) ──────────────
  final String placeId;               // Google Places API ID
  final String placeName;
  final String placeAddress;
  final double placeLatitude;
  final double placeLongitude;
  final double placeRating;
  final int? placeTotalReviews;
  final String? businessStatus;       // 'OPERATIONAL', 'CLOSED_TEMPORARILY', …
  final List<String> placeTypes;
  final String? placePhotoRef;
  final String? placePhone;
  final String? placeWebsite;
  final OpeningHours? placeRegularOpeningHours;
  final int? placePriceLevel;

  // ── Pipeline-computed fields (immutable) ─────────────────────
  final int? visitDurationMinutes;
  final String? category;
  final String? bestTimeSuggestion;

  // ── Source identity (assigned during candidate retrieval) ─────
  final String? destinationId;  // e.g. "D001"
  final String? hotspotId;      // e.g. "H_KL_01"

  // ── Local DB ID (optional) ───────────────────────────────────
  final String id;

  // ── Constructor ──────────────────────────────────────────────
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

  // ── Backward-compatible getters (delegate to canonical fields) ─
  String get name => placeName;
  String get address => placeAddress;
  double get latitude => placeLatitude;
  double get longitude => placeLongitude;
  Coordinates get coordinates =>
      Coordinates(latitude: placeLatitude, longitude: placeLongitude);
  double get rating => placeRating;
  List<String> get types => placeTypes;
  OpeningHours? get openingHours => placeRegularOpeningHours;
  String? get photoReference => placePhotoRef;
  String? get phoneNumber => placePhone;
  String? get website => placeWebsite;
  int? get priceLevel => placePriceLevel;

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
    final geometry = json['geometry']['location'];
    final types = (json['types'] as List?)?.cast<String>() ?? [];
    final category = _mapTypeToCategory(types);
    final duration = _getDurationByCategory(category);
    final bestTime = _getBestTimeByCategory(category);

    return Place(
      id: json['place_id'] ?? '',
      placeId: json['place_id'] ?? '',
      placeName: json['name'] ?? 'Unknown',
      placeAddress: json['vicinity'] ?? json['formatted_address'] ?? '',
      placeLatitude: (geometry['lat'] as num).toDouble(),
      placeLongitude: (geometry['lng'] as num).toDouble(),
      placeRating: (json['rating'] as num?)?.toDouble() ?? 3.5,
      placeTotalReviews: json['user_ratings_total'] as int?,
      businessStatus: json['business_status'] as String?,
      placeTypes: types,
      placePhotoRef: json['photos'] != null && (json['photos'] as List).isNotEmpty
          ? json['photos'][0]['photo_reference'] as String?
          : null,
      placePhone: json['formatted_phone_number'] as String?,
      placeWebsite: json['website'] as String?,
      placeRegularOpeningHours: json['opening_hours'] != null
          ? OpeningHours.fromJson(json['opening_hours'])
          : null,
      placePriceLevel: json['price_level'] as int?,
      visitDurationMinutes: duration,
      category: category,
      bestTimeSuggestion: bestTime,
    );
  }

  // ── Copy (immutable) ─────────────────────────────────────────
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

  // ── Serialization ────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'id': id,
    'placeId': placeId,
    'name': placeName,
    'address': placeAddress,
    'latitude': placeLatitude,
    'longitude': placeLongitude,
    'rating': placeRating,
    'user_ratings_total': placeTotalReviews,
    'business_status': businessStatus,
    'types': placeTypes,
    'photoRef': placePhotoRef,
    'phone': placePhone,
    'website': placeWebsite,
    'priceLevel': placePriceLevel,
    'visitDurationMinutes': visitDurationMinutes,
    'category': category,
    'bestTimeSuggestion': bestTimeSuggestion,
    'destinationId': destinationId,
    'hotspotId': hotspotId,
  };

  // ── Equality (keyed on placeId) ──────────────────────────────
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Place && runtimeType == other.runtimeType && placeId == other.placeId;

  @override
  int get hashCode => placeId.hashCode;

  @override
  String toString() => 'Place(placeId: $placeId, name: $placeName)';

  // ── Category / duration helpers (unchanged) ──────────────────
  static String _mapTypeToCategory(List<String> types) {
    const typeMap = <String, String>{
      'museum': 'museum',
      'art_gallery': 'cultural',
      'amusement_park': 'adventure',
      'theme_park': 'adventure',
      'water_park': 'adventure',
      'campground': 'adventure',
      'park': 'nature',
      'natural_feature': 'nature',
      'garden': 'nature',
      'forest': 'nature',
      'beach': 'nature',
      'tourist_attraction': 'landmark',
      'hindu_temple': 'religious',
      'place_of_worship': 'religious',
      'church': 'religious',
      'mosque': 'religious',
      'shopping_mall': 'shopping',
      'restaurant': 'restaurant',
      'cafe': 'restaurant',
      'night_club': 'nightlife',
      'bar': 'nightlife',
      'movie_theater': 'nightlife',
    };
    for (final type in types) {
      if (typeMap.containsKey(type)) return typeMap[type]!;
    }
    return 'landmark';
  }

  static int _getDurationByCategory(String category) {
    const durationMap = <String, int>{
      'museum': 120,
      'cultural': 120,
      'adventure': 180,
      'nature': 120,
      'landmark': 60,
      'religious': 90,
      'shopping': 120,
      'restaurant': 60,
      'nightlife': 120,
    };
    return durationMap[category] ?? 120;
  }

  static String _getBestTimeByCategory(String category) {
    const bestTimeMap = <String, String>{
      'adventure': 'Morning (avoid afternoon heat and crowds)',
      'nature': 'Morning (cooler temperatures, better lighting)',
      'museum': 'Afternoon (indoor activities, flexible timing)',
      'cultural': 'Afternoon (indoor activities, flexible timing)',
      'religious': 'Morning (religious services, cooler weather)',
      'shopping': 'Afternoon (indoor, can adjust schedule)',
      'restaurant': 'Lunch or Dinner (meal times)',
      'nightlife': 'Evening (activities start at night)',
      'landmark': 'Morning or Late Afternoon (best lighting)',
    };
    return bestTimeMap[category] ?? 'Check opening hours';
  }

}