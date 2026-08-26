// lib/data/dto/place_dto.dart
import '../entities/openning_hours.dart';
import '../entities/place.dart';
import '../entities/coordinates.dart';

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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'place_id': placeId,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'types': types,
      'opening_hours': openingHours?.toJson(),
      'price_level': priceLevel,
      'phone_number': phoneNumber,
      'website': website,
      'photo_reference': photoReference,
      'visit_duration_minutes': visitDurationMinutes,
      'category': category,
      'best_time_suggestion': bestTimeSuggestion,
    };
  }

  factory PlaceDto.fromMap(Map<String, dynamic> map) {
    return PlaceDto(
      id: map['id'] as String,
      placeId: map['place_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      rating: (map['rating'] as num).toDouble(),
      types: List<String>.from(map['types'] ?? []),
      openingHours: map['opening_hours'] != null
          ? OpeningHours.fromJson(map['opening_hours'] as Map<String, dynamic>)
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
}