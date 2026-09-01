import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/dto/ar_recommendation_dto.dart';

void main() {
  test('maps recommend-ar response into the AR domain entity', () {
    final dto = ARRecommendationDto.fromJson({
      'attraction_id': 'AD010',
      'marker_id': 'MK010',
      'place_id': 'google-place-10',
      'name': 'Petrosains',
      'category': 'Museum',
      'address': 'Suria KLCC',
      'summary': 'An interactive science centre.',
      'reason': 'Continue exploring science and technology.',
      'relationship': 'Deepen the experience',
      'rank': 1,
      'latitude': 3.1579,
      'longitude': 101.7117,
      'distance_km': 0.8,
      'rating': 4.6,
      'image_url': 'https://example.test/photo',
    });

    final result = dto.toEntity();

    expect(result.attractionId, 'AD010');
    expect(result.markerId, 'MK010');
    expect(result.placeId, 'google-place-10');
    expect(result.relationship, 'Deepen the experience');
    expect(result.estimatedWalkMinutes, 10);
    expect(result.travelSummary, '10 min walk');
    expect(result.toBookmarkPlace().placeId, 'google-place-10');
  });

  test('uses safe defaults for optional presentation fields', () {
    final result = ARRecommendationDto.fromJson({
      'attraction_id': 'AD020',
      'marker_id': 'MK020',
      'place_id': 'google-place-20',
      'name': 'Example attraction',
      'latitude': 3,
      'longitude': 101,
      'distance_km': 0,
    }).toEntity();

    expect(result.category, 'Attraction');
    expect(result.relationship, 'Complementary experience');
    expect(result.estimatedWalkMinutes, 1);
    expect(result.travelSummary, '1 min walk');
  });
}
