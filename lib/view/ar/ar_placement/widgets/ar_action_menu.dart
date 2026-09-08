import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_vm.dart';
import '../../../../viewmodel/ar/ar_placement_vm.dart';
import '../../../../viewmodel/ar/ar_recommendation_vm.dart';
import './video_player_overlay.dart';

/// Action Menu shown after Avatar is placed on plane
class ARActionMenu extends StatelessWidget {
  const ARActionMenu({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    const primaryTeal = Color(0xFF2E656A);

    return Selector<
      ARPlacementViewModel,
      ({
        bool isPlaced,
        bool hasAvatarInScene,
        bool hasStarted,
        bool isPlaneDetected,
        String? videoUrl,
        String? videoUrlBackup,
        String landmarkName,
      })
    >(
      selector: (context, vm) => (
        isPlaced: vm.isAvatarPlaced,
        hasAvatarInScene: vm.hasAvatarInScene,
        hasStarted: vm.hasStartedStorytelling,
        isPlaneDetected: vm.isPlaneDetected,
        videoUrl: vm.videoUrl,
        videoUrlBackup: vm.videoUrlBackup,
        landmarkName: vm.landmarkName,
      ),
      builder: (context, data, child) {
        if (data.hasStarted) return const SizedBox.shrink();

        // 1. Center prompt guiding the user to tap and place Manja (initial scan or lockscreen resume)
        // Disappear immediately once the blue plane/surface is detected!
        if (!data.isPlaced || !data.hasAvatarInScene) {
          if (data.isPlaneDetected) {
            return const SizedBox.shrink();
          }
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

        // 2. Action buttons displayed once Manja is placed in the scene
        return Stack(
          children: [
            // Bottom Action buttons
            Positioned(
              bottom: 16,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Main Storytelling button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryTeal,
                        foregroundColor: Colors.white,
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      onPressed: () {
                        context
                            .read<ARPlacementViewModel>()
                            .openStorytellingMenu();
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        AppLocalizations.t('ar.storytelling'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Secondary action buttons (Watch Video, Recommend)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: () async {
                              final vm = context.read<ARPlacementViewModel>();
                              if (vm.isPlaying) {
                                vm.pauseStorytelling();
                              }
                              // Pause background ARCore rendering to free GPU/memory while watching video
                              vm.pauseARSession();
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoPlayerScreen(
                                    videoUrl: data.videoUrl,
                                    videoUrlBackup: data.videoUrlBackup,
                                    landmarkName: data.landmarkName,
                                  ),
                                ),
                              );
                              if (context.mounted) {
                                vm.resumeARSession();
                              }
                            },
                            icon: const Icon(Icons.play_circle_fill, size: 18),
                            label: Text(
                              AppLocalizations.t('ar.watchVideo'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: () {
                              final marker = context
                                  .read<ARPlacementViewModel>()
                                  .selectedMarker;
                              if (marker != null) {
                                context.read<ARRecommendationVm>().open(marker);
                              }
                            },
                            icon: const Icon(
                              Icons.recommend_outlined,
                              size: 18,
                            ),
                            label: Text(
                              AppLocalizations.t('ar.recommend'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
