import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../viewmodel/ar/ar_placement_viewmodel.dart';
import '../../../../viewmodel/ar/ar_recommendation_vm.dart';
import 'video_player_overlay.dart';

/// Action Menu shown after Avatar is placed on plane
class ARActionMenu extends StatelessWidget {
  const ARActionMenu({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryTeal = Color(0xFF2E656A);

    return Selector<
      ARPlacementViewModel,
      ({bool isPlaced, bool hasStarted, String? videoUrl, String landmarkName})
    >(
      selector: (context, vm) => (
        isPlaced: vm.isAvatarPlaced,
        hasStarted: vm.hasStartedStorytelling,
        videoUrl: vm.videoUrl,
        landmarkName: vm.landmarkName,
      ),
      builder: (context, data, child) {
        if (!data.isPlaced || data.hasStarted) return const SizedBox.shrink();

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
                      label: const Text(
                        "Storytelling",
                        style: TextStyle(
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
                            onPressed: () {
                              final vm = context.read<ARPlacementViewModel>();
                              if (vm.isPlaying) {
                                vm.pauseStorytelling();
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoPlayerScreen(
                                    videoUrl: data.videoUrl,
                                    landmarkName: data.landmarkName,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.play_circle_fill, size: 18),
                            label: const Text(
                              "Watch Video",
                              style: TextStyle(fontSize: 13),
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
                            label: const Text(
                              "Recommend",
                              style: TextStyle(fontSize: 13),
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
