import 'package:permission_handler/permission_handler.dart';
import 'app_service.dart';

/// Generic permission checking — camera, location, and anything else the
/// app needs later. Not AR-specific: any module can ask for just the
/// permission(s) it actually needs instead of a one-size-fits-all check.
class PermissionService extends AppService {
  @override
  Future<void> init() async {
    // Nothing to initialize eagerly — permissions are requested on demand.
  }

  Future<bool> hasCameraPermission() async => (await Permission.camera.status).isGranted;

  Future<bool> hasLocationPermission() async =>
      (await Permission.locationWhenInUse.status).isGranted;

  Future<PermissionStatus> requestCamera() => Permission.camera.request();

  Future<PermissionStatus> requestLocation() => Permission.locationWhenInUse.request();

  Future<void> openSettings() => openAppSettings();
}

/// Result of a combined camera + location check — used by AR specifically
/// (UC100 [C1] Hardware & Permission Mandate: AR scanning needs BOTH).
/// Other modules that only need location should call
/// [PermissionService.requestLocation] directly instead of this.
enum CameraAndLocationPermissionState { granted, cameraDenied, locationDenied, bothDenied }

extension ARPermissions on PermissionService {
  Future<CameraAndLocationPermissionState> requestCameraAndLocation() async {
    final cameraStatus = await requestCamera();
    final locationStatus = await requestLocation();

    final cameraOk = cameraStatus.isGranted;
    final locationOk = locationStatus.isGranted;

    if (cameraOk && locationOk) return CameraAndLocationPermissionState.granted;
    if (!cameraOk && !locationOk) return CameraAndLocationPermissionState.bothDenied;
    if (!cameraOk) return CameraAndLocationPermissionState.cameraDenied;
    return CameraAndLocationPermissionState.locationDenied;
  }
}