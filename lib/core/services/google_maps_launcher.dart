import 'package:url_launcher/url_launcher.dart';

/// Opens turn-by-turn directions using the same Google Maps URL format as the
/// Travel Assistant. Keeping this outside either screen lets recommendation,
/// AR and AI surfaces share one safe implementation.
class GoogleMapsLauncher {
  const GoogleMapsLauncher._();

  static Uri directionsUri({
    required String destinationName,
    required double latitude,
    required double longitude,
    String? googlePlaceId,
  }) {
    final hasCoordinates = latitude != 0 && longitude != 0;
    final parameters = <String, String>{
      'api': '1',
      'destination': hasCoordinates
          ? '$latitude,$longitude'
          : destinationName.trim(),
    };
    final placeId = googlePlaceId?.trim();
    if (placeId != null && placeId.isNotEmpty) {
      parameters['destination_place_id'] = placeId;
    }
    return Uri.https('www.google.com', '/maps/dir/', parameters);
  }

  static Future<bool> openDirections({
    required String destinationName,
    required double latitude,
    required double longitude,
    String? googlePlaceId,
  }) async {
    try {
      return await launchUrl(
        directionsUri(
          destinationName: destinationName,
          latitude: latitude,
          longitude: longitude,
          googlePlaceId: googlePlaceId,
        ),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
