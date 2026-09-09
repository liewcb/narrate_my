import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/ai_assistant/global_ai_assistant.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_vm.dart';
import '../../../../model/entities/ar_placement.dart';
import '../../../../viewmodel/ar/ar_placement_vm.dart';
import './ar_3d_viewer_overlay.dart';

/// Storytelling overlay managing subtitles, 3D model viewport, and narration controls
class ARStorytellingPanel extends StatelessWidget {
  const ARStorytellingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    const accentOrange = Color(0xFFD67D4A);
    final topPadding = MediaQuery.of(context).padding.top + 70;
    final isAssistantOpen = context.select<GlobalAiAssistantController, bool>(
      (c) => c.isAssistantOpen,
    );
    final isCovered =
        isAssistantOpen || !(ModalRoute.of(context)?.isCurrent ?? true);

    return Selector<ARPlacementViewModel, ({
      bool isPlaced,
      bool hasAvatarInScene,
      bool hasStarted,
      bool isPlaneDetected,
      String subtitle,
      StoryPlaybackState playbackState,
      bool show3d,
      String? model3dPath,
      String landmarkName,
    })>(
      selector: (context, vm) => (
        isPlaced: vm.isAvatarPlaced,
        hasAvatarInScene: vm.hasAvatarInScene,
        hasStarted: vm.hasStartedStorytelling,
        isPlaneDetected: vm.isPlaneDetected,
        subtitle: vm.currentSubtitle,
        playbackState: vm.playbackState,
        show3d: vm.show3DLandmarkModel,
        model3dPath: vm.model3dPath,
        landmarkName: vm.landmarkName,
      ),
      builder: (context, data, child) {
        if (!data.hasStarted) return const SizedBox.shrink();

        final isPlaying = data.playbackState == StoryPlaybackState.playing;
        final isPaused = data.playbackState == StoryPlaybackState.paused;
        final isCompleted = data.playbackState == StoryPlaybackState.completed;
        final bool hasModelAsset = data.model3dPath != null && data.model3dPath!.trim().isNotEmpty;
        final bool show3DModel = !isCovered && hasModelAsset && data.show3d && (isPlaying || isPaused || isCompleted);

        final String actionLabel = isPlaying
            ? AppLocalizations.t('ar.actionPause')
            : (isCompleted
                  ? AppLocalizations.t('ar.actionReplay')
                  : (isPaused
                        ? AppLocalizations.t('ar.actionResume')
                        : AppLocalizations.t('ar.actionPlay')));
        final IconData actionIcon = isPlaying
            ? Icons.pause
            : (isCompleted ? Icons.replay : Icons.play_arrow);

        return Positioned.fill(
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
                _buildSubtitleCard(
                  context,
                  data,
                  accentOrange,
                  isPlaying,
                  isPaused,
                  isCompleted,
                  hasModelAsset,
                ),

                const SizedBox(height: 10),

                // 2. 3D Model Viewport (Preloaded on storytelling entry, kept warm with Visibility to eliminate reloads)
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 3D Model: Rendered when active, and completely unmounted when hidden to free WebGL/GPU memory
                      if (hasModelAsset && show3DModel)
                        const AR3DViewerOverlay(),

                      // Re-scan & re-place prompt: Prominently displayed floating on top whenever Manja is reset after lockscreen
                      if (!data.hasAvatarInScene && !data.isPlaneDetected)
                        _buildReScanSurfacePrompt(),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 3. Bottom Play / Pause / Replay / Stop Controls
                _buildBottomControls(context, isPlaying, actionIcon, actionLabel),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Semi-transparent overlay prompt guiding the user to tap to place Manja and continue story
  Widget _buildReScanSurfacePrompt() {
    return Center(
      child: IgnorePointer(
        child: Image.asset(
          'assets/images/scanAR.webp',
          width: 320,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildSubtitleCard(
    BuildContext context,
    dynamic data,
    Color accentOrange,
    bool isPlaying,
    bool isPaused,
    bool isCompleted,
    bool hasModelAsset,
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
                      AppLocalizations.t('ar.storyCompleted'),
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
                  isPaused
                      ? AppLocalizations.t('ar.paused')
                      : AppLocalizations.t('ar.tapPlayToBegin'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              if (isPlaying || isPaused || isCompleted)
                IconButton(
                  icon: Icon(
                    !hasModelAsset
                        ? Icons.view_in_ar_outlined
                        : ((data.show3d as bool) ? Icons.view_in_ar : Icons.view_in_ar_outlined),
                    color: !hasModelAsset
                        ? Colors.white24
                        : ((data.show3d as bool) ? accentOrange : Colors.white70),
                    size: 22,
                  ),
                  tooltip: !hasModelAsset
                      ? AppLocalizations.t('ar.no3dModelAvailable')
                      : ((data.show3d as bool)
                            ? AppLocalizations.t('ar.hide3dModel')
                            : AppLocalizations.t('ar.show3dModel')),
                  onPressed: () {
                    if (!hasModelAsset) {
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppLocalizations.t('ar.no3dModelForLandmark')
                                      .replaceFirst(
                                        '{landmarkName}',
                                        data.landmarkName as String,
                                      ),
                                  style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: const Color(0xFF1B2A2B),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      );
                      return;
                    }
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
              label: Text(AppLocalizations.t('ar.endStory')),
            ),
          ),
        ),
      ],
    );
  }
}