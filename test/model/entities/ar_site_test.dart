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
}
