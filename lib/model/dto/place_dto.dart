import 'dart:convert';

import '../entities/openning_hours.dart';
import '../entities/place.dart';

/// Data Transfer Object for [Place] — local SQLite + remote Supabase.
class PlaceDto {
  final String id;
  final String placeId;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final double? rating;
  final List<String>? types;
  final String? category;
  final int? visitDurationMinutes;
  final String? bestTimeSuggestion;
  final int? priceLevel;
  final String? phoneNumber;
  final String? website;
  final String? photoReference;
  final Map<String, dynamic>? openingHours;
  final int? placeTotalReviews;
  final String? businessStatus;
  final String? destinationId;
  final String? hotspotId;

  const PlaceDto({
    required this.id,
    required this.placeId,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.rating,
    this.types,
    this.category,
    this.visitDurationMinutes,
    this.bestTimeSuggestion,
    this.priceLevel,
    this.phoneNumber,
    this.website,
    this.photoReference,
    this.openingHours,
    this.placeTotalReviews,
    this.businessStatus,
    this.destinationId,
    this.hotspotId,
  });

  // ============================================================
  // FROM JSON (remote)
  // ============================================================

  factory PlaceDto.fromJson(Map<String, dynamic> json) {
    return PlaceDto(
      id: json['id']?.toString() ?? '',
      placeId: json['place_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      rating: json['rating'] != null
          ? (json['rating'] as num).toDouble()
          : null,
      types: json['types'] != null
          ? (json['types'] as List).map((e) => e.toString()).toList()
          : null,
      category: json['category'] as String?,
      visitDurationMinutes: json['visit_duration_minutes'] as int?,
      bestTimeSuggestion: json['best_time_suggestion'] as String?,
      priceLevel: json['price_level'] as int?,
      phoneNumber: json['phone_number'] as String?,
      website: json['website'] as String?,
      photoReference: json['photo_reference'] as String?,
      openingHours: json['opening_hours'] != null
          ? (json['opening_hours'] is Map
              ? Map<String, dynamic>.from(json['opening_hours'] as Map)
              : jsonDecode(json['opening_hours'] as String)
                  as Map<String, dynamic>)
          : null,
      placeTotalReviews: json['user_ratings_total'] as int?,
      businessStatus: json['business_status'] as String?,
      destinationId: json['destination_id'] as String?,
      hotspotId: json['hotspot_id'] as String?,
    );
  }

  // ============================================================
  // TO JSON FOR SUPABASE (remote)
  // ============================================================

  Map<String, dynamic> toJsonForRemote() {
    // The shared public.places table stores only canonical place details.
    // destinationId/hotspotId and the extra Google scoring fields remain
    // available on Place for the itinerary pipeline, but they are not columns
    // in that table and must not be sent to PostgREST.
    final effectiveId = id.trim().isNotEmpty ? id.trim() : placeId.trim();
    return {
      'id': effectiveId,
      'place_id': placeId,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'types': types,
      'category': category,
      'visit_duration_minutes': visitDurationMinutes,
      'best_time_suggestion': bestTimeSuggestion,
      'price_level': priceLevel,
      'phone_number': phoneNumber,
      'website': website,
      'photo_reference': photoReference,
      'opening_hours': openingHours,
    };
  }

  // ============================================================
  // TO MAP (SQLite local)
  // ============================================================

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'place_id': placeId,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'types': types?.join(','),
      'category': category,
      'visit_duration_minutes': visitDurationMinutes,
      'best_time_suggestion': bestTimeSuggestion,
      'price_level': priceLevel,
      'phone_number': phoneNumber,
      'website': website,
      'photo_reference': photoReference,
      'opening_hours': openingHours != null ? jsonEncode(openingHours) : null,
    };
  }

  factory PlaceDto.fromMap(Map<String, dynamic> map) {
    return PlaceDto(
      id: map['id'] as String,
      placeId: map['place_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      rating: map['rating'] != null
          ? (map['rating'] as num).toDouble()
          : null,
      types: map['types'] != null
          ? (map['types'] as String)
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : null,
      category: map['category'] as String?,
      visitDurationMinutes: map['visit_duration_minutes'] as int?,
      bestTimeSuggestion: map['best_time_suggestion'] as String?,
      priceLevel: map['price_level'] as int?,
      phoneNumber: map['phone_number'] as String?,
      website: map['website'] as String?,
      photoReference: map['photo_reference'] as String?,
      openingHours: map['opening_hours'] != null
          ? (map['opening_hours'] is Map
              ? Map<String, dynamic>.from(map['opening_hours'] as Map)
              : jsonDecode(map['opening_hours'] as String)
                  as Map<String, dynamic>)
          : null,
    );
  }

  // ============================================================
  // TO ENTITY
  // ============================================================

  Place toEntity() {
    return Place(
      id: id,
      placeId: placeId,
      placeName: name,
      placeAddress: address ?? '',
      placeLatitude: latitude,
      placeLongitude: longitude,
      placeRating: rating ?? 0.0,
      placeTypes: types ?? [],
      placePhotoRef: photoReference,
      placePhone: phoneNumber,
      placeWebsite: website,
      placeRegularOpeningHours: openingHours != null
          ? OpeningHours.fromJson(openingHours!)
          : null,
      placePriceLevel: priceLevel,
      placeTotalReviews: placeTotalReviews,
      businessStatus: businessStatus,
      visitDurationMinutes: visitDurationMinutes,
      category: category,
      bestTimeSuggestion: bestTimeSuggestion,
      destinationId: destinationId,
      hotspotId: hotspotId,
    );
  }

  // ============================================================
  // FROM ENTITY
  // ============================================================

  factory PlaceDto.fromEntity(Place place) {
    return PlaceDto(
      id: place.id,
      placeId: place.placeId,
      name: place.placeName,
      address: place.placeAddress,
      latitude: place.placeLatitude,
      longitude: place.placeLongitude,
      rating: place.placeRating,
      types: place.placeTypes,
      category: place.category,
      visitDurationMinutes: place.visitDurationMinutes,
      bestTimeSuggestion: place.bestTimeSuggestion,
      priceLevel: place.placePriceLevel,
      phoneNumber: place.placePhone,
      website: place.placeWebsite,
      photoReference: place.placePhotoRef,
      openingHours: place.placeRegularOpeningHours?.toJson(),
      placeTotalReviews: place.placeTotalReviews,
      businessStatus: place.businessStatus,
      destinationId: place.destinationId,
      hotspotId: place.hotspotId,
    );
  }
}
