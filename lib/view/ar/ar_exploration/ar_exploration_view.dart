import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../viewmodel/ar/ar_exploration_vm.dart';
import '../../../model/entities/ar_object.dart';
import '../ar_placement/ar_placement_view.dart';
import 'widgets/ar_camera_view.dart';
import 'widgets/ar_marker_overlay.dart';
import 'widgets/ar_notification_banner.dart';

/// UC100 — AR Exploration Module (BF-1 through BF-7).
/// Notification banner intentionally omitted for now per current scope;
/// [ARMarkerOverlay] still renders every nearby marker (not just the
/// primary one) so "detect the nearby marker" is still visible on screen.
class ARExplorationView extends StatelessWidget {
  /// Whether the AR tab is the one currently selected in the bottom nav.
  ///
  /// [AppRoutes] keeps all four tabs alive at once via `IndexedStack` (so
  /// switching tabs doesn't lose AR scanning state) — but that means this
  /// widget is built immediately at app launch and never disposed just
  /// by switching away from it. Without this flag, the camera/GPS/
  /// compass/accelerometer used to start the instant the app opened and
  /// never stop for the rest of the app's life, regardless of which tab
  /// was visible — the real cause of crashes/freezes that showed up on
  /// completely unrelated screens (e.g. right after opening Profile).
  final bool isActive;

  const ARExplorationView({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Deliberately NOT calling `..init()` here — that would start the
      // camera/GPS/compass immediately at app launch (IndexedStack
      // builds this the moment the app opens, tab selected or not).
      // `_ARExplorationScaffold` below calls `init()` itself, once, the
      // first time `isActive` actually becomes true.
      create: (_) => ARExplorationViewModel(),
      child: _ARExplorationScaffold(isActive: isActive),
    );
  }
}

class _ARExplorationScaffold extends StatefulWidget {
  final bool isActive;

  const _ARExplorationScaffold({required this.isActive});

  @override
  State<_ARExplorationScaffold> createState() => _ARExplorationScaffoldState();
}

class _ARExplorationScaffoldState extends State<_ARExplorationScaffold> {
  bool _hasInitialized = false;

  /// Whether ARCameraView is allowed to hold the physical camera open.
  /// False by default — only turned on once this tab is actually
  /// selected (see [didUpdateWidget]/[initState]), and flipped off again
  /// both when leaving this tab and right before navigating into AR
  /// Placement (see ARCameraView's doc comment for why two camera
  /// clients on the same hardware at once causes the freeze loop).
  bool _cameraActive = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      // Set fields directly rather than going through `_activate()`'s
      // setState() call — calling setState() synchronously inside
      // initState() trips Flutter's "setState() called during build"
      // assertion. The very first build already reads these fields
      // fresh, so no setState() is needed for it.
      _hasInitialized = true;
      _cameraActive = true;
      // Defer the actual ViewModel kickoff to right after the first
      // frame, so this widget finishes mounting cleanly first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<ARExplorationViewModel>().init();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ARExplorationScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _activate();
    } else if (!widget.isActive && oldWidget.isActive) {
      _deactivate();
    }
  }

  void _activate() {
    final vm = context.read<ARExplorationViewModel>();
    if (!_hasInitialized) {
      _hasInitialized = true;
      vm.init();
    } else {
      vm.resume();
    }
    setState(() => _cameraActive = true);
  }

  void _deactivate() {
    if (!_hasInitialized) return; // never started — nothing to stop
    context.read<ARExplorationViewModel>().pause();
    setState(() => _cameraActive = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ARExplorationViewModel>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (vm.state) {
        ARViewState.idle ||
        ARViewState.checkingPermissions ||
        ARViewState.loading => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        ARViewState.permissionDenied => _PermissionDeniedView(
          message: vm.errorMessage,
        ),
        ARViewState.error => _ErrorView(message: vm.errorMessage),
        ARViewState.ready => Stack(
          fit: StackFit.expand,
          children: [
            ARCameraView(active: _cameraActive),
            ARMarkerOverlay(
              nearbyMarkers: vm.nearbyMarkers,
              primaryMarker: vm.primaryMarker,
              deviceHeadingDegrees: vm.deviceHeadingDegrees,
              devicePitchDegrees: vm.devicePitchDegrees,
              onTapMarker: (marker) => _navigateToPlacement(context, marker),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ARNotificationBanner(
                markers: vm.nearbyMarkers,
              ),
            ),
          ],
        ),
      },
    );
  }

  void _navigateToPlacement(BuildContext context, ARMarker marker) async {
    final vm = context.read<ARExplorationViewModel>();

    // Stop this screen's GPS/compass/accelerometer streams AND release
    // the physical camera before ARCore starts its own session on the
    // Placement screen — running both at once is what caused the
    // freeze/stutter loop (confirmed in logcat: IMU buffer overflow +
    // CameraCaptureSession CAMERA_ERROR from two clients on one camera).
    vm.pause();
    setState(() => _cameraActive = false);

    // Give the `camera` plugin's async teardown a brief moment to
    // actually close the Camera2 session before ARCore tries to open
    // its own on the same physical camera.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ARPlacementScreen(
          selectedMarker: marker,
          cameraMarkerIds: vm.nearbyMarkers
              .map((item) => item.markerId)
              .toList(growable: false),
        ),
      ),
    );

    if (context.mounted) {
      setState(() => _cameraActive = true);
      vm.resume();
    }
  }
}

/// [A1] Permission Denied
class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message ??
                  'Camera and Location access are required to use the AR feature.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                await openAppSettings();
                if (context.mounted) {
                  await context
                      .read<ARExplorationViewModel>()
                      .retryAfterPermissionGranted();
                }
              },
              child: const Text('Enable in Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              message ?? 'Something went wrong starting the AR camera.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.read<ARExplorationViewModel>().init(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}