import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of [LocationService.checkPermissions] — UC100 BF-2 / A1.
enum PermissionState { granted, cameraDenied, locationDenied, bothDenied }

/// Shared GPS + permission handling. Lives in `shared_services` (not
/// `ar_exploration_service`) because Itinerary and Recommendation also
/// need the tourist's location later.
class LocationService {
  /// [C1] Hardware & Permission Mandate — AR scanning must stay disabled
  /// unless BOTH Camera and Fine Location are granted.
  Future<PermissionState> checkAndRequestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    final cameraOk = cameraStatus.isGranted;
    final locationOk = locationStatus.isGranted;

    if (cameraOk && locationOk) return PermissionState.granted;
    if (!cameraOk && !locationOk) return PermissionState.bothDenied;
    if (!cameraOk) return PermissionState.cameraDenied;
    return PermissionState.locationDenied;
  }

  Future<bool> hasCameraAndLocationPermission() async {
    final camera = await Permission.camera.status;
    final location = await Permission.locationWhenInUse.status;
    return camera.isGranted && location.isGranted;
  }

  /// [REQ_101_2] One-shot fetch of GPS latitude/longitude/altitude.
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Continuous position stream, used to keep re-evaluating nearby
  /// markers as the tourist walks around.
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
