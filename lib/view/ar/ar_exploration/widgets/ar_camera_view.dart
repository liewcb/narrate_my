import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Live camera feed used as the AR background (BF-1: "opens the AR Camera
/// feature"). Purely presentational — no permission logic here, that's
/// handled upstream by the ViewModel before this widget is ever built.
///
/// [active] controls whether this widget is allowed to hold the physical
/// camera open. Set it to false right before navigating into AR
/// Placement, which starts its own ARCore/ARKit camera session — if this
/// widget's CameraController is still holding the back camera open at
/// the same time, Android's Camera2 framework has to arbitrate between
/// two clients for the same hardware, which shows up as
/// "CameraCaptureSession ... CAMERA_ERROR (3): Function not implemented"
/// in logcat and a visible stutter/freeze loop while AR Placement scans
/// for a surface. Because `Navigator.push` doesn't dispose the widget
/// it's pushed from, this widget's own `dispose()` never runs for that
/// case — [active] is the explicit signal to release the camera anyway.
class ARCameraView extends StatefulWidget {
  final bool active;

  const ARCameraView({super.key, this.active = true});

  @override
  State<ARCameraView> createState() => _ARCameraViewState();
}

class _ARCameraViewState extends State<ARCameraView> {
  CameraController? _controller;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _initFuture = _setup();
    }
  }

  @override
  void didUpdateWidget(covariant ARCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      // Coming back from AR Placement: the camera was fully released
      // while we were away (see _release below), so open it fresh
      // rather than assuming a stale controller is still valid.
      _initFuture = _setup();
    } else if (!widget.active && oldWidget.active) {
      // Going away: release the physical camera now, synchronously with
      // this state transition, instead of waiting for a dispose() that
      // won't come until the tourist eventually pops all the way back
      // past this screen.
      _release();
    }
  }

  Future<void> _setup() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final backCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();

    if (!mounted || !widget.active) {
      // Navigated away again before init finished — don't leave an
      // orphaned camera session open in the background.
      await controller.dispose();
      return;
    }
    _controller = controller;
    setState(() {});
  }

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    if (mounted) setState(() {});
    if (controller != null) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return Container(color: Colors.black);
        }
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 1,
              height: controller.value.previewSize?.width ?? 1,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}