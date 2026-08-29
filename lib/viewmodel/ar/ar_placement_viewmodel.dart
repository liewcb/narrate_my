import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_plus/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_plus/models/ar_node.dart';
import 'package:ar_flutter_plugin_plus/models/ar_hittest_result.dart';
import '../../model/entities/ar_object.dart';
import '../../model/entities/ar_placement.dart';
import '../../model/business_logic/ar_placement_service/ar_placement_service.dart';

/// ViewModel corresponding to `ARPlacementVM` in the architecture diagram.
/// Manages ARCore session lifecycle, plane hit-testing, model placement,
/// and storytelling narration state machine.
class ARPlacementViewModel extends ChangeNotifier {
  final ARPlacementService _placementService;

  ARPlacementViewModel({
    ARPlacementService? placementService,
  }) : _placementService = placementService ?? ARPlacementService();

  // --- State Variables ---
  PlacementState _placementState = PlacementState.initializing;
  ARMarker? _selectedMarker;
  ARAvatarConfig? _avatarConfig;

  bool _isAvatarPlaced = false;
  bool _isModelLoading = false;
  bool _show3DLandmarkModel = false;
  bool _showVideoPlayer = false;
  bool _hasStartedStorytelling = false;

  String _currentSubtitle = "";
  StoryPlaybackState _playbackState = StoryPlaybackState.stopped;
  String? _errorMessage;

  // AR Managers & Node references
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;
  final List<ARNode> _nodes = [];
  final List<ARPlaneAnchor> _anchors = [];

  StreamSubscription<String>? _subtitleSub;
  StreamSubscription<StoryPlaybackState>? _playbackSub;

  // --- Getters ---
  PlacementState get placementState => _placementState;
  ARMarker? get selectedMarker => _selectedMarker;
  String get landmarkName =>
      _placementService.narrationService.currentScript?.landmarkName ??
          _selectedMarker?.name ??
          "Landmark";
  String? get model3dPath =>
      _placementService.narrationService.currentScript?.model3dPath;
  String? get videoUrl =>
      _placementService.narrationService.currentScript?.videoUrl;
  StoryScript? get currentScript => _placementService.narrationService.currentScript;

  bool get isAvatarPlaced => _isAvatarPlaced;
  bool get isModelLoading => _isModelLoading;
  bool get show3DLandmarkModel => _show3DLandmarkModel;
  bool get showVideoPlayer => _showVideoPlayer;
  bool get hasStartedStorytelling => _hasStartedStorytelling;
  String get currentSubtitle => _currentSubtitle;
  TTSLanguageOption get currentLanguage => _placementService.narrationService.currentLanguage;
  StoryPlaybackState get playbackState => _playbackState;
  bool get isPlaying => _playbackState == StoryPlaybackState.playing;
  String? get errorMessage => _errorMessage;

  /// Initializes the ViewModel with the selected marker
  Future<void> init(ARMarker? marker) async {
    _selectedMarker = marker;
    _placementState = PlacementState.initializing;
    notifyListeners();

    // 1. Prepare/cache avatar GLB config in parallel
    _avatarConfig = await _placementService.modelService.prepareAvatarConfig();

    // 2. Load narration script into PlayNarrationService from Supabase / Marker
    final markerId = marker?.markerId ?? 'default_marker';
    final name = marker?.name ?? 'Landmark';
    await _placementService.narrationService.loadScriptForMarker(markerId, name);

    // 3. Subscribe to narration streams
    _subtitleSub?.cancel();
    _subtitleSub = _placementService.narrationService.subtitleStream.listen((sub) {
      _currentSubtitle = sub;
      notifyListeners();
    });

    _playbackSub?.cancel();
    _playbackSub = _placementService.narrationService.stateStream.listen((state) {
      _playbackState = state;
      notifyListeners();
    });

    _currentSubtitle = _placementService.narrationService.currentScript?.initialGreeting ?? "";
    _placementState = PlacementState.scanning;
    notifyListeners();

    // NOTE: no longer eagerly preloading the landmark 3D model here.
    // ModelViewer (model_viewer_plus) doesn't read through Flutter's
    // asset bundle at all — it copies the asset out and serves it to its
    // own WebView via a local server, so `rootBundle.load()` gave zero
    // benefit to that path. Meanwhile, for a model the size of klcc.glb
    // (~25MB vs. manja.glb's ~7MB), reading the whole thing into memory
    // on the same isolate that's driving ARKit's live camera/plane
    // detection was a real cost with no payoff — the likely cause of the
    // "freeze a couple seconds, resume, repeat" stutter seen while
    // scanning for a placement surface on iOS. The model now only loads
    // when the tourist actually taps Play, via ModelViewer itself.
  }

  /// Called when ARView native surface is created
  void onARViewCreated(
      ARSessionManager sessionManager,
      ARObjectManager objectManager,
      ARAnchorManager anchorManager,
      ARLocationManager locationManager,
      ) {
    arSessionManager = sessionManager;
    arObjectManager = objectManager;
    arAnchorManager = anchorManager;

    arSessionManager!.onInitialize(
      showFeaturePoints: true,
      showPlanes: true,
      showWorldOrigin: false,
      handleTaps: true,
    );
    arObjectManager!.onInitialize();
    arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTap;
  }

  /// Handles user tapping on detected horizontal planes
  Future<void> onPlaneOrPointTap(List<ARHitTestResult> hitTestResults) async {
    if (hitTestResults.isEmpty || _isAvatarPlaced || _isModelLoading) return;

    // Strict Real-AR filter: Only place on detected horizontal ground planes (no walls/points)
    final singleHitTest = _placementService.selectBestHitTest(hitTestResults);
    if (singleHitTest == null || arAnchorManager == null || arObjectManager == null) {
      return;
    }

    _isModelLoading = true;
    _placementState = PlacementState.placing;
    notifyListeners();

    try {
      final newAnchor = _placementService.createAnchor(singleHitTest);
      final didAddAnchor = await arAnchorManager!.addAnchor(newAnchor);

      if (didAddAnchor == true) {
        _anchors.add(newAnchor);

        final config = _avatarConfig ?? ARAvatarConfig.defaultManja();
        final newNode = _placementService.createAvatarNode(
          config,
          distanceMeters: singleHitTest.distance,
        );

        final didAddNode = await arObjectManager!.addNode(newNode, planeAnchor: newAnchor);
        if (didAddNode == true) {
          _nodes.add(newNode);

          // Performance Optimization: Disable plane detection and feature points after placement to save GPU overhead
          arSessionManager?.onInitialize(
            showPlanes: false,
            showFeaturePoints: false,
            handleTaps: false,
          );

          _isAvatarPlaced = true;
          _placementState = PlacementState.placed;
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to place avatar: $e';
      _placementState = PlacementState.error;
    } finally {
      _isModelLoading = false;
      notifyListeners();
    }
  }

  // --- Storytelling & 3D Model Flow ---

  /// Opens the Storytelling flow (Initial state: Play button visible, 3D model hidden)
  void openStorytellingMenu() {
    _hasStartedStorytelling = true;
    _playbackState = StoryPlaybackState.stopped;
    _show3DLandmarkModel = false; 
    _currentSubtitle = _placementService.narrationService.currentScript?.initialGreeting ??
        "Hello! I'm Manja! (Tap Play below to begin)";
    notifyListeners();
  }

  /// Toggles between Play and Pause for landmark narration
  void togglePlayPause() {
    if (_playbackState == StoryPlaybackState.playing) {
      _placementService.narrationService.pause();
    } else {
      _hasStartedStorytelling = true;
      _show3DLandmarkModel = true; // 3D model only appears after user taps Play / Resume
      _placementService.narrationService.play();
    }
  }

  /// Pauses active narration without resetting state
  void pauseStorytelling() {
    if (_playbackState == StoryPlaybackState.playing) {
      _placementService.narrationService.pause();
    }
  }

  /// Stops narration and resets
  void stopStorytelling() {
    _placementService.narrationService.stop();
    _hasStartedStorytelling = false;
    _show3DLandmarkModel = false;
    _currentSubtitle = "";
    notifyListeners();
  }

  /// Toggles the In-App Video Player Overlay
  void setVideoPlayerVisible(bool visible) {
    _showVideoPlayer = visible;
    notifyListeners();
  }

  double _currentYawDegrees = 0.0;

  /// Rotates the placed AR Avatar by delta degrees (e.g. +45, -45, or 180 degrees)
  Future<void> rotateAvatar([double deltaDegrees = 45.0]) async {
    if (_nodes.isEmpty || _anchors.isEmpty || arObjectManager == null) return;

    _currentYawDegrees = (_currentYawDegrees + deltaDegrees) % 360;
    final oldNode = _nodes.first;
    final currentAnchor = _anchors.first;

    try {
      await arObjectManager!.removeNode(oldNode);
      _nodes.clear();

      final baseConfig = _avatarConfig ?? ARAvatarConfig.defaultManja();
      final updatedConfig = baseConfig.copyWithRotation(_currentYawDegrees);
      final newNode = _placementService.createAvatarNode(updatedConfig);

      final didAdd = await arObjectManager!.addNode(newNode, planeAnchor: currentAnchor);
      if (didAdd == true) {
        _nodes.add(newNode);
      }
    } catch (e) {
      debugPrint("Rotate avatar error: $e");
    }
    notifyListeners();
  }

  /// Turns the Avatar 180 degrees to face the opposite direction / face user
  Future<void> turn180() => rotateAvatar(180.0);

  /// Toggles the 3D Landmark Model viewer
  void toggle3DModelViewer() {
    _show3DLandmarkModel = !_show3DLandmarkModel;
    notifyListeners();
  }

  @override
  void dispose() {
    _subtitleSub?.cancel();
    _playbackSub?.cancel();

    // Release native AR resources safely to prevent memory leaks and Camera2 hardware conflicts
    try {
      arSessionManager?.onPlaneOrPointTap = (_) {};
      for (final node in _nodes) {
        arObjectManager?.removeNode(node);
      }
      _nodes.clear();

      for (final anchor in _anchors) {
        arAnchorManager?.removeAnchor(anchor);
      }
      _anchors.clear();

      arSessionManager?.dispose();
    } catch (e) {
      debugPrint("Error disposing AR resources: $e");
    }

    _placementService.dispose();
    super.dispose();
  }
}