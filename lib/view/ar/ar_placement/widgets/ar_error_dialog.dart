import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../model/entities/ar_placement.dart';
import '../../../../viewmodel/ar/ar_placement_vm.dart';

/// Error overlay complying with REQ_201_6:
/// Displays an error message and allows the tourist to retry or return to the
/// AR exploration view when attraction content retrieval or narration generation fails.
class ARErrorOverlay extends StatelessWidget {
  const ARErrorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    const accentOrange = Color(0xFFD67D4A);

    return Selector<ARPlacementViewModel, ({PlacementState state, String? errorMessage})>(
      selector: (context, vm) => (
        state: vm.placementState,
        errorMessage: vm.errorMessage,
      ),
      builder: (context, data, child) {
        if (data.state != PlacementState.error) {
          return const SizedBox.shrink();
        }

        return Container(
          color: Colors.black.withValues(alpha: 0.78),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
            decoration: BoxDecoration(
              color: const Color(0xFF142121),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.6),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "Narration Unavailable",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  data.errorMessage ??
                      "Attraction content retrieval or narration generation failed. Please try again.",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    // Return to AR exploration view button
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text(
                          "Return",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Retry button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                        ),
                        onPressed: () {
                          context.read<ARPlacementViewModel>().retryContentRetrieval();
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text(
                          "Retry",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
