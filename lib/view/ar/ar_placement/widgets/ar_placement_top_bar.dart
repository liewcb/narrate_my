import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../viewmodel/ar/ar_placement_viewmodel.dart';

/// Top bar displaying Landmark title, Back button, and LIVE / Mode indicators
class ARPlacementTopBar extends StatelessWidget {
  const ARPlacementTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    const accentOrange = Color(0xFFD67D4A);
    final topPadding = MediaQuery.of(context).padding.top + 16;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: Selector<ARPlacementViewModel, ({
        String landmarkName,
        bool isPlaying,
        bool hasAvatarInScene,
        bool hasStarted,
        bool isCapturing,
      })>(
        selector: (context, vm) => (
          landmarkName: vm.landmarkName,
          isPlaying: vm.isPlaying,
          hasAvatarInScene: vm.hasAvatarInScene,
          hasStarted: vm.hasStartedStorytelling,
          isCapturing: vm.isCapturingSnapshot,
        ),
        builder: (context, data, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back / Close Button
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: data.hasStarted ? 'Back to Actions' : 'Exit AR',
                  icon: Icon(
                    data.hasStarted ? Icons.close : Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () {
                    if (data.hasStarted) {
                      // Return to the 3-button Action Menu (Storytelling, Watch Video, Recommend)
                      context.read<ARPlacementViewModel>().stopStorytelling();
                    } else {
                      // Exit AR Placement screen back to exploration
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),

              // Landmark Name Pill
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: accentOrange,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          data.landmarkName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Mode / Status Badge or Camera Snapshot Button
              if (data.isPlaying)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E6A4B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Colors.greenAccent),
                      SizedBox(width: 6),
                      Text(
                        "LIVE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else if (data.hasAvatarInScene && !data.hasStarted)
                // 📸 Snapshot Camera Button (Shown ONLY when Avatar placed AND NOT in Storytelling!)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: data.isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.amberAccent,
                          ),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          tooltip: 'Take Photo with Manja',
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final vm = context.read<ARPlacementViewModel>();
                            final success = await vm.takeSnapshotAndSave();
                            messenger.hideCurrentSnackBar();
                            if (success) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                                      SizedBox(width: 10),
                                      Text(
                                        "📸 Photo saved to Gallery!",
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF1B2A2B),
                                  duration: const Duration(seconds: 3),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              );
                            } else {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: const Text("Failed to save photo. Please try again."),
                                  backgroundColor: Colors.redAccent.shade700,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                )
              else
                // Left blank before avatar placement AND during storytelling (when not live)
                const SizedBox(width: 44, height: 44),
            ],
          );
        },
      ),
    );
  }
}
