import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:narrate_my/model/data_sources/remote/recommendation_places_remote_data_source.dart';

void main() {
  group('RecommendationPlacesRemoteDataSource', () {
    test('uses Places API New and parses recommendation place data', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'places': [
              {
                'id': 'place-123',
                'displayName': {'text': 'National Museum'},
                'formattedAddress': 'Kuala Lumpur, Malaysia',
                'location': {'latitude': 3.1379, 'longitude': 101.6870},
                'rating': 4.6,
                'photos': [
                  {'name': 'places/place-123/photos/photo-456'},
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final dataSource = RecommendationPlacesRemoteDataSource(
        apiKey: 'test-key',
        client: client,
      );

      final places = await dataSource.searchText(
        query: 'National Museum, Kuala Lumpur',
        latitude: 3.139,
        longitude: 101.687,
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.toString(),
        'https://places.googleapis.com/v1/places:searchText',
      );
      expect(capturedRequest.headers['x-goog-api-key'], 'test-key');
      expect(
        capturedRequest.headers['x-goog-fieldmask'],
        contains('places.id'),
      );
      expect(jsonDecode(capturedRequest.body)['textQuery'], contains('Museum'));
      expect(places, hasLength(1));
      expect(places.single.placeId, 'place-123');
      expect(places.single.name, 'National Museum');
      expect(places.single.latitude, closeTo(3.1379, 0.00001));
      expect(
        places.single.photoResourceName,
        'places/place-123/photos/photo-456',
      );
    });

    test('builds a Places API New photo URL', () {
      final dataSource = RecommendationPlacesRemoteDataSource(
        apiKey: 'test-key',
      );

      final url = dataSource.buildPhotoUrl(
        'places/place-123/photos/photo-456',
        maxWidth: 800,
      );

      expect(
        url,
        'https://places.googleapis.com/v1/places/place-123/photos/'
        'photo-456/media?maxWidthPx=800&key=test-key',
      );
    });

    test('returns the Places API error details', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'message': 'Places API (New) is not enabled for this key.',
              'status': 'PERMISSION_DENIED',
            },
          }),
          403,
        ),
      );
      final dataSource = RecommendationPlacesRemoteDataSource(
        apiKey: 'test-key',
        client: client,
      );

      expect(
        () => dataSource.searchText(
          query: 'Museum',
          latitude: 3.139,
          longitude: 101.687,
        ),
        throwsA(
          isA<RecommendationPlacesException>().having(
            (error) => error.message,
            'message',
            contains('not enabled'),
          ),
        ),
      );
    });
  });
}
