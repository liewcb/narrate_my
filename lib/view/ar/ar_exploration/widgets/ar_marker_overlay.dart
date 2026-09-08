import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
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
/// style. Vertically, markers anchor to a fixed midsection line offset by
/// relative altitude (marker vs. tourist) when both are known, so two
/// markers that share a bearing/distance bucket but sit at very different
/// heights don't render on top of each other.
///
/// Horizontally, a marker's position is normally its real, un-nudged
/// bearing — EXCEPT when two or more markers would render close enough
/// on screen to actually overlap (e.g. two POIs at nearly the same
/// lat/lng and altitude, both inside their own activation radius). In
/// that case [_computeFannedOutDeltas] spreads them apart, the same
/// technique map-label layout engines use for overlapping pins, so they
/// don't fully occlude one another. This only affects screen position,
/// never the marker's real bearing used elsewhere (e.g. primary-marker
/// selection upstream).
///
/// The minimum gap is derived from the marker's actual on-screen
/// footprint ([_markerFootprintWidth]) converted into degrees for the
/// current screen width/FOV, not a fixed angular constant — a fixed
/// degree threshold either under-spaces on a wide screen/narrow FOV
/// (markers still visually overlap) or over-spaces on a narrow
/// screen/wide FOV (markers drift apart for no reason). Spreading itself
/// is a symmetric multi-pass relaxation (push overlapping neighbors
/// apart from their shared midpoint, repeat), not a single left-to-right
/// sweep — a one-directional sweep pushes an entire cluster off to one
/// side, which for 3+ overlapping markers still leaves the trailing ones
/// under-spaced relative to their neighbor unless every prior gap was
/// already exactly the minimum.
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
    this.userAltitude,
    this.horizontalFovDegrees = 60,
    this.pitchToleranceDegrees = 35,
    this.edgeFadeDegrees = 10,
    this.markerSpacingPaddingPx = 16,
    this.onTapMarker,
  });

  final List<ARMarker> nearbyMarkers;

  /// Tourist's current GPS altitude (meters), if available. Combined with
  /// each marker's own [ARMarker.altitude] to offset that marker
  /// vertically from the fixed anchor line — otherwise two markers at the
  /// same bearing/distance but very different heights (e.g. a ground
  /// floor entrance vs. a rooftop) land on the exact same screen point.
  final double? userAltitude;

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

  /// Extra breathing room (logical pixels) added on top of a marker's
  /// footprint ([_markerFootprintWidth]) when computing the minimum
  /// on-screen gap between two markers before fan-out kicks in. `0`
  /// means "just barely not touching"; the default leaves a small visible
  /// sliver of camera feed between adjacent markers instead of them
  /// sitting edge-to-edge. Purely a screen-position nudge: the marker's
  /// real bearing (used upstream for primary-marker selection, tap
  /// targets' underlying data, etc.) is untouched.
  final double markerSpacingPaddingPx;

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
    // still every marker renders at its real, un-nudged position (aside
    // from the bearing fan-out below, which only applies when markers
    // would otherwise collide).
    final markers = [...nearbyMarkers]
      ..sort((a, b) => (b.distanceMeters ?? 0).compareTo(a.distanceMeters ?? 0));

    // Precompute fanned-out horizontal deltas once per build, keyed by
    // marker id, so markers that would otherwise render close enough to
    // overlap get spread apart instead of stacking on the same screen
    // column. Needs screenSize because the minimum gap is derived in
    // pixels, then converted to degrees for this specific screen/FOV.
    final fannedOutDeltas = _computeFannedOutDeltas(markers, size);

    return AnimatedOpacity(
      duration: _animDuration,
      opacity: verticalFactor,
      child: Stack(
        children: [
          for (final marker in markers)
            _buildMarker(context, marker, size, fannedOutDeltas[marker.markerId]),
        ],
      ),
    );
  }

  /// Approximate on-screen width (logical px) a marker occupies for
  /// spacing purposes. The icon circle itself is a fixed 72px (see
  /// [_LandmarkMarker]), but the name pill underneath it sizes to text
  /// and can easily run wider — e.g. "Istana Budaya Performing Arts
  /// Centre" comfortably exceeds 72px at 12.5pt. Using the icon width
  /// alone as the spacing basis is exactly the kind of under-spacing
  /// that left a visible fraction of markers still overlapping: two
  /// markers could clear the 72px icon-to-icon gap while their name
  /// pills still collided. This is a fixed estimate, not a measurement
  /// (the text isn't laid out until build), so it errs generous rather
  /// than tight.
  static const double _markerFootprintWidth = 140;

  /// Computes each visible marker's heading-relative horizontal delta
  /// (bearing minus device heading, normalized to [-180, 180]), then
  /// resolves any that would overlap on screen by symmetrically pushing
  /// them apart until every adjacent pair clears the minimum pixel gap.
  ///
  /// The minimum gap starts in pixels
  /// ([_markerFootprintWidth] + [markerSpacingPaddingPx]) and is
  /// converted to degrees using the actual screen width and
  /// [horizontalFovDegrees] for this build, so spacing tracks the real
  /// rendered size instead of an arbitrary fixed angle — a fixed-degree
  /// threshold was the main source of markers still visually
  /// overlapping: on a wide screen, or a narrow FOV, a few degrees maps
  /// to far fewer pixels than a marker actually occupies.
  ///
  /// Resolution is a multi-pass relaxation rather than a single
  /// left-to-right sweep: each pass walks adjacent pairs and, for any
  /// pair closer than the minimum gap, moves each one away from their
  /// shared midpoint by half the shortfall. Repeating this converges to
  /// a symmetric spread even for clusters of 3+ overlapping markers,
  /// where a one-directional sweep would push the whole cluster toward
  /// one side and leave later pairs under-spaced relative to a neighbor
  /// that had already been shifted. Capped at [_maxFanOutPasses]
  /// iterations — real clusters here are small (single digits), so this
  /// converges in practice well before the cap.
  ///
  /// Markers with no bearing, or fully outside the fade margin, are
  /// omitted from the returned map; [_buildMarker] treats a missing
  /// entry the same as "not visible" and renders nothing, matching the
  /// original out-of-FOV behavior.
  Map<String, double> _computeFannedOutDeltas(List<ARMarker> markers, Size screenSize) {
    final halfFov = horizontalFovDegrees / 2;
    final fadeEnd = halfFov + edgeFadeDegrees;

    final entries = <MapEntry<ARMarker, double>>[];
    for (final marker in markers) {
      final bearing = marker.bearingFromUser;
      if (bearing == null) continue;

      double delta = (bearing - deviceHeadingDegrees) % 360;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;

      if (delta.abs() > fadeEnd) continue; // fully outside, no entry
      entries.add(MapEntry(marker, delta));
    }

    // Sort left-to-right by (still-real) bearing delta before spreading,
    // independent of the farthest-first draw order used for the Stack.
    entries.sort((a, b) => a.value.compareTo(b.value));

    final degreesPerPixel = horizontalFovDegrees / screenSize.width;
    final minGapDegrees =
        (_markerFootprintWidth + markerSpacingPaddingPx) * degreesPerPixel;

    for (var pass = 0; pass < _maxFanOutPasses; pass++) {
      var movedAny = false;
      for (var i = 1; i < entries.length; i++) {
        final gap = entries[i].value - entries[i - 1].value;
        if (gap >= minGapDegrees) continue;
        final shift = (minGapDegrees - gap) / 2;
        entries[i - 1] = MapEntry(entries[i - 1].key, entries[i - 1].value - shift);
        entries[i] = MapEntry(entries[i].key, entries[i].value + shift);
        movedAny = true;
      }
      if (!movedAny) break;
    }

    return {for (final e in entries) e.key.markerId: e.value};
  }

  static const int _maxFanOutPasses = 8;

  /// Vertical screen anchor for [marker], offset from the fixed
  /// midsection line by how much higher/lower the marker's altitude is
  /// than the tourist's own. Markers above the tourist (positive relative
  /// altitude) move up the screen (smaller dy); markers below move down.
  ///
  /// This is what actually distinguishes two markers that share the same
  /// bearing/distance bucket but sit at very different heights (e.g. a
  /// plaza-level plaque vs. a rooftop feature on the same building) — the
  /// old fixed 0.34 line put every marker on top of every other one
  /// regardless of height. Falls back to the fixed line when either
  /// altitude reading is unavailable, since a half-known delta is worse
  /// than no offset at all. Complements (doesn't replace)
  /// [_computeFannedOutDeltas]'s horizontal nudge: that one handles
  /// markers with near-identical bearing, this one handles markers with
  /// near-identical bearing AND altitude/lat-lng, which fan-out alone
  /// would still separate horizontally but this keeps meaningfully
  /// distinct in height when the data supports it.
  double _verticalAnchor(ARMarker marker, Size screenSize) {
    const baseDyFraction = 0.34;
    final baseDy = screenSize.height * baseDyFraction;

    final markerAltitude = marker.altitude;
    if (markerAltitude == null || userAltitude == null) {
      return baseDy;
    }

    final relativeAltitude = markerAltitude - userAltitude!;
    final verticalRange = screenSize.height * AppConfig.altitudeVerticalRangeFraction;
    final altitudeOffset =
        (relativeAltitude / AppConfig.maxExpectedAltitudeRangeMeters) * verticalRange;

    final minDy = screenSize.height * AppConfig.markerMinDyFraction;
    final maxDy = screenSize.height * AppConfig.markerMaxDyFraction;

    return (baseDy - altitudeOffset).clamp(minDy, maxDy);
  }

  double _fadeFactor(double value, {required double fadeStart, required double fadeEnd}) {
    if (value <= fadeStart) return 1;
    if (value >= fadeEnd) return 0;
    return 1 - (value - fadeStart) / (fadeEnd - fadeStart);
  }

  Widget _buildMarker(
      BuildContext context,
      ARMarker marker,
      Size screenSize,
      double? fannedOutDelta,
      ) {
    // No entry means either no bearing or fully outside the fade margin
    // (see _computeFannedOutDeltas) — same "don't build it at all"
    // behavior as the original bearing-null / out-of-FOV checks.
    if (fannedOutDelta == null) return const SizedBox.shrink();
    final delta = fannedOutDelta;

    final halfFov = horizontalFovDegrees / 2;
    final fadeEnd = halfFov + edgeFadeDegrees;

    // Fade/opacity and the "turning away" 3D tilt are still driven by
    // how close the marker's REAL bearing delta is to the FOV edge, not
    // its fanned-out screen delta — otherwise a marker nudged aside by
    // collision avoidance could visually fade/tilt as if it were near
    // the edge when it isn't really facing that way yet. Recomputed
    // directly from the marker's own bearing (cheap, and simpler than
    // threading the pre-spread value through the fan-out map).
    final bearing = marker.bearingFromUser;
    double realDelta = ((bearing ?? deviceHeadingDegrees) - deviceHeadingDegrees) % 360;
    if (realDelta > 180) realDelta -= 360;
    if (realDelta < -180) realDelta += 360;

    final horizontalFactor = _fadeFactor(
      realDelta.abs(),
      fadeStart: halfFov - edgeFadeDegrees,
      fadeEnd: fadeEnd,
    );

    // Position uses the fanned-out delta (may be nudged past the raw
    // marker's own bearing to avoid overlapping a neighbor); it can
    // legitimately slide a little past the nominal 0..1 range in the
    // fade zone, same as before.
    final xFraction = (delta + halfFov) / horizontalFovDegrees;
    final dx = xFraction * screenSize.width;

    final dy = _verticalAnchor(marker, screenSize);

    // Icon's own width, used only to center it on dx — deliberately NOT
    // [_markerFootprintWidth], which is the wider spacing estimate that
    // also accounts for the name pill below the icon.
    const width = 72.0;

    // "Turning away" effect as a marker nears the edge of the FOV: a
    // small 3D rotation in the direction it's exiting (left/right),
    // paired with the fade, instead of an instant cut. Driven by the
    // real delta's sign (see comment above), not the fanned-out one.
    final turnAngle = (1 - horizontalFactor) * realDelta.sign * 0.9; // radians, caps ~51°

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