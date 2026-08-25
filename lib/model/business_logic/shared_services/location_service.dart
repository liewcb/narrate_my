import 'package:geolocator/geolocator.dart';

class LocationService {
  /// [REQ_101_2] One-shot fetch of GPS latitude/longitude/altitude.
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Continuous position stream, used to keep re-evaluating nearby
  /// markers/attractions as the tourist moves around.
  Stream<Position> watchPosition({int distanceFilterMeters = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    );
  }

  Future<bool> isLocationServiceEnabled() => Geolocator.isLocationServiceEnabled();
}