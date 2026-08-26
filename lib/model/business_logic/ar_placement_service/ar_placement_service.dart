import 'package:ar_flutter_plugin_plus/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_plus/models/ar_node.dart';
import 'package:ar_flutter_plugin_plus/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_plus/datatypes/hittest_result_types.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../../entities/ar_placement.dart';
import 'ar_model_service.dart';
import 'play_narration_service.dart';

/// Business logic service coordinating AR Placement calculations and model creation
class ARPlacementService {
  final ARModelService _modelService;
  final PlayNarrationService _narrationService;

  ARPlacementService({
    ARModelService? modelService,
    PlayNarrationService? narrationService,
  })  : _modelService = modelService ?? ARModelService(),
        _narrationService = narrationService ?? PlayNarrationService();

  ARModelService get modelService => _modelService;
  PlayNarrationService get narrationService => _narrationService;

  /// Selects the best hit test result, ensuring:
  /// 1. Only verified horizontal plane surfaces are accepted (ignoring walls and steep diagonal bridging planes).
  /// 2. Enforces a comfortable minimum safe distance (>= minDistanceMeters, default 0.60m)
  ///    so the 3D avatar never spawns directly in the user's face.
  ARHitTestResult? selectBestHitTest(
    List<ARHitTestResult> results, {
    double minDistanceMeters = 0.60,
  }) {
    if (results.isEmpty) return null;

    // Filter for genuine horizontal plane surfaces (normal vector Y >= 0.70, rejecting steep accidental bridges)
    final planeHits = results.where((hit) {
      if (hit.type != ARHitTestResultType.plane) return false;
      final normalY = hit.worldTransform.getColumn(1).y.abs();
      return normalY >= 0.70; // Must be predominantly horizontal (<= 45° slope)
    }).toList();

    if (planeHits.isEmpty) return null;

    // 1. Prioritize plane hit points within comfortable viewing distance (0.8m ~ 1.5m)
    planeHits.sort((a, b) {
      final aDiff = (a.distance - 1.2).abs();
      final bDiff = (b.distance - 1.2).abs();
      return aDiff.compareTo(bDiff);
    });

    for (final hit in planeHits) {
      if (hit.distance >= minDistanceMeters) {
        return hit;
      }
    }

    // 2. If all hit points along the ray are close, select the furthest one
    planeHits.sort((a, b) => b.distance.compareTo(a.distance));
    return planeHits.first;
  }

  /// Builds a strictly upright, gravity-aligned ARPlaneAnchor that directly faces the tourist.
  /// 1. Locks pitch and roll to 0 (Up vector = [0, 1, 0]) so Manja ALWAYS stands straight upright.
  /// 2. Calculates the horizontal look direction from the avatar's position directly towards
  ///    the user's device camera so Manja ALWAYS faces the tourist.
  ARPlaneAnchor createAnchor(ARHitTestResult hitResult) {
    final position = hitResult.worldTransform.getTranslation();

    // Direction vector from avatar towards user camera on horizontal plane
    final toCamera = vector.Vector3(-position.x, 0, -position.z);
    final forward = toCamera.length2 > 0.0001
        ? toCamera.normalized()
        : vector.Vector3(0, 0, 1);

    // Gravity-aligned vertical Up vector
    final up = vector.Vector3(0, 1, 0);

    // Right-handed coordinate basis (det = +1.0, eliminating shear and lateral slant)
    final right = forward.cross(up)..normalize();
    final actualUp = right.cross(forward)..normalize();

    // Construct level 4x4 matrix facing the user
    final levelTransform = vector.Matrix4.identity()
      ..setColumn(0, vector.Vector4(right.x, right.y, right.z, 0))
      ..setColumn(1, vector.Vector4(actualUp.x, actualUp.y, actualUp.z, 0))
      ..setColumn(2, vector.Vector4(forward.x, forward.y, forward.z, 0))
      ..setColumn(3, vector.Vector4(position.x, position.y, position.z, 1));

    return ARPlaneAnchor(transformation: levelTransform);
  }

  /// Builds the ARNode using the prepared/cached avatar configuration
  /// With distance-adaptive scaling to guarantee close-up taps (e.g. on desk/keyboard)
  /// scale down smoothly and never appear disproportionately large.
  ARNode createAvatarNode(ARAvatarConfig config, {double? distanceMeters}) {
    vector.Vector3 effectiveScale = config.scale;

    if (distanceMeters != null && distanceMeters > 0) {
      // Distance-aware adaptive scaling:
      // Auto-scales down proportionally (0.35x ~ 0.65x) on near-field surfaces (0.3m ~ 0.7m desk/tabletop)
      // Maintains full 1.0x scale on standard ground plane distances (1.2m+)
      final double factor = (distanceMeters / 1.25).clamp(0.35, 1.0);
      effectiveScale = vector.Vector3(
        config.scale.x * factor,
        config.scale.y * factor,
        config.scale.z * factor,
      );
    }

    return ARNode(
      type: config.nodeType,
      uri: config.modelUri,
      scale: effectiveScale,
      position: config.position,
      eulerAngles: config.eulerAngles,
    );
  }

  void dispose() {
    _narrationService.dispose();
  }
}
