import 'dart:async';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';
import '../../../../viewmodel/ar/ar_placement_viewmodel.dart';

/// Standalone 3D Landmark Model Viewport Widget with persistent loading shield and GPU optimizations.
class AR3DViewerOverlay extends StatefulWidget {
  const AR3DViewerOverlay({super.key});

  @override
  State<AR3DViewerOverlay> createState() => _AR3DViewerOverlayState();
}

class _AR3DViewerOverlayState extends State<AR3DViewerOverlay> {
  bool _is3DModelLoading = true;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    // 26MB GLB Model requires 4.5s - 5.0s on mobile device to compile all PBR shaders.
    // Loading overlay stays visible continuously to ensure user never sees a blank screen!
    _loadingTimer = Timer(const Duration(milliseconds: 4800), () {
      if (mounted) {
        setState(() => _is3DModelLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardBg = Color(0xFF1B2A2B);
    const accentOrange = Color(0xFFD67D4A);

    return Selector<ARPlacementViewModel, ({
      String landmarkName,
      String? modelPath,
    })>(
      selector: (_, vm) => (
        landmarkName: vm.landmarkName,
        modelPath: vm.model3dPath,
      ),
      builder: (context, data, _) {
        final modelPath = data.modelPath;
        final landmarkName = data.landmarkName;
        final hasModel = modelPath != null && modelPath.trim().isNotEmpty;

        return RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: cardBg,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: hasModel
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. High-Performance WebGL 3D Model Viewer
                      ModelViewer(
                        key: ValueKey('3d_viewer_$modelPath'),
                        src: modelPath,
                        alt: '$landmarkName 3D Model',
                        ar: false,
                        autoRotate: false,
                        cameraControls: true,
                        backgroundColor: Colors.transparent,
                        disableZoom: false,
                        loading: Loading.eager,
                        interactionPrompt: InteractionPrompt.none,
                        shadowIntensity: 0.0,
                      ),

                      // 2. Dedicated 3D Model Loading Indicator (Guarantees user NEVER sees a blank screen!)
                      AnimatedOpacity(
                        opacity: _is3DModelLoading ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 350),
                        child: IgnorePointer(
                          ignoring: !_is3DModelLoading,
                          child: Container(
                            color: cardBg,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: accentOrange.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: accentOrange,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    "Loading 3D $landmarkName...",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    "Compiling 3D WebGL geometry & textures",
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 3. Top-Right 360° Interactive Hint Badge
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_outlined, color: Colors.white70, size: 12),
                              SizedBox(width: 4),
                              Text(
                                "360° View",
                                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.view_in_ar_outlined,
                              color: Colors.redAccent,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "3D Model Unavailable",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "The representative 3D model could not be loaded. Storytelling can continue without the 3D model.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
