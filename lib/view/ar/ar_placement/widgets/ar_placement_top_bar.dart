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
      child: Selector<ARPlacementViewModel, ({String landmarkName, bool isPlaying})>(
        selector: (context, vm) => (
          landmarkName: vm.landmarkName,
          isPlaying: vm.isPlaying,
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
                  icon: Icon(
                    data.isPlaying ? Icons.arrow_back_ios_new : Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
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

              // Mode / Status Badge
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
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.explore_outlined, color: Colors.white, size: 20),
                ),
            ],
          );
        },
      ),
    );
  }
}
