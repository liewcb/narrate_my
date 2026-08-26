import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../viewmodel/ar/ar_placement_viewmodel.dart';

/// Scanning prompt guiding the user to move the device and tap on detected planes
class ARScanningGuide extends StatelessWidget {
  const ARScanningGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 90;

    return Selector<ARPlacementViewModel, bool>(
      selector: (_, vm) => vm.isAvatarPlaced,
      builder: (context, isPlaced, _) {
        if (isPlaced) return const SizedBox.shrink();

        return Positioned(
          top: topPadding,
          left: 24,
          right: 24,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.vibration, color: Colors.amberAccent, size: 24),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      "No suitable placement surface detected. Please move your device to scan the surrounding area.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
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
