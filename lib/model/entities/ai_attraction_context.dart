/// Attraction context carried into UC500 from AR, Itinerary, or Recommendation.
///
/// [attractionId] is optional because a tourist may type an attraction name
/// that is not yet present in the shared attraction catalogue.
class AiAttractionContext {
  const AiAttractionContext({
    this.attractionId,
    this.attractionName,
    this.markerId,
    this.placeId,
    this.latitude,
    this.longitude,
    required this.source,
  });

  final String? attractionId;
  final String? attractionName;
  final String? markerId;
  final String? placeId;
  final double? latitude;
  final double? longitude;
  final String source;

  Map<String, dynamic> toJson() => {
    'attractionId': attractionId,
    'attractionName': attractionName,
    'markerId': markerId,
    'placeId': placeId,
    'latitude': latitude,
    'longitude': longitude,
    'source': source,
  };
}
