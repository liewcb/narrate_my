import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/entities/ar_site.dart';

const _site = ARSite(
  siteId: 'ARS_KLCC_TOWERS',
  name: 'Petronas Twin Towers',
  latitude: 3.1579,
  longitude: 101.7116,
  googlePlaceIds: ['google-klcc'],
  matchAliases: ['KLCC Skybridge'],
  matchRadiusMeters: 250,
  experiences: [
    ARSiteExperience(
      attractionId: 'AD003',
      markerId: 'MK003',
      name: 'KLCC Skybridge',
      latitude: 3.1579,
      longitude: 101.7116,
      activationRadiusMeters: 100,
    ),
  ],
);

void main() {
  group('ARSite matching', () {
    test('uses an exact Google Place ID regardless of display name', () {
      expect(
        _site.matchesPlace(
          googlePlaceId: 'google-klcc',
          placeName: 'Different localized name',
          placeLatitude: 0,
          placeLongitude: 0,
        ),
        isTrue,
      );
    });

    test('uses a nearby configured alias when no Google ID is configured', () {
      expect(
        _site.matchesPlace(
          googlePlaceId: 'another-id',
          placeName: 'Visit the KLCC Skybridge',
          placeLatitude: 3.1579,
          placeLongitude: 101.7116,
        ),
        isTrue,
      );
    });

    test('does not merge a similarly named place outside the site radius', () {
      expect(
        _site.matchesPlace(
          googlePlaceId: 'another-id',
          placeName: 'KLCC Skybridge',
          placeLatitude: 3.2,
          placeLongitude: 101.75,
        ),
        isFalse,
      );
    });
  });

  test('unlocks AR only inside an experience activation radius', () {
    expect(_site.canOpenArAt(3.1579, 101.7116), isTrue);
    expect(_site.canOpenArAt(3.17, 101.72), isFalse);
  });

  test('groups unassigned experiences sharing one Marker into one site', () {
    final sites = groupUngroupedARExperiences(const [
      ARSiteExperience(
        attractionId: 'AD100',
        markerId: 'MK100',
        name: 'Tower Ground Floor',
        latitude: 3.1,
        longitude: 101.7,
        activationRadiusMeters: 80,
      ),
      ARSiteExperience(
        attractionId: 'AD101',
        markerId: 'MK100',
        name: 'Tower Upper Floor',
        latitude: 3.1,
        longitude: 101.7,
        activationRadiusMeters: 120,
      ),
    ]);

    expect(sites, hasLength(1));
    expect(sites.single.siteId, 'UNLINKED_MK100');
    expect(sites.single.experiences, hasLength(2));
    expect(sites.single.matchRadiusMeters, 150);
  });

  group('Nearby exact-coordinate grouping', () {
    test('combines different attractions at exactly equal coordinates', () {
      final sites = groupNearbyARExperiencesByExactCoordinates(const [
        ARSiteExperience(
          attractionId: 'AD002',
          markerId: 'MK002',
          name: 'Tower 2 — Visitor Tower',
          latitude: 3.1578,
          longitude: 101.7114,
          activationRadiusMeters: 100,
        ),
        ARSiteExperience(
          attractionId: 'AD007',
          markerId: 'MK007',
          name: 'Observation Deck (Level 86)',
          latitude: 3.1578,
          longitude: 101.7114,
          activationRadiusMeters: 120,
        ),
      ]);

      expect(sites, hasLength(1));
      expect(sites.single.experiences, hasLength(2));
      expect(
        sites.single.name,
        'Tower 2 — Visitor Tower / Observation Deck (Level 86)',
      );
      expect(
        sites.single.experiences.map((experience) => experience.name),
        containsAll(['Tower 2 — Visitor Tower', 'Observation Deck (Level 86)']),
      );
    });

    test('keeps attractions separate when coordinates are only nearby', () {
      final sites = groupNearbyARExperiencesByExactCoordinates(const [
        ARSiteExperience(
          attractionId: 'AD100',
          markerId: 'MK100',
          name: 'First attraction',
          latitude: 3.1578,
          longitude: 101.7114,
          activationRadiusMeters: 100,
        ),
        ARSiteExperience(
          attractionId: 'AD101',
          markerId: 'MK101',
          name: 'Second attraction',
          latitude: 3.15781,
          longitude: 101.7114,
          activationRadiusMeters: 100,
        ),
      ]);

      expect(sites, hasLength(2));
      expect(sites.every((site) => site.experiences.length == 1), isTrue);
    });

    test('enriches an exact-coordinate pin without grouping nearby pins', () {
      final sites = groupNearbyARExperiencesByExactCoordinates(
        const [
          ARSiteExperience(
            attractionId: 'AD200',
            parentSiteId: 'ARS_MUSEUM',
            markerId: 'MK200',
            name: 'Museum Gallery',
            latitude: 3.14,
            longitude: 101.69,
            activationRadiusMeters: 80,
          ),
        ],
        parentSitesById: const {
          'ARS_MUSEUM': ARSite(
            siteId: 'ARS_MUSEUM',
            name: 'Museum Parent Place',
            latitude: 3.14,
            longitude: 101.69,
            address: 'Museum Road',
            category: 'Museum',
            googlePlaceIds: ['google-museum'],
            matchAliases: ['National Museum'],
          ),
        },
      );

      expect(sites, hasLength(1));
      expect(sites.single.name, 'Museum Gallery');
      expect(sites.single.address, 'Museum Road');
      expect(sites.single.googlePlaceIds, ['google-museum']);
      expect(
        sites.single.matchAliases,
        containsAll([
          'Museum Parent Place',
          'National Museum',
          'Museum Gallery',
        ]),
      );
    });
  });
}
