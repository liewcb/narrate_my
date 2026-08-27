import 'package:flutter/material.dart';
import '../../../../model/entities/ar_object.dart';

/// Positions markers over the camera feed using compass-based
/// "POI browser" AR: each marker's horizontal screen position is derived
/// from the angular difference between the device heading and the
/// marker's bearing, mapped across the camera's horizontal field of view.
/// Device *pitch* additionally gates the whole layer: tip the phone too
/// far toward the sky or the ground and there's nothing left to anchor a
/// marker to, so it fades away.
///
/// Every marker currently inside the camera's FOV renders identically
/// (the orange "landmark" pin) — there's no separate dimmed/secondary
/// style and no artificial spacing between markers that happen to land
/// close together. Each one sits exactly where its real bearing places
/// it.
///
/// This is a 2D heading-anchored overlay (no SLAM/plane detection) —
/// intentionally simple and matches what UC100 BF-6/BF-7 actually needs:
/// "anchoring the AR marker overlay onto the building(s) the tourist is
/// currently capturing with the camera."
class ARMarkerOverlay extends StatelessWidget {
  const ARMarkerOverlay({
    super.key,
    required this.nearbyMarkers,
    this.primaryMarker,
    required this.deviceHeadingDegrees,
    this.devicePitchDegrees = 0,
    this.horizontalFovDegrees = 60,
    this.pitchToleranceDegrees = 35,
    this.edgeFadeDegrees = 10,
    this.onTapMarker,
  });

  final List<ARMarker> nearbyMarkers;

  /// No longer affects rendering (every in-FOV marker looks the same) —
  /// kept only in case a future screen wants to know which marker the
  /// tourist is most directly facing (BF-7).
  final ARMarker? primaryMarker;

  final double deviceHeadingDegrees;

  /// 0° = phone held level, pointing at the horizon. See
  /// [OrientationService] for sign convention.
  final double devicePitchDegrees;

  final double horizontalFovDegrees;

  /// Max |pitch| before the whole marker layer is hidden.
  final double pitchToleranceDegrees;

  /// Width, in degrees, of the soft fade zone at the horizontal FOV edge
  /// and at the pitch tolerance boundary — markers ease out instead of
  /// snapping away the instant they cross the line.
  final double edgeFadeDegrees;

  final ValueChanged<ARMarker>? onTapMarker;

  static const _animDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Phone pitched too far up/down: nothing to anchor markers to, so
    // fade the entire layer out rather than leaving markers stuck on
    // screen while facing the sky or the ground.
    final verticalFactor = _fadeFactor(
      devicePitchDegrees.abs(),
      fadeStart: pitchToleranceDegrees - edgeFadeDegrees,
      fadeEnd: pitchToleranceDegrees,
    );

    if (verticalFactor <= 0) {
      return const SizedBox.shrink();
    }

    // Draw farthest-first so a closer marker never ends up hidden behind
    // a farther one that happens to land at a similar screen position —
    // still every marker renders at its real, un-nudged position.
    final markers = [...nearbyMarkers]
      ..sort((a, b) => (b.distanceMeters ?? 0).compareTo(a.distanceMeters ?? 0));

    return AnimatedOpacity(
      duration: _animDuration,
      opacity: verticalFactor,
      child: Stack(
        children: [
          for (final marker in markers) _buildMarker(context, marker, size),
        ],
      ),
    );
  }

  double _fadeFactor(double value, {required double fadeStart, required double fadeEnd}) {
    if (value <= fadeStart) return 1;
    if (value >= fadeEnd) return 0;
    return 1 - (value - fadeStart) / (fadeEnd - fadeStart);
  }

  Widget _buildMarker(BuildContext context, ARMarker marker, Size screenSize) {
    final bearing = marker.bearingFromUser;
    if (bearing == null) return const SizedBox.shrink();

    // Signed angular offset of this marker relative to where the device
    // is currently pointing, normalized to [-180, 180].
    double delta = (bearing - deviceHeadingDegrees) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;

    final halfFov = horizontalFovDegrees / 2;
    final fadeEnd = halfFov + edgeFadeDegrees;

    // Fully outside even the fade margin — don't build it at all. Keeps
    // the widget tree light and avoids leaving an invisible, still-
    // tappable marker sitting off-screen.
    if (delta.abs() > fadeEnd) return const SizedBox.shrink();

    final horizontalFactor = _fadeFactor(
      delta.abs(),
      fadeStart: halfFov - edgeFadeDegrees,
      fadeEnd: fadeEnd,
    );

    final xFraction = (delta + halfFov) / horizontalFovDegrees; // 0..1 (can slide slightly past in the fade zone)
    final dx = xFraction * screenSize.width;

    // Fixed anchor height matching where a building midsection would
    // read on screen — same for every marker, no vertical stacking.
    final dy = screenSize.height * 0.34;

    const width = 72.0;

    // "Turning away" effect as a marker nears the edge of the FOV: a
    // small 3D rotation in the direction it's exiting (left/right),
    // paired with the fade, instead of an instant cut.
    final turnAngle = (1 - horizontalFactor) * delta.sign * 0.9; // radians, caps ~51°

    return AnimatedPositioned(
      key: ValueKey(marker.markerId),
      duration: _animDuration,
      curve: Curves.easeOut,
      left: dx - width / 2,
      top: dy,
      child: AnimatedOpacity(
        duration: _animDuration,
        opacity: horizontalFactor,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(turnAngle),
          child: GestureDetector(
            onTap: horizontalFactor > 0.3 ? () => onTapMarker?.call(marker) : null,
            child: _LandmarkMarker(marker: marker),
          ),
        ),
      ),
    );
  }
}

class _LandmarkMarker extends StatelessWidget {
  const _LandmarkMarker({required this.marker});
  final ARMarker marker;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFDE8A46).withValues(alpha: 0.18),
            border: Border.all(color: const Color(0xFFDE8A46), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDE8A46).withValues(alpha: 0.4),
                blurRadius: 24,
              ),
            ],
          ),
          child: const Icon(Icons.account_balance, color: Color(0xFFDE8A46), size: 30),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDE8A46), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4))],
          ),
          child: Text(
            marker.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}