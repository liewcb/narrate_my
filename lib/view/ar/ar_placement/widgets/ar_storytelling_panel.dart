import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';
import '../../../../model/entities/ar_placement.dart';
import '../../../../viewmodel/ar/ar_placement_viewmodel.dart';

/// Unified Storytelling View with responsive Subtitle Card, dynamic 3D Model Box, and Narration Controls
class ARStorytellingPanel extends StatelessWidget {
  const ARStorytellingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    const accentOrange = Color(0xFFD67D4A);
    final topPadding = MediaQuery.of(context).padding.top + 70;

    return Selector<ARPlacementViewModel, ({
      bool hasStarted,
      String subtitle,
      StoryPlaybackState playbackState,
      bool show3d,
      String landmarkName,
      String? modelPath,
    })>(
      selector: (_, vm) => (
        hasStarted: vm.hasStartedStorytelling,
        subtitle: vm.currentSubtitle,
        playbackState: vm.playbackState,
        show3d: vm.show3DLandmarkModel,
        landmarkName: vm.landmarkName,
        modelPath: vm.model3dPath,
      ),
      builder: (context, data, _) {
        final isPlaying = data.playbackState == StoryPlaybackState.playing;
        final isPaused = data.playbackState == StoryPlaybackState.paused;

        final String actionLabel = isPlaying
            ? "Pause"
            : (isPaused ? "Resume" : "Play");
        final IconData actionIcon = isPlaying ? Icons.pause : Icons.play_arrow;

        return Positioned.fill(
          child: Visibility(
            visible: data.hasStarted,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: false,
            maintainSemantics: false,
            maintainInteractivity: false,
            child: Padding(
              padding: EdgeInsets.only(
                top: topPadding,
                bottom: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Top Subtitle Box (Auto-resizes based on text length, NEVER overlaps!)
                  _buildSubtitleCard(context, data, accentOrange, isPlaying, isPaused),

                  // 2. 3D Model Viewport (Prewarmed with maintainState for 0ms instant display!)
                  Expanded(
                    child: Visibility(
                      visible: data.show3d,
                      maintainState: true,
                      maintainAnimation: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _build3DModelCard(data),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. Bottom Play / Pause / Resume / Stop Controls
                  _buildBottomControls(context, isPlaying, actionIcon, actionLabel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubtitleCard(
    BuildContext context,
    dynamic data,
    Color accentOrange,
    bool isPlaying,
    bool isPaused,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF142121).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.subtitle as String,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isPlaying)
                Row(
                  children: List.generate(
                    5,
                    (index) => Container(
                      margin: const EdgeInsets.only(right: 4),
                      width: 4,
                      height: index % 2 == 0 ? 14 : 8,
                      decoration: BoxDecoration(
                        color: accentOrange,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                )
              else
                Text(
                  isPaused ? "Paused" : "Tap Play to begin",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              if (isPlaying || isPaused || (data.show3d as bool))
                IconButton(
                  icon: Icon(
                    (data.show3d as bool) ? Icons.view_in_ar : Icons.view_in_ar_outlined,
                    color: (data.show3d as bool) ? accentOrange : Colors.white70,
                    size: 22,
                  ),
                  tooltip: 'Toggle 3D Model',
                  onPressed: () {
                    context.read<ARPlacementViewModel>().toggle3DModelViewer();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _build3DModelCard(dynamic data) {
    final modelPath = data.modelPath as String?;
    final landmarkName = data.landmarkName as String;
    final hasModel = modelPath != null && modelPath.trim().isNotEmpty;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1B2A2B),
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
        child: hasModel
            ? ModelViewer(
                key: ValueKey('3d_viewer_$modelPath'),
                src: modelPath,
                alt: '$landmarkName 3D Model',
                ar: false,
                autoRotate: false,
                cameraControls: true,
                disablePan: true,
                disableZoom: false,
                backgroundColor: const Color(0xFF1B2A2B),
                loading: Loading.eager,
                interactionPrompt: InteractionPrompt.auto,
                shadowIntensity: 0.0,
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
  }

  Widget _buildBottomControls(
    BuildContext context,
    bool isPlaying,
    IconData actionIcon,
    String actionLabel,
  ) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E656A),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              onPressed: () {
                context.read<ARPlacementViewModel>().togglePlayPause();
              },
              icon: Icon(actionIcon),
              label: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              onPressed: () {
                context.read<ARPlacementViewModel>().stopStorytelling();
              },
              icon: const Icon(Icons.stop, size: 20),
              label: const Text("End Story"),
            ),
          ),
        ),
      ],
    );
  }
}
