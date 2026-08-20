import 'package:flutter/material.dart';
import '../../../../model/entities/ar_object.dart';

/// Positions markers over the camera feed using compass-based
/// "POI browser" AR: each marker's horizontal screen position is derived
/// from the angular difference between the device heading and the
/// marker's bearing, mapped across the camera's horizontal field of view.
///
/// This is a 2D heading-anchored overlay (no SLAM/plane detection) —
/// intentionally simple and matches what UC100 BF-6/BF-7 actually needs:
/// "anchoring the primary AR marker overlay onto the building the tourist
/// is directly facing."
class ARMarkerOverlay extends StatelessWidget {
  const ARMarkerOverlay({
    super.key,
    required this.nearbyMarkers,
    required this.primaryMarker,
    required this.deviceHeadingDegrees,
    this.horizontalFovDegrees = 60,
    this.onTapMarker,
  });

  final List<ARMarker> nearbyMarkers;
  final ARMarker? primaryMarker;
  final double deviceHeadingDegrees;
  final double horizontalFovDegrees;
  final ValueChanged<ARMarker>? onTapMarker;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        for (final marker in nearbyMarkers)
          if (marker.markerId != primaryMarker?.markerId)
            _buildMarker(context, marker, size, isPrimary: false),
        if (primaryMarker != null)
          _buildMarker(context, primaryMarker!, size, isPrimary: true),
      ],
    );
  }

  Widget _buildMarker(BuildContext context, ARMarker marker, Size screenSize, {required bool isPrimary}) {
    final bearing = marker.bearingFromUser;
    if (bearing == null) return const SizedBox.shrink();

    // Signed angular offset of this marker relative to where the device
    // is currently pointing, normalized to [-180, 180].
    double delta = (bearing - deviceHeadingDegrees) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;

    // Outside the camera's FOV — don't render (a future pass could show
    // an edge indicator here instead of hiding it entirely).
    final halfFov = horizontalFovDegrees / 2;
    if (delta.abs() > halfFov) return const SizedBox.shrink();

    final xFraction = (delta + halfFov) / horizontalFovDegrees; // 0..1
    final dx = xFraction * screenSize.width;

    // Slight vertical variance by distance just so multiple markers
    // don't perfectly overlap; primary marker sits at a fixed anchor
    // height matching where a building midsection would read on screen.
    final dy = isPrimary ? screenSize.height * 0.32 : screenSize.height * 0.38;

    return Positioned(
      left: dx - (isPrimary ? 36 : 20),
      top: dy,
      child: GestureDetector(
        onTap: () => onTapMarker?.call(marker),
        child: isPrimary ? _PrimaryMarker(marker: marker) : _SecondaryMarker(marker: marker),
      ),
    );
  }
}

class _PrimaryMarker extends StatelessWidget {
  const _PrimaryMarker({required this.marker});
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

class _SecondaryMarker extends StatelessWidget {
  const _SecondaryMarker({required this.marker});
  final ARMarker marker;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            marker.name,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
