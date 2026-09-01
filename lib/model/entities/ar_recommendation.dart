import 'place.dart';

/// One contextual recommendation shown over the AR camera.
///
/// [attractionId] and [markerId] identify the NarrateMy AR experience, while
/// [placeId] is the Google Places ID used by the shared bookmark pipeline.
class ARRecommendation {
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

  const ARRecommendation({
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

  int get estimatedWalkMinutes {
    if (distanceKm <= 0) return 1;
    return (distanceKm / 5 * 60).ceil().clamp(1, 999).toInt();
  }

  int get estimatedDriveMinutes {
    if (distanceKm <= 0) return 1;
    return (distanceKm / 35 * 60).ceil().clamp(1, 999).toInt();
  }

  bool get isWalkable => distanceKm <= 2;

  String get travelSummary => isWalkable
      ? '$estimatedWalkMinutes min walk'
      : '~$estimatedDriveMinutes min by car';

  Place toBookmarkPlace() => Place(
    placeId: placeId,
    placeName: name,
    placeAddress: address,
    placeLatitude: latitude,
    placeLongitude: longitude,
    placeRating: rating ?? 0,
    placeTypes: [category],
    category: category,
  );
}
