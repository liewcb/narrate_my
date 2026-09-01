import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../model/entities/ar_placement.dart';
import '../../../../viewmodel/ar/ar_placement_viewmodel.dart';
import 'ar_3d_viewer_overlay.dart';

/// Storytelling overlay managing subtitles, 3D model viewport, and narration controls
class ARStorytellingPanel extends StatelessWidget {
  const ARStorytellingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    const accentOrange = Color(0xFFD67D4A);
    final topPadding = MediaQuery.of(context).padding.top + 70;

    return Selector<ARPlacementViewModel, ({
      bool isPlaced,
      bool hasStarted,
      String subtitle,
      StoryPlaybackState playbackState,
      bool show3d,
    })>(
      selector: (context, vm) => (
        isPlaced: vm.isAvatarPlaced,
        hasStarted: vm.hasStartedStorytelling,
        subtitle: vm.currentSubtitle,
        playbackState: vm.playbackState,
        show3d: vm.show3DLandmarkModel,
      ),
      builder: (context, data, child) {
        if (!data.isPlaced) return const SizedBox.shrink();

        final isPlaying = data.playbackState == StoryPlaybackState.playing;
        final isPaused = data.playbackState == StoryPlaybackState.paused;
        final isCompleted = data.playbackState == StoryPlaybackState.completed;
        final bool show3DModel = data.show3d && (isPlaying || isPaused || isCompleted);

        final String actionLabel = isPlaying
            ? "Pause"
            : (isCompleted ? "Replay Story" : (isPaused ? "Resume" : "Play"));
        final IconData actionIcon = isPlaying
            ? Icons.pause
            : (isCompleted ? Icons.replay : Icons.play_arrow);

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
                  // 1. Top Subtitle Box (Displays narration & completion message)
                  _buildSubtitleCard(context, data, accentOrange, isPlaying, isPaused, isCompleted),

                  const SizedBox(height: 10),

                  // 2. 3D Model Viewport (Only rendered when story playback has started)
                  if (show3DModel)
                    const Expanded(
                      child: AR3DViewerOverlay(),
                    )
                  else
                    const Spacer(),

                  const SizedBox(height: 12),

                  // 3. Bottom Play / Pause / Replay / Stop Controls
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
    bool isCompleted,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF142121).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted ? Colors.amberAccent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.2),
        ),
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
            style: TextStyle(
              color: isCompleted ? Colors.amber.shade100 : Colors.white,
              fontSize: 13.5,
              height: 1.4,
              fontWeight: isCompleted ? FontWeight.w500 : FontWeight.w400,
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
              else if (isCompleted)
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.amberAccent, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      "Story Completed",
                      style: TextStyle(
                        color: Colors.amberAccent.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  isPaused ? "Paused" : "Tap Play to begin",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              if (isPlaying || isPaused || isCompleted)
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