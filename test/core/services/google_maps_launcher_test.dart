import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/services/google_maps_launcher.dart';

void main() {
  test(
    'builds a Google Maps directions URL with exact destination identity',
    () {
      final uri = GoogleMapsLauncher.directionsUri(
        destinationName: 'Petronas Twin Towers',
        latitude: 3.1579,
        longitude: 101.7116,
        googlePlaceId: 'ChIJ-test-place',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['destination'], '3.1579,101.7116');
      expect(uri.queryParameters['destination_place_id'], 'ChIJ-test-place');
    },
  );
}
