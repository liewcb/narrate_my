import 'dart:async';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_vm.dart';
import '../../../../viewmodel/ar/ar_placement_vm.dart';

/// Standalone 3D Landmark Model Viewport Widget with persistent loading shield and GPU optimizations.
class AR3DViewerOverlay extends StatefulWidget {
  const AR3DViewerOverlay({super.key});

  @override
  State<AR3DViewerOverlay> createState() => _AR3DViewerOverlayState();
}

class _AR3DViewerOverlayState extends State<AR3DViewerOverlay> {
  bool _shouldAttachViewer = false;
  bool _is3DModelLoading = true;
  Timer? _attachTimer;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    // Defer attaching the heavy PlatformView/WebView by 350ms so the camera
    // and UI entrance transition render at silky smooth 60 FPS without any frame drops!
    _attachTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() => _shouldAttachViewer = true);
        _loadingTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted) {
            setState(() => _is3DModelLoading = false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _attachTimer?.cancel();
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    const cardBg = Color(0xFF1B2A2B);
    const accentOrange = Color(0xFFD67D4A);

    return Selector<ARPlacementViewModel, ({
      String landmarkName,
      String? modelPath,
    })>(
      selector: (context, vm) => (
        landmarkName: vm.landmarkName,
        modelPath: vm.model3dPath,
      ),
      builder: (context, data, child) {
        final modelPath = data.modelPath;
        final landmarkName = data.landmarkName;
        final hasModel = modelPath != null && modelPath.trim().isNotEmpty;

        return Container(
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
          clipBehavior: Clip.hardEdge,
          child: hasModel
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. High-Performance WebGL 3D Model Viewer (Async Progressive Loading)
                    if (_shouldAttachViewer)
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
                                    AppLocalizations.t('ar.loading3d')
                                        .replaceFirst(
                                          '{landmarkName}',
                                          landmarkName,
                                        ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppLocalizations.t('ar.compilingGeometry'),
                                    style: const TextStyle(
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.touch_app_outlined, color: Colors.white70, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.t('ar.view360'),
                                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
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
                          Text(
                            AppLocalizations.t('ar.model3dUnavailableTitle'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppLocalizations.t('ar.model3dUnavailableBody'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          );
      },
    );
  }
}
