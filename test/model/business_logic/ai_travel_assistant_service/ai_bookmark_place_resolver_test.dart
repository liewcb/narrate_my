import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/business_logic/ai_travel_assistant_service/ai_bookmark_place_resolver.dart';
import 'package:narrate_my/model/entities/coordinates.dart';
import 'package:narrate_my/model/entities/place.dart';

void main() {
  const suria = Place(
    placeId: 'suria-klcc',
    placeName: 'Suria KLCC Shopping Mall',
    placeAddress: 'Kuala Lumpur City Centre',
    placeLatitude: 3.1579,
    placeLongitude: 101.7123,
    placeRating: 4.6,
    placeTypes: ['shopping_mall', 'tourist_attraction'],
  );
  const aquaria = Place(
    placeId: 'aquaria-klcc',
    placeName: 'Aquaria KLCC',
    placeAddress: 'Kuala Lumpur Convention Centre',
    placeLatitude: 3.1534,
    placeLongitude: 101.7131,
    placeRating: 4.5,
    placeTypes: ['aquarium', 'tourist_attraction'],
  );
  const klccRestaurant = Place(
    placeId: 'klcc-restaurant',
    placeName: 'KLCC Restaurant',
    placeAddress: 'Kuala Lumpur City Centre',
    placeLatitude: 3.1585,
    placeLongitude: 101.713,
    placeRating: 4.4,
    placeTypes: ['restaurant', 'food'],
  );
  const penangRestaurant = Place(
    placeId: 'penang-restaurant',
    placeName: 'Penang Restaurant',
    placeAddress: 'George Town, Penang',
    placeLatitude: 5.4145,
    placeLongitude: 100.329,
    placeRating: 4.8,
    placeTypes: ['restaurant', 'food'],
  );
  const penangBridge = Place(
    placeId: 'google-penang-bridge',
    placeName: 'Penang Bridge',
    placeAddress: 'Penang, Malaysia',
    placeLatitude: 5.3544,
    placeLongitude: 100.315,
    placeRating: 4.5,
    placeTypes: ['point_of_interest', 'establishment'],
  );
  const aFamosa = Place(
    placeId: 'google-a-famosa',
    placeName: 'A Famosa',
    placeAddress: 'Bandar Hilir, Melaka, Malaysia',
    placeLatitude: 2.1919,
    placeLongitude: 102.2504,
    placeRating: 4.4,
    placeTypes: ['tourist_attraction', 'point_of_interest'],
  );

  test('extra descriptive words still resolve the named attraction', () async {
    final resolver = AiBookmarkPlaceResolver(
      knownPlacesLoader: () async => const [suria, aquaria],
    );

    final result = await resolver.resolveQuestion('Suria KLCC nice?');

    expect(result, const [suria]);
  });

  test('where is and where contraction resolve identical bookmarks', () async {
    final contractionResolver = AiBookmarkPlaceResolver(
      knownPlacesLoader: () async => const [suria, aquaria],
    );
    final fullWordingResolver = AiBookmarkPlaceResolver(
      knownPlacesLoader: () async => const [suria, aquaria],
    );

    final contraction = await contractionResolver.resolveQuestion(
      "Where's KLCC?",
    );
    final fullWording = await fullWordingResolver.resolveQuestion(
      'Where is KLCC?',
    );

    expect(fullWording, contraction);
    expect(fullWording, isNotEmpty);
  });

  test(
    'direct bridge name uses verified server search when database has no row',
    () async {
      String? receivedQuery;
      final resolver = AiBookmarkPlaceResolver(
        knownPlacesLoader: () async => const [aFamosa],
        textPlaceLoader: ({required query}) async {
          receivedQuery = query;
          return const [aFamosa, penangBridge];
        },
      );

      final result = await resolver.resolveQuestion('penang bridge');

      expect(receivedQuery, 'penang bridge');
      expect(result, const [penangBridge]);
    },
  );

  test('Malay direct-place wording resolves a verified bookmark', () async {
    final resolver = AiBookmarkPlaceResolver(
      knownPlacesLoader: () async => const [],
      textPlaceLoader: ({required query}) async => const [suria],
    );

    final result = await resolver.resolveQuestion('Di mana Suria KLCC?');

    expect(result, const [suria]);
  });

  test('Mandarin direct-place wording resolves a verified bookmark', () async {
    final resolver = AiBookmarkPlaceResolver(
      knownPlacesLoader: () async => const [],
      textPlaceLoader: ({required query}) async => const [penangBridge],
    );

    final result = await resolver.resolveQuestion('槟城大桥在哪里？');

    expect(result, const [penangBridge]);
  });

  test(
    'Mandarin want-to-visit wording searches only the canonical place terms',
    () async {
      String? receivedQuery;
      final resolver = AiBookmarkPlaceResolver(
        knownPlacesLoader: () async => const [],
        textPlaceLoader: ({required query}) async {
          receivedQuery = query;
          return const [suria];
        },
      );

      final result = await resolver.resolveQuestion('我想去suria klcc');

      expect(receivedQuery, 'suria klcc Malaysia');
      expect(result, const [suria]);
    },
  );

  test('near me does not load unrelated database places', () async {
    var loadCount = 0;
    final resolver = AiBookmarkPlaceResolver(
      knownPlacesLoader: () async {
        loadCount++;
        return const [suria, aquaria];
      },
    );

    final result = await resolver.resolveQuestion('Any drinks near by me?');

    expect(result, isEmpty);
    expect(loadCount, 0);
  });

  test('nearby results are filtered around the supplied origin', () async {
    final resolver = AiBookmarkPlaceResolver(
      nearbyPlaceLoader:
          ({
            required origin,
            required includedTypes,
            required radiusKm,
          }) async => throw Exception('Google unavailable in unit test'),
      knownPlacesLoader: () async => const [klccRestaurant, penangRestaurant],
    );

    final nearKlcc = await resolver.resolveQuestion(
      'Show restaurants nearby',
      nearbyOrigin: const Coordinates(latitude: 3.1579, longitude: 101.7123),
    );
    final nearUser = await resolver.resolveQuestion(
      'Show restaurants nearby me',
      nearbyOrigin: const Coordinates(latitude: 5.4141, longitude: 100.3288),
    );

    expect(nearKlcc, const [klccRestaurant]);
    expect(nearUser, const [penangRestaurant]);
  });

  test('scoped restaurant discovery prefers verified Google results', () async {
    Coordinates? receivedOrigin;
    List<String>? receivedTypes;
    final resolver = AiBookmarkPlaceResolver(
      nearbyPlaceLoader:
          ({required origin, required includedTypes, required radiusKm}) async {
            receivedOrigin = origin;
            receivedTypes = includedTypes;
            return const [klccRestaurant];
          },
      knownPlacesLoader: () async => const [penangRestaurant],
    );
    const origin = Coordinates(latitude: 3.1579, longitude: 101.7123);

    final result = await resolver.resolveQuestion(
      'Any restaurants nearby this place?',
      nearbyOrigin: origin,
    );

    expect(result, const [klccRestaurant]);
    expect(receivedOrigin, origin);
    expect(receivedTypes, const ['restaurant']);
  });
}
