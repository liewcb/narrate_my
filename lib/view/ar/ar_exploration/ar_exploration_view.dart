import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../viewmodel/ar/ar_exploration_viewmodel.dart';
import 'widgets/ar_camera_view.dart';
import 'widgets/ar_marker_overlay.dart';

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

class _ARExplorationScaffold extends StatelessWidget {
  const _ARExplorationScaffold();

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
              const ARCameraView(),
              ARMarkerOverlay(
                nearbyMarkers: vm.nearbyMarkers,
                primaryMarker: vm.primaryMarker,
                deviceHeadingDegrees: vm.deviceHeadingDegrees,
                onTapMarker: (marker) {
                  // BF-8 onward (heritage interpretation) is a separate
                  // use case/screen — hook the navigation here once that
                  // flow exists.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Selected: ${marker.name}')),
                  );
                },
              ),
            ],
          ),
      },
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
