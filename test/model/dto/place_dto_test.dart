import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/dto/bookmark_dto.dart';
import 'package:narrate_my/model/dto/place_dto.dart';
import 'package:narrate_my/model/entities/place.dart';

void main() {
  group('PlaceDto remote payload', () {
    test('matches the columns in the shared Supabase places table', () {
      const place = Place(
        placeId: 'ChIJ-test-place',
        placeName: 'Test Place',
        placeAddress: 'Kuala Lumpur',
        placeLatitude: 3.139,
        placeLongitude: 101.6869,
        placeRating: 4.5,
        placeTotalReviews: 120,
        businessStatus: 'OPERATIONAL',
        placeTypes: ['tourist_attraction'],
        destinationId: 'D001',
        hotspotId: 'H001',
      );

      final payload = PlaceDto.fromEntity(place).toJsonForRemote();

      expect(payload['id'], 'ChIJ-test-place');
      expect(payload['place_id'], 'ChIJ-test-place');
      expect(payload, isNot(contains('user_ratings_total')));
      expect(payload, isNot(contains('business_status')));
      expect(payload, isNot(contains('destination_id')));
      expect(payload, isNot(contains('hotspot_id')));
    });
  });

  group('BookmarkDTO nullable item ID', () {
    test('keeps a place-backed Supabase bookmark item ID null', () {
      final dto = BookmarkDTO.fromSupabase({
        'id': 'bookmark-1',
        'user_id': 'user-1',
        'item_id': null,
        'item_type': 'attraction',
        'place_id': 'place-1',
      });

      expect(dto.itemId, isNull);
      expect(dto.toRemoteMap(), isNot(contains('item_id')));
    });
  });
}
