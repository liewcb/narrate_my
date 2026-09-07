import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_vm.dart';

/// Pure View component: Displays an isolated 3D landmark model,
/// allowing tourists to rotate and zoom with gestures.
/// If no 3D model is found (null url or load failure), displays a clear fallback message.
class ObjectPreview extends StatelessWidget {
  final String? modelPath;
  final String landmarkName;
  final VoidCallback? onClose;

  const ObjectPreview({
    super.key,
    required this.modelPath,
    required this.landmarkName,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    final hasModel = modelPath != null && modelPath!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          landmarkName,
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: onClose ?? () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: hasModel
            ? ModelViewer(
                key: ValueKey(modelPath),
                src: modelPath!,
                alt: landmarkName,
                ar: false,
                autoRotate: false,
                cameraControls: true,
                disableZoom: false,
                backgroundColor: Colors.black,
                loading: Loading.eager,
                interactionPrompt: InteractionPrompt.auto,
                shadowIntensity: 0.0,
              )
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.view_in_ar,
                        color: Colors.redAccent,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.t('ar.model3dUnavailableTitle'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppLocalizations.t('ar.model3dMissingError')
                          .replaceFirst('{landmarkName}', landmarkName),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}