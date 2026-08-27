import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../viewmodel/ar/ar_exploration_viewmodel.dart';
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
  const ARExplorationView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ARExplorationViewModel()..init(),
      child: const _ARExplorationScaffold(),
    );
  }
}

class _ARExplorationScaffold extends StatefulWidget {
  const _ARExplorationScaffold();

  @override
  State<_ARExplorationScaffold> createState() => _ARExplorationScaffoldState();
}

class _ARExplorationScaffoldState extends State<_ARExplorationScaffold> {
  bool _showDebugHud = true; // default ON while you're diagnosing; flip to false later

  /// Whether ARCameraView is allowed to hold the physical camera open.
  /// Flipped off right before navigating into AR Placement — see
  /// ARCameraView's doc comment for why two camera clients on the same
  /// hardware at once causes the freeze loop.
  bool _cameraActive = true;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ARExplorationViewModel>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (vm.state) {
        ARViewState.idle || ARViewState.checkingPermissions || ARViewState.loading =>
        const Center(child: CircularProgressIndicator(color: Colors.white)),
        ARViewState.permissionDenied => _PermissionDeniedView(message: vm.errorMessage),
        ARViewState.error => _ErrorView(message: vm.errorMessage),
        ARViewState.ready => Stack(
          fit: StackFit.expand,
          children: [
            ARCameraView(active: _cameraActive),
            ARMarkerOverlay(
              nearbyMarkers: vm.nearbyMarkers,
              primaryMarker: vm.primaryMarker,
              deviceHeadingDegrees: vm.deviceHeadingDegrees,
              onTapMarker: (marker) => _navigateToPlacement(context, marker),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ARNotificationBanner(
                markers: vm.nearbyMarkers,
                onTapMarker: (marker) => _navigateToPlacement(context, marker),
              ),
            ),
            Positioned(
              top: 104,
              right: 12,
              child: IconButton(
                icon: Icon(_showDebugHud ? Icons.bug_report : Icons.bug_report_outlined,
                    color: Colors.white),
                onPressed: () => setState(() => _showDebugHud = !_showDebugHud),
              ),
            ),
            // Testing for Marker
            /*
            Positioned(
              bottom: 25,
              left: 20,
              right: 20,
              child: Center(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    icon: const Icon(Icons.science_outlined, size: 20),
                    onPressed: () {
                      const dummyMarker = ARMarker(
                        markerId: 'MK003',
                        latitude: 3.15750,
                        longitude: 101.71160,
                        name: 'The Skybridge',
                        activationRadiusMeters: 80,
                      );
                      _navigateToPlacement(context, dummyMarker);
                    },
                    label: const Text(
                      '🧪 Test AR Placement (Mock Marker)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            */
            if (_showDebugHud) _DebugHud(vm: vm),
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

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ARPlacementScreen(selectedMarker: marker),
      ),
    );

    if (context.mounted) {
      setState(() => _cameraActive = true);
      vm.resume();
    }
  }
}

class _DebugHud extends StatelessWidget {
  const _DebugHud({required this.vm});
  final ARExplorationViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 96,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('you: ${vm.userLat?.toStringAsFixed(6)}, ${vm.userLng?.toStringAsFixed(6)}'),
                Text('heading: ${vm.deviceHeadingDegrees.toStringAsFixed(1)}°'),
                Text('fetched from DB (within scan radius): ${vm.rawFetchedCount}'),
                Text('within activation_radius: ${vm.nearbyMarkers.length}'),
                Text('primary (in FOV + facing): ${vm.primaryMarker?.name ?? "none"}'),
                const Divider(color: Colors.white24),
                for (final m in vm.allComputedMarkers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${m.name}: dist=${m.distanceMeters?.toStringAsFixed(1)}m '
                          'bearing=${m.bearingFromUser?.toStringAsFixed(1)}° '
                          'facing=${m.isFacing} '
                          'inRadius=${m.isWithinActivationRadius}',
                    ),
                  ),
                if (vm.allComputedMarkers.isEmpty)
                  const Text('(no rows returned by the DB query at all — check RLS policies)',
                      style: TextStyle(color: Colors.orangeAccent)),
              ],
            ),
          ),
        ),
      ),
    );
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
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              message ?? 'Camera and Location access are required to use the AR feature.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                await openAppSettings();
                if (context.mounted) {
                  await context.read<ARExplorationViewModel>().retryAfterPermissionGranted();
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