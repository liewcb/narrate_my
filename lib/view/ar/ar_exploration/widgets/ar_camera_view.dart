import 'dart:async';
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

class _ARCameraViewState extends State<ARCameraView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  Future<void> _operations = Future<void>.value();
  int _generation = 0;
  bool _foreground = true;
  bool _disposed = false;
  bool _isRecovering = false;

  bool get _isRouteCurrent => ModalRoute.of(context)?.isCurrent ?? true;
  bool get _shouldOpen => !_disposed && widget.active && _foreground && _isRouteCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _synchronize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If another route (like ARPlacementScreen) is pushed on top, release camera immediately!
    if (!_isRouteCurrent && _controller != null) {
      _synchronize();
    }
  }

  @override
  void didUpdateWidget(covariant ARCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _synchronize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.active || !_isRouteCurrent) {
      // Background route (e.g. AR Placement screen is open) — do NOT touch Camera2!
      if (_controller != null) {
        _synchronize();
      }
      return;
    }
    final isForeground = state == AppLifecycleState.resumed;
    if (_foreground == isForeground) return;
    _foreground = isForeground;

    if (_foreground) {
      // 💡 On Android, when waking up from lockscreen, CameraService takes 200-400ms
      // to fully release and become available. Wait 250ms before requesting camera hardware.
      _isRecovering = true;
      if (mounted) setState(() {});
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted && _foreground && !_disposed && widget.active && _isRouteCurrent) {
          _synchronize();
        }
      });
    } else {
      _synchronize();
      if (mounted) setState(() {});
    }
  }

  void _synchronize() {
    final generation = ++_generation;

    _operations = _operations
        .then((_) async {
          final previous = _controller;
          _controller = null;
          if (mounted && !_disposed) setState(() {});
          await previous?.dispose();

          if (!_shouldOpen || generation != _generation) {
            _isRecovering = false;
            return;
          }

          CameraController? candidateController;
          var retained = false;
          int attempts = 0;
          const maxAttempts = 3;

          while (attempts < maxAttempts && _shouldOpen && generation == _generation) {
            attempts++;
            try {
              final cameras = await availableCameras();
              if (!_shouldOpen || generation != _generation || cameras.isEmpty) {
                return;
              }
              final camera = cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.back,
                orElse: () => cameras.first,
              );
              candidateController = CameraController(
                camera,
                ResolutionPreset.high,
                enableAudio: false,
              );
              await candidateController.initialize();

              if (!_shouldOpen || generation != _generation) {
                await candidateController.dispose();
                return;
              }

              _controller = candidateController;
              retained = true;
              _isRecovering = false;
              break;
            } catch (e) {
              debugPrint('Camera init attempt $attempts failed: $e');
              await candidateController?.dispose();
              candidateController = null;
              if (attempts < maxAttempts && _shouldOpen && generation == _generation) {
                await Future.delayed(Duration(milliseconds: 300 * attempts));
              }
            }
          }

          if (!retained) {
            await candidateController?.dispose();
          }

          if (mounted && !_disposed) {
            setState(() {
              _isRecovering = false;
            });
          }
        })
        .catchError((Object error, StackTrace stack) {
          debugPrint('Camera lifecycle error: $error');
          if (mounted && !_disposed) {
            setState(() {
              _isRecovering = false;
            });
          }
        });

    _initFuture = _operations;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _synchronize();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return Container(
            color: const Color(0xFF142121),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: Color(0xFFD67D4A),
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isRecovering ? "Resuming AR Camera..." : "Initializing camera...",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }
        return RepaintBoundary(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1,
                height: controller.value.previewSize?.width ?? 1,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}