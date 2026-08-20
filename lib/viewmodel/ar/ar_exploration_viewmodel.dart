import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../model/business_logic/ar_exploration_service/ar_exploration_service.dart';
import '../../model/business_logic/shared_services/location_service.dart';
import '../../model/entities/ar_object.dart';
import '../../model/repositories/adapters/ar_repository_adapter.dart';
import '../../model/repositories/interfaces/ar_repository.dart';

enum ARViewState { idle, checkingPermissions, permissionDenied, loading, ready, error }

/// ViewModel for the AR Exploration screen (UC100 BF-1 through BF-7,
/// notification banner intentionally omitted per current scope).
class ARExplorationViewModel extends ChangeNotifier {
  final LocationService _locationService;
  final ARExplorationService _explorationService;

  ARExplorationViewModel({
    ARRepository? repository,
    LocationService? locationService,
  })  : _locationService = locationService ?? LocationService(),
        _explorationService = ARExplorationService(
          repository: repository ?? SupabaseARRepositoryAdapter(),
          locationService: locationService,
        );

  ARViewState state = ARViewState.idle;
  String? errorMessage;

  List<ARMarker> nearbyMarkers = [];
  ARMarker? primaryMarker;
  double deviceHeadingDegrees = 0;

  StreamSubscription<ARSceneState>? _sceneSub;

  /// UC100 BF-1 -> BF-7 entry point. Call from the View's initState.
  Future<void> init() async {
    state = ARViewState.checkingPermissions;
    notifyListeners();

    // [C1] [A1] Permission Denied
    final permissionState = await _locationService.checkAndRequestPermissions();
    if (permissionState != PermissionState.granted) {
      state = ARViewState.permissionDenied;
      errorMessage = switch (permissionState) {
        PermissionState.cameraDenied => 'Camera access is required to use the AR feature.',
        PermissionState.locationDenied => 'Location access is required to use the AR feature.',
        PermissionState.bothDenied => 'Camera and Location access are required to use the AR feature.',
        PermissionState.granted => null,
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

  void _onScene(ARSceneState scene) {
    nearbyMarkers = scene.nearbyMarkers;
    primaryMarker = scene.primaryMarker;
    deviceHeadingDegrees = scene.deviceHeadingDegrees;
    notifyListeners();
  }

  @override
  void dispose() {
    _sceneSub?.cancel();
    _explorationService.dispose();
    super.dispose();
  }
}
