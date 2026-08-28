import 'dart:convert';

import '../entities/openning_hours.dart';
import '../entities/place.dart';

class PlaceDto {
  final String id;
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double rating;
  final List<String> types;
  final OpeningHours? openingHours;
  final int? priceLevel;
  final String? phoneNumber;
  final String? website;
  final String? photoReference;
  final int? visitDurationMinutes;
  final String? category;
  final String? bestTimeSuggestion;

  const PlaceDto({
    required this.id,
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.types,
    this.openingHours,
    this.priceLevel,
    this.phoneNumber,
    this.website,
    this.photoReference,
    this.visitDurationMinutes,
    this.category,
    this.bestTimeSuggestion,
  });

  // ─── From Domain Entity ──────────────────────────────────────────

  factory PlaceDto.fromEntity(Place entity) {
    return PlaceDto(
      id: entity.id,
      placeId: entity.placeId,
      name: entity.name,
      address: entity.address,
      latitude: entity.coordinates.latitude,
      longitude: entity.coordinates.longitude,
      rating: entity.rating,
      types: entity.types,
      openingHours: entity.openingHours,
      priceLevel: entity.priceLevel,
      phoneNumber: entity.phoneNumber,
      website: entity.website,
      photoReference: entity.photoReference,
      visitDurationMinutes: entity.visitDurationMinutes,
      category: entity.category,
      bestTimeSuggestion: entity.bestTimeSuggestion,
    );
  }

  // ─── To Domain Entity ────────────────────────────────────────────

  Place toEntity() {
    return Place(
      id: id,
      placeId: placeId,
      placeName: name,
      placeAddress: address,
      placeLatitude: latitude,
      placeLongitude: longitude,
      placeRating: rating,
      placeTypes: types,
      placeRegularOpeningHours: openingHours,
      placePriceLevel: priceLevel,
      placePhone: phoneNumber,
      placeWebsite: website,
      placePhotoRef: photoReference,
      visitDurationMinutes: visitDurationMinutes,
      category: category,
      bestTimeSuggestion: bestTimeSuggestion,
    );
  }

  // ─── To Local Database Map (SQLite) ─────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'place_id': placeId,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'types': types.join(','),
      'opening_hours': openingHours != null ? jsonEncode(openingHours!.toJson()) : null,
      'price_level': priceLevel,
      'phone_number': phoneNumber,
      'website': website,
      'photo_reference': photoReference,
      'visit_duration_minutes': visitDurationMinutes,
      'category': category,
      'best_time_suggestion': bestTimeSuggestion,
    };
  }

  // ─── From Local Database Map ─────────────────────────────────────

  factory PlaceDto.fromMap(Map<String, dynamic> map) {
    return PlaceDto(
      id: map['id'] as String,
      placeId: map['place_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      rating: (map['rating'] as num).toDouble(),
      types: map['types'] != null
          ? (map['types'] as String).split(',').map((e) => e.trim()).toList()
          : [],
      openingHours: map['opening_hours'] != null
          ? OpeningHours.fromJson(jsonDecode(map['opening_hours'] as String) as Map<String, dynamic>)
          : null,
      priceLevel: map['price_level'] as int?,
      phoneNumber: map['phone_number'] as String?,
      website: map['website'] as String?,
      photoReference: map['photo_reference'] as String?,
      visitDurationMinutes: map['visit_duration_minutes'] as int?,
      category: map['category'] as String?,
      bestTimeSuggestion: map['best_time_suggestion'] as String?,
    );
  }

  // ─── From Supabase (Remote) ──────────────────────────────────────

  factory PlaceDto.fromJson(Map<String, dynamic> json) {
    return PlaceDto(
      id: json['id']?.toString() ?? '',
      placeId: json['place_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      types: json['types'] != null
          ? (json['types'] as List).map((e) => e.toString()).toList()
          : [],
      openingHours: json['opening_hours'] != null
          ? OpeningHours.fromJson(json['opening_hours'] as Map<String, dynamic>)
          : null,
      priceLevel: json['price_level'] as int?,
      phoneNumber: json['phone_number'] as String?,
      website: json['website'] as String?,
      photoReference: json['photo_reference'] as String?,
      visitDurationMinutes: json['visit_duration_minutes'] as int?,
      category: json['category'] as String?,
      bestTimeSuggestion: json['best_time_suggestion'] as String?,
    );
  }

  // ─── To Supabase (Remote) ─────────────────────────────────────────
  // Leave opening_hours as a Map – Supabase jsonb accepts it.

  Map<String, dynamic> toJsonForRemote() {
    // Ensure we have an id – if empty, fallback to placeId.
    final effectiveId = id.isNotEmpty ? id : placeId;
    return {
      'id': effectiveId,
      'place_id': placeId,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'types': types,           // Supabase ARRAY
      'category': category,
      'visit_duration_minutes': visitDurationMinutes,
      'best_time_suggestion': bestTimeSuggestion,
      'price_level': priceLevel,
      'phone_number': phoneNumber,
      'website': website,
      'photo_reference': photoReference,
      'opening_hours': openingHours?.toJson(),
    };
  }
}