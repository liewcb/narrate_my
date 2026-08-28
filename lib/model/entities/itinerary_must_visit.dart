// lib/model/entities/itinerary_must_visit.dart

class ItineraryMustVisit {
  final int mustVisitId;
  final String itineraryId;
  final String? placeId;      // references places.id (Google place id)
  final String placeName;
  final String? destinationId; // references destinations.destinationId
  final String source;        // 'BOOKMARK', 'GOOGLE_SEARCH'
  final bool isVerified;
  final DateTime? createdAt;

  const ItineraryMustVisit({
    required this.mustVisitId,
    required this.itineraryId,
    this.placeId,
    required this.placeName,
    this.destinationId,
    this.source = 'GOOGLE_SEARCH',
    this.isVerified = false,
    this.createdAt,
  });

  ItineraryMustVisit copyWith({
    int? mustVisitId,
    String? itineraryId,
    String? placeId,
    bool clearPlaceId = false,
    String? placeName,
    String? destinationId,
    String? source,
    bool? isVerified,
    DateTime? createdAt,
  }) {
    return ItineraryMustVisit(
      mustVisitId: mustVisitId ?? this.mustVisitId,
      itineraryId: itineraryId ?? this.itineraryId,
      placeId: clearPlaceId ? null : (placeId ?? this.placeId),
      placeName: placeName ?? this.placeName,
      destinationId: destinationId ?? this.destinationId,
      source: source ?? this.source,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
