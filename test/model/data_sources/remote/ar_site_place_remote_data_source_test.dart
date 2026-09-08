import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/data_sources/remote/ar_site_place_remote_data_source.dart';

void main() {
  group('ARSitePlaceRemoteDataSource response parsing', () {
    test('creates a bookmarkable place with its signed image URL', () {
      final place = ARSitePlaceRemoteDataSource.placeFromResponse({
        'place_id': 'google-place-1',
        'name': 'Orang Asli Crafts Museum',
        'address': 'Museum Road',
        'latitude': 3.135,
        'longitude': 101.688,
        'rating': 4.4,
        'types': ['museum', 'tourist_attraction'],
        'category': 'Museum',
        'photo_reference': 'places/google-place-1/photos/photo-1',
        'image_url': 'https://example.supabase.co/functions/v1/place-photo',
      });

      expect(place, isNotNull);
      expect(place!.placeId, 'google-place-1');
      expect(place.placeName, 'Orang Asli Crafts Museum');
      expect(place.placeImageUrl, contains('/functions/v1/place-photo'));
      expect(place.placeTypes, contains('museum'));
    });

    test('rejects a response without a verified Google Place ID', () {
      final place = ARSitePlaceRemoteDataSource.placeFromResponse({
        'name': 'Unverified attraction',
        'latitude': 3.135,
        'longitude': 101.688,
      });

      expect(place, isNull);
    });
  });
}
