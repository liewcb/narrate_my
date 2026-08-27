import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/services/permission_service.dart';
import '../../model/business_logic/ar_exploration_service/ar_exploration_service.dart';
import '../../model/business_logic/shared_services/location_service.dart';
import '../../core/services/orientation_service.dart';
import '../../model/entities/ar_object.dart';
import '../../model/repositories/adapters/ar_repository_adapter.dart';
import '../../model/repositories/interfaces/ar_repository.dart';

enum ARViewState { idle, checkingPermissions, permissionDenied, loading, ready, error }

/// ViewModel for the AR Exploration screen (UC100 BF-1 through BF-7).
class ARExplorationViewModel extends ChangeNotifier {
  final PermissionService _permissionService;
  final ARExplorationService _explorationService;

  ARExplorationViewModel({
    ARRepository? repository,
    PermissionService? permissionService,
    LocationService? locationService,
    OrientationService? orientationService,
  })  : _permissionService = permissionService ?? PermissionService(),
        _explorationService = ARExplorationService(
          repository: repository ?? SupabaseARRepositoryAdapter(),
          locationService: locationService,
          orientationService: orientationService,
        );

  ARViewState state = ARViewState.idle;
  String? errorMessage;

  List<ARMarker> nearbyMarkers = [];
  ARMarker? primaryMarker;
  double deviceHeadingDegrees = 0;
  double devicePitchDegrees = 0;

  // --- Diagnostics for the debug HUD ---
  double? userLat;
  double? userLng;
  int rawFetchedCount = 0;
  List<ARMarker> allComputedMarkers = [];

  StreamSubscription<ARSceneState>? _sceneSub;

  /// UC100 BF-1 -> BF-7 entry point. Call from the View's initState.
  Future<void> init() async {
    state = ARViewState.checkingPermissions;
    notifyListeners();

    // [C1] [A1] Permission Denied — AR specifically needs BOTH camera and
    // location, unlike other modules which will only ever ask for location.
    final permissionState = await _permissionService.requestCameraAndLocation();
    if (permissionState != CameraAndLocationPermissionState.granted) {
      state = ARViewState.permissionDenied;
      errorMessage = switch (permissionState) {
        CameraAndLocationPermissionState.cameraDenied =>
        'Camera access is required to use the AR feature.',
        CameraAndLocationPermissionState.locationDenied =>
        'Location access is required to use the AR feature.',
        CameraAndLocationPermissionState.bothDenied =>
        'Camera and Location access are required to use the AR feature.',
        CameraAndLocationPermissionState.granted => null,
      };
      notifyListeners();
      return;
    }

    state = ARViewState.loading;
    notifyListeners();

    try {
      _sceneSub = _explorationService.sceneStream.listen(_onScene);
      await _explorationService.start();
      state = ARViewState.ready;
    } catch (e) {
      state = ARViewState.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Re-run the permission check after the tourist returns from Settings
  /// (A1: "If the tourist grants permission, return to BF-3").
  Future<void> retryAfterPermissionGranted() => init();

  /// Stops the GPS/compass/accelerometer streams without disposing this
  /// ViewModel. Call this before pushing into AR Placement — that screen
  /// starts its own ARCore/ARKit session, which needs exclusive,
  /// uncontended access to the device's accelerometer/gyroscope for its
  /// own real-time IMU fusion. Leaving this screen's streams running
  /// underneath (which `Navigator.push` does, since it doesn't dispose
  /// the widget it's pushed from) registers a second accelerometer
  /// listener alongside ARCore's own — on some devices that's enough to
  /// cause ARCore's internal IMU buffer to fall behind and stutter
  /// (visible in logcat as "IMU buffer beyond maximum size... Removing
  /// the first 1 element(s)" / "Callback list for SENSOR_TYPE_
  /// ACCELEROMETER ... not found").
  void pause() {
    _explorationService.stop();
  }

  /// Restarts the streams after returning from AR Placement.
  Future<void> resume() => _explorationService.start();

  void _onScene(ARSceneState scene) {
    nearbyMarkers = scene.nearbyMarkers;
    primaryMarker = scene.primaryMarker;
    deviceHeadingDegrees = scene.deviceHeadingDegrees;
    devicePitchDegrees = scene.devicePitchDegrees;
    userLat = scene.userLat;
    userLng = scene.userLng;
    rawFetchedCount = scene.rawFetchedCount;
    allComputedMarkers = scene.allComputedMarkers;
    notifyListeners();
  }

  @override
  void dispose() {
    _sceneSub?.cancel();
    _explorationService.dispose();
    super.dispose();
  }
}