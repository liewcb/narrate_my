import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/DTO/recommendation_dto.dart';

void main() {
  test('parses the server-enriched nearby recommendation contract', () {
    final dto = RecommendationDto.fromJson({
      'place_id': 'google-place-123',
      'name': 'National Museum of Malaysia',
      'category': 'Museum',
      'address': 'Jalan Damansara, Kuala Lumpur',
      'reason': 'Matches your heritage interests.',
      'rank': 1,
      'latitude': 3.1379,
      'longitude': 101.6870,
      'rating': 4.6,
      'photo_reference': 'places/google-place-123/photos/photo-456',
      'image_url':
          'https://example.supabase.co/functions/v1/place-photo?signed=true',
    });

    expect(dto.placeId, 'google-place-123');
    expect(dto.latitude, closeTo(3.1379, 0.00001));
    expect(dto.longitude, closeTo(101.6870, 0.00001));
    expect(dto.rating, 4.6);
    expect(dto.photoReference, 'places/google-place-123/photos/photo-456');
    expect(dto.imageUrl, contains('/functions/v1/place-photo'));
  });
}
