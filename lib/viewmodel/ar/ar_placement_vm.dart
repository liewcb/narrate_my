import 'dart:async';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
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
  final ValueChanged<bool>? onStorytellingActivityChanged;
  bool _disposed = false;

  ARPlacementViewModel({
    ARPlacementService? placementService,
    this.onStorytellingActivityChanged,
  }) : _placementService = placementService ?? ARPlacementService();

  // --- State Variables ---
  PlacementState _placementState = PlacementState.initializing;
  ARMarker? _selectedMarker;
  ARAvatarConfig? _avatarConfig;

  bool _isAvatarPlaced = false;
  bool _isPlaneDetected = false;
  bool _isModelLoading = false;
  bool _show3DLandmarkModel = false;
  bool _showVideoPlayer = false;
  bool _hasStartedStorytelling = false;
  bool _wasPlayingBeforeLock = false;

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
  StreamSubscription<String>? _errorSub;

  // --- Getters ---
  PlacementState get placementState => _placementState;
  ARMarker? get selectedMarker => _selectedMarker;
  String get landmarkName =>
      _placementService.narrationService.currentScript?.landmarkName ??
      _selectedMarker?.name ??
      "Landmark";
  String? get model3dPath =>
      _placementService.narrationService.currentScript?.model3dPath;
  bool get has3dModel =>
      model3dPath != null && model3dPath!.trim().isNotEmpty;
  String? get videoUrl =>
      _placementService.narrationService.currentScript?.videoUrl;
  String? get videoUrlBackup =>
      _placementService.narrationService.currentScript?.videoUrlBackup;
  StoryScript? get currentScript =>
      _placementService.narrationService.currentScript;

  bool get isAvatarPlaced => _isAvatarPlaced;
  bool get isPlaneDetected => _isPlaneDetected;
  bool get hasAvatarInScene => _nodes.isNotEmpty;
  bool get isModelLoading => _isModelLoading;
  bool get show3DLandmarkModel => _show3DLandmarkModel;
  bool get showVideoPlayer => _showVideoPlayer;
  bool get hasStartedStorytelling => _hasStartedStorytelling;
  String get currentSubtitle => _currentSubtitle;
  TTSLanguageOption get currentLanguage =>
      _placementService.narrationService.currentLanguage;
  StoryPlaybackState get playbackState => _playbackState;
  bool get isPlaying => _playbackState == StoryPlaybackState.playing;
  String? get errorMessage => _errorMessage;

  /// Initializes the ViewModel with the selected marker
  Future<void> init(ARMarker? marker) async {
    _selectedMarker = marker;
    _placementState = PlacementState.initializing;
    _errorMessage = null;
    _isAvatarPlaced = false;
    _isPlaneDetected = false;
    _show3DLandmarkModel = false;
    _showVideoPlayer = false;
    _hasStartedStorytelling = false;
    onStorytellingActivityChanged?.call(false);
    _playbackState = StoryPlaybackState.stopped;
    notifyListeners();

    try {
      // 1. Prepare/cache avatar GLB config in parallel
      _avatarConfig = await _placementService.modelService.prepareAvatarConfig();

      if (_disposed) return;

      // 2. Load narration script into PlayNarrationService from Supabase / Marker
      final markerId = marker?.markerId ?? 'default_marker';
      final name = marker?.name ?? 'Landmark';
      await _placementService.narrationService.loadScriptForMarker(
        markerId,
        name,
      );

      final script = _placementService.narrationService.currentScript;
      if (script == null || script.id.startsWith('error_')) {
        throw Exception(
          script?.initialGreeting.replaceFirst('Error: ', '') ??
              "Unable to retrieve attraction narration content for $name.",
        );
      }

      // Pre-warm the landmark 3D model asset in memory in the background for fast loading
      final landmarkGlb = script.model3dPath;
      if (landmarkGlb != null && landmarkGlb.startsWith('assets/')) {
        unawaited(rootBundle.load(landmarkGlb));
      }

      if (_disposed) return;

      // 3. Subscribe to narration streams
      _subtitleSub?.cancel();
      _subtitleSub = _placementService.narrationService.subtitleStream.listen((
        sub,
      ) {
        _currentSubtitle = sub;
        notifyListeners();
      });

      _playbackSub?.cancel();
      _playbackSub = _placementService.narrationService.stateStream.listen((
        state,
      ) {
        _playbackState = state;
        if (state == StoryPlaybackState.completed) {
          onStorytellingActivityChanged?.call(false);
        }
        notifyListeners();
      });

      _errorSub?.cancel();
      _errorSub = _placementService.narrationService.errorStream.listen((
        err,
      ) {
        if (_disposed) return;
        _placementState = PlacementState.error;
        _errorMessage = err;
        notifyListeners();
      });

      _currentSubtitle = script.initialGreeting;
      if (!_isAvatarPlaced && !_isModelLoading) {
        _placementState = PlacementState.scanning;
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Attraction content retrieval failed: $e");
      if (_disposed) return;
      _placementState = PlacementState.error;
      _errorMessage =
          "Attraction content retrieval or narration generation failed for ${marker?.name ?? 'this landmark'}. Please check your network connection and try again.";
      notifyListeners();
    }
  }

  /// Retries content retrieval and narration generation (REQ_201_6)
  Future<void> retryContentRetrieval() async {
    _placementState = PlacementState.initializing;
    _errorMessage = null;
    notifyListeners();
    await init(_selectedMarker);
  }

  /// Called when ARView native surface is created
  void onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    if (_disposed) return;
    arSessionManager = sessionManager;
    arObjectManager = objectManager;
    arAnchorManager = anchorManager;

    _nodes.clear();
    _anchors.clear();
    _isModelLoading = false;
    _currentYawDegrees = 0;
    arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTap;
    arSessionManager!.onPlaneDetected = () {
      if (_disposed) return;
      if (!_isPlaneDetected) {
        _isPlaneDetected = true;
        unawaited(arSessionManager?.hideCoachingOverlay());
        notifyListeners();
      }
    };
    unawaited(_initializeSession(sessionManager, objectManager));
  }

  Future<void> _initializeSession(
    ARSessionManager session,
    ARObjectManager objects,
  ) async {
    try {
      await session.onInitialize(
        showFeaturePoints: true,
        showPlanes: true,
        showWorldOrigin: false,
        handleTaps: true,
        showAnimatedGuide: false,
      );
      if (_disposed || arSessionManager != session) return;
      objects.onInitialize();

      _placementState = PlacementState.scanning;
      notifyListeners();
    } catch (e) {
      if (_disposed || arSessionManager != session) return;
      _errorMessage = 'Failed to initialize AR: $e';
      _placementState = PlacementState.error;
      notifyListeners();
    }
  }

  /// Resets AR placement and removes old drifted Manja node when returning from lockscreen,
  /// cleanly prompting user to scan surface and re-place Manja.
  void resetToScanningAfterLockscreen() {
    if (_disposed) return;
    for (final node in _nodes) {
      try {
        arObjectManager?.removeNode(node);
      } catch (_) {}
    }
    _nodes.clear();
    _anchors.clear();
    _isAvatarPlaced = false;
    _isPlaneDetected = false;
    _wasPlayingBeforeLock = _playbackState == StoryPlaybackState.playing;
    _show3DLandmarkModel = false;
    _isModelLoading = false;

    // Re-enable plane tapping so user can tap ground to place Manja:
    try {
      arSessionManager?.onInitialize(
        showPlanes: true,
        showFeaturePoints: true,
        handleTaps: true,
        showAnimatedGuide: false,
      );
    } catch (_) {}

    // Pause audio cleanly without wiping paragraph index or word offset:
    _placementService.narrationService.pause();
    _playbackState = StoryPlaybackState.paused;

    // Keep _hasStartedStorytelling intact so progress is never lost!
    if (!_hasStartedStorytelling) {
      _currentSubtitle =
          _placementService.narrationService.currentScript?.initialGreeting ??
          "";
    }
    _placementState = PlacementState.scanning;
    notifyListeners();
  }

  /// Safely pauses ARCore session when locking screen or sending to background
  Future<void> pauseARSession() async {
    if (_disposed || arSessionManager == null) return;
    try {
      await arSessionManager?.pause();
    } catch (e) {
      debugPrint("Error pausing AR session: $e");
    }
  }

  /// Safely resumes ARCore session without destroying the native view or anchors
  Future<void> resumeARSession() async {
    if (_disposed || arSessionManager == null) return;
    try {
      await arSessionManager?.resume();
    } catch (e) {
      debugPrint("Error resuming AR session: $e");
    }
  }

  /// Handles user tapping on detected horizontal planes
  Future<void> onPlaneOrPointTap(List<ARHitTestResult> hitTestResults) async {
    if (_disposed ||
        hitTestResults.isEmpty ||
        _nodes.isNotEmpty ||
        _isModelLoading) {
      return;
    }

    _isPlaneDetected = true;
    unawaited(arSessionManager?.hideCoachingOverlay());

    // Strict Real-AR filter: Only place on detected horizontal ground planes (no walls/points)
    final singleHitTest = _placementService.selectBestHitTest(hitTestResults);
    if (singleHitTest == null ||
        arAnchorManager == null ||
        arObjectManager == null) {
      return;
    }

    _isModelLoading = true;
    _placementState = PlacementState.placing;
    notifyListeners();

    try {
      final newAnchor = _placementService.createAnchor(singleHitTest);
      final didAddAnchor = await arAnchorManager!.addAnchor(newAnchor);

      if (_disposed) return;
      if (didAddAnchor == true) {
        _anchors.add(newAnchor);

        final config = _avatarConfig ?? ARAvatarConfig.defaultManja();
        final newNode = _placementService.createAvatarNode(
          config,
          distanceMeters: singleHitTest.distance,
        );

        final didAddNode = await arObjectManager!.addNode(
          newNode,
          planeAnchor: newAnchor,
        );
        if (_disposed) return;
        if (didAddNode == true) {
          _nodes.add(newNode);

          // Performance Optimization: Disable plane detection and feature points after placement to save GPU overhead
          await arSessionManager?.onInitialize(
            showPlanes: false,
            showFeaturePoints: false,
            handleTaps: false,
          );

          if (_disposed) return;
          _isAvatarPlaced = true;
          _placementState = PlacementState.placed;

          // Auto-resume storytelling from exact paused word/paragraph if user was listening before lock
          if (_hasStartedStorytelling && _wasPlayingBeforeLock) {
            _wasPlayingBeforeLock = false;
            Future.delayed(const Duration(milliseconds: 600), () {
              if (!_disposed &&
                  _isAvatarPlaced &&
                  _playbackState == StoryPlaybackState.paused) {
                togglePlayPause();
              }
            });
          }
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to place avatar: $e';
      _placementState = PlacementState.error;
    } finally {
      _isModelLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // --- Storytelling & 3D Model Flow ---

  /// Opens the Storytelling flow (Initial state: Play button visible, 3D model hidden)
  void openStorytellingMenu() {
    _hasStartedStorytelling = true;
    onStorytellingActivityChanged?.call(true);
    _playbackState = StoryPlaybackState.stopped;
    _show3DLandmarkModel = false;
    _currentSubtitle =
        _placementService.narrationService.currentScript?.initialGreeting ??
        "Hello! I'm Manja! (Tap Play below to begin)";
    notifyListeners();
  }

  /// Toggles between Play and Pause for landmark narration
  void togglePlayPause() {
    if (_playbackState == StoryPlaybackState.playing) {
      _placementService.narrationService.pause();
    } else {
      _hasStartedStorytelling = true;
      onStorytellingActivityChanged?.call(true);
      _show3DLandmarkModel =
          has3dModel; // 3D model only appears after user taps Play / Resume if landmark has a model asset
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
    onStorytellingActivityChanged?.call(false);
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
    if (_disposed || _nodes.isEmpty || arObjectManager == null) return;
    _currentYawDegrees = (_currentYawDegrees + deltaDegrees) % 360;
    // Update the existing node in place. Keep its anchor and distance-adapted
    // scale, and avoid remove/add races with pause or surface recreation.
    _nodes.first.eulerAngles = vector.Vector3(
      0,
      vector.radians(_currentYawDegrees),
      0,
    );
    notifyListeners();
  }

  /// Turns the Avatar 180 degrees to face the opposite direction / face user
  Future<void> turn180() => rotateAvatar(180.0);

  /// Toggles the 3D Landmark Model viewer
  void toggle3DModelViewer() {
    if (!has3dModel) return;
    _show3DLandmarkModel = !_show3DLandmarkModel;
    notifyListeners();
  }

  bool _isCapturingSnapshot = false;
  bool get isCapturingSnapshot => _isCapturingSnapshot;

  /// Captures a high-resolution snapshot of the AR scene (Camera feed + 3D Avatar)
  /// and saves it directly to the device photo gallery.
  Future<bool> takeSnapshotAndSave() async {
    if (arSessionManager == null || _isCapturingSnapshot) return false;
    try {
      _isCapturingSnapshot = true;
      notifyListeners();

      final imageProvider = await arSessionManager!.snapshot().timeout(
        const Duration(milliseconds: 4500),
      );
      if (imageProvider is MemoryImage) {
        await Gal.putImageBytes(
          imageProvider.bytes,
          name:
              'NarrateMY_${landmarkName.replaceAll(RegExp(r'\s+'), '_')}_${DateTime.now().millisecondsSinceEpoch}',
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Failed to capture and save AR snapshot: $e");
      return false;
    } finally {
      _isCapturingSnapshot = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    onStorytellingActivityChanged?.call(false);
    _subtitleSub?.cancel();
    _playbackSub?.cancel();
    _errorSub?.cancel();

    // Release native AR resources safely to prevent memory leaks and Camera2 hardware conflicts
    try {
      arSessionManager?.onPlaneOrPointTap = (results) {};
      _nodes.clear();
      _anchors.clear();
      arSessionManager?.dispose();
    } catch (e) {
      debugPrint("Error disposing AR resources: $e");
    }

    _placementService.dispose();
    super.dispose();
  }
}
