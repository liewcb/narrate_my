import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/entities/recommendation.dart';

void main() {
  test(
    'round-trips a resolved recommendation through the phone cache JSON',
    () {
      const recommendation = Recommendation(
        placeId: 'place-123',
        name: 'National Museum',
        category: 'Museum',
        address: 'Kuala Lumpur',
        reason: 'Matches the tourist’s heritage interests.',
        rank: 1,
        latitude: 3.1379,
        longitude: 101.687,
        imageUrl: 'https://example.com/museum.jpg',
        rating: 4.6,
        distanceKm: 2.4,
        estimatedTravelMinutes: 5,
      );

      final restored = Recommendation.fromJson(recommendation.toJson());

      expect(restored.placeId, recommendation.placeId);
      expect(restored.name, recommendation.name);
      expect(restored.category, recommendation.category);
      expect(restored.address, recommendation.address);
      expect(restored.reason, recommendation.reason);
      expect(restored.rank, recommendation.rank);
      expect(restored.latitude, recommendation.latitude);
      expect(restored.longitude, recommendation.longitude);
      expect(restored.imageUrl, recommendation.imageUrl);
      expect(restored.rating, recommendation.rating);
      expect(restored.distanceKm, recommendation.distanceKm);
      expect(
        restored.estimatedTravelMinutes,
        recommendation.estimatedTravelMinutes,
      );
    },
  );
}
