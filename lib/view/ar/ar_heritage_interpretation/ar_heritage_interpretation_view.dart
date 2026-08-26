import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../model/entities/ar_object.dart';
import '../../../viewmodel/ar/ar_heritage_interpretation_viewmodel.dart';
import '../ar_placement/widgets/object_preview.dart';

/// Screen corresponding to `AR Heritage Screen` in the architecture diagram.
class ARHeritageInterpretationView extends StatelessWidget {
  final ARMarker marker;

  const ARHeritageInterpretationView({super.key, required this.marker});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ARHeritageInterpretationViewModel>(
      create: (_) => ARHeritageInterpretationViewModel()..init(marker),
      child: const _HeritageInterpretationContent(),
    );
  }
}

class _HeritageInterpretationContent extends StatelessWidget {
  const _HeritageInterpretationContent();

  @override
  Widget build(BuildContext context) {
    const primaryTeal = Color(0xFF2E656A);
    const accentOrange = Color(0xFFD67D4A);

    return Scaffold(
      backgroundColor: const Color(0xFF142121),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Consumer<ARHeritageInterpretationViewModel>(
          builder: (_, vm, _) => Text(
            vm.currentMarker?.name ?? 'Heritage Landmark',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: Consumer<ARHeritageInterpretationViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          final story = vm.currentStory;
          final marker = vm.currentMarker;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3D Model Quick Preview Card
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.view_in_ar, size: 64, color: Colors.white38),
                      Positioned(
                        bottom: 16,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ObjectPreview(
                                  modelPath: story?.model3dPath,
                                  landmarkName: marker?.name ?? 'Landmark 3D',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.touch_app, size: 18),
                          label: const Text('Interactive 3D Preview'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Title & Badges
                Text(
                  marker?.name ?? 'Landmark',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (marker?.labels.isNotEmpty ?? false)
                  Wrap(
                    spacing: 8,
                    children: marker!.labels.map((tag) {
                      return Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 12, color: Colors.white)),
                        backgroundColor: primaryTeal.withValues(alpha: 0.6),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),

                // Description
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text(
                    marker?.description ??
                        "An iconic architectural landmark celebrating culture, engineering excellence, and Malaysian heritage.",
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                  ),
                ),
                const SizedBox(height: 20),

                // Historical Narration Paragraphs
                const Text(
                  "Historical Background & Architecture",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (story != null)
                  for (final paragraph in story.narrationParagraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Icon(Icons.circle, size: 6, color: accentOrange),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              paragraph,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
