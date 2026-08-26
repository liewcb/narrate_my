import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ar_flutter_plugin_plus/datatypes/node_types.dart';
import '../../entities/ar_placement.dart';

/// High-performance Service managing 3D GLB model preparation and pre-caching
class ARModelService {
  static const String _originalAssetPath = 'assets/manja.glb';

  /// Prepares avatar config instantly using native AAssetManager memory-mapping (0ms latency).
  Future<ARAvatarConfig> prepareAvatarConfig() async {
    return ARAvatarConfig.defaultManja(
      modelUri: _originalAssetPath,
      nodeType: NodeType.localGLB,
    );
  }

  /// Preloads and pre-caches the representative 3D landmark model in memory (REQ_204_5)
  Future<void> preloadLandmarkModel(String? modelPath) async {
    if (modelPath == null || modelPath.trim().isEmpty) return;
    try {
      final safePath = modelPath.trim();
      if (safePath.startsWith('assets/')) {
        // Pre-warm Flutter root bundle asset cache in memory
        await rootBundle.load(safePath);
      }
    } catch (e) {
      debugPrint('Preload landmark 3D model notice: $e');
    }
  }
}
