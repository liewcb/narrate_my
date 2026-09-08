import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_vm.dart';
import '../../../../model/entities/ar_object.dart';

/// UC100 BF-5: "System displays a notification banner at the top of the
/// screen indicating the number of nearby markers detected." (REQ_101_4)
///
/// Collapsed by default: tapping the pill toggles the panel open/closed.
/// When expanded, a dark panel lists every relevant marker split into two
/// sections:
///
///   - **Available** — the tourist is already standing inside that
///     marker's own [ARMarker.activationRadiusMeters] activation zone
///     (BF-6/BF-7 territory). No distance/direction needed here — they
///     can just look around the camera view and tap it.
///   - **Nearby** — outside the activation zone but within
///     [_nearbyMaxMeters]. Each row shows the live walking distance
///     *and* a relative Left/Right/Ahead/Behind direction (derived from
///     the marker's bearing vs. the device's current compass heading),
///     so the tourist knows which way to turn and how far to go, e.g.
///     "Left 157m".
///
/// Rows are display-only — no tap action, no narration trigger here.
/// Starting narration only happens via tapping a marker rendered in the
/// camera view ([ARMarkerOverlay]'s `onTapMarker`).
class ARNotificationBanner extends StatefulWidget {
  const ARNotificationBanner({
    super.key,
    required this.markers,
    required this.deviceHeadingDegrees,
  });

  /// Already sorted nearest-first by the ViewModel.
  final List<ARMarker> markers;

  /// Current device compass heading (0-360°). Used only to turn each
  /// "Nearby" marker's absolute live bearing into a relative direction
  /// label for display — has no effect on the Available section.
  final double deviceHeadingDegrees;

  @override
  State<ARNotificationBanner> createState() => _ARNotificationBannerState();
}

class _ARNotificationBannerState extends State<ARNotificationBanner> {
  bool _expanded = false;

  // Markers beyond this are left out of the "Nearby" list entirely (not
  // lumped into a catch-all band) — keeps the panel focused on what's
  // actually walkable right now rather than every marker ever fetched.
  static const double _nearbyMaxMeters = 150;

  // Half-width, in degrees, of the "Ahead"/"Behind" cones centered on
  // 0°/180°. Outside those cones the marker is called Left or Right
  // depending on the sign of the relative bearing.
  static const double _directionConeDegrees = 25;

  static const _distanceAnimDuration = Duration(milliseconds: 260);

  List<ARMarker> get _available =>
      widget.markers.where((m) => m.isWithinActivationRadius).toList();

  List<ARMarker> get _nearby => widget.markers
      .where(
        (m) =>
    !m.isWithinActivationRadius &&
        (m.distanceMeters ?? double.infinity) < _nearbyMaxMeters,
  )
      .toList();

  IconData _iconFor(ARMarker marker) {
    final labels = marker.labels.map((l) => l.toLowerCase()).toSet();
    if (labels.contains('skybridge') || labels.contains('bridge')) return Icons.architecture;
    if (labels.contains('tower')) return Icons.location_city;
    if (labels.contains('lake') || labels.contains('water') || labels.contains('nature')) {
      return Icons.water;
    }
    if (labels.contains('temple') || labels.contains('worship')) return Icons.temple_buddhist;
    if (labels.contains('restaurant') || labels.contains('food')) return Icons.restaurant;
    return Icons.place;
  }

  /// Relative direction label (Left/Right/Ahead/Behind) the tourist needs
  /// to turn toward [marker], derived from the signed angular difference
  /// between the marker's live bearing and the device's current compass
  /// heading. Same sign convention [ARMarkerOverlay] uses for its
  /// on-screen X position: a positive delta means the marker sits
  /// clockwise from where the phone is pointing, i.e. to the right.
  String? _directionFor(ARMarker marker) {
    final bearing = marker.bearingFromUser;
    if (bearing == null) return null;

    double delta = (bearing - widget.deviceHeadingDegrees) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;

    if (delta.abs() <= _directionConeDegrees) {
      return AppLocalizations.t('ar.directionAhead');
    }
    if (delta.abs() >= 180 - _directionConeDegrees) {
      return AppLocalizations.t('ar.directionBehind');
    }
    return delta > 0
        ? AppLocalizations.t('ar.directionRight')
        : AppLocalizations.t('ar.directionLeft');
  }

  /// Formats a live distance for display: whole meters under 1km, and
  /// kilometers to one decimal place beyond that (matches how map/nav
  /// apps switch units, and avoids a jittery 4-digit meter count for
  /// markers far across a site). Rounded to the nearest meter (or 100m
  /// once in km) so the label doesn't visibly flicker between adjacent
  /// values as raw GPS readings dance around by a meter or two between
  /// updates.
  static String formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
    return '${meters.round()}m';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    final available = _available;
    final nearby = _nearby;
    final count = available.length + nearby.length;
    final label = count == 0
        ? AppLocalizations.t('ar.noMarkersNearby')
        : count == 1
        ? AppLocalizations.t('ar.markerDetectedOne')
        : AppLocalizations.t('ar.markersDetectedMany')
        .replaceFirst('{count}', '$count');

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Collapsed pill header ---
            Material(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: _expanded && count > 0
                  ? const BorderRadius.vertical(top: Radius.circular(14))
                  : BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: count == 0 ? null : () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCEADA),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.shield_outlined, size: 15, color: Color(0xFFB5652A)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
                        ),
                      ),
                      if (count > 0)
                        Icon(
                          _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.black45,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // --- Expanded, sectioned list ---
            if (_expanded && count > 0)
              Container(
                constraints: const BoxConstraints(maxHeight: 420),
                decoration: const BoxDecoration(
                  color: Color(0xE6142020), // dark translucent panel
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (available.isNotEmpty) ...[
                        _SectionHeader(
                          label: AppLocalizations.t('ar.availableSection'),
                          count: available.length,
                          color: const Color(0xFF6FCF97),
                        ),
                        for (final m in available)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MarkerRow(
                              marker: m,
                              icon: _iconFor(m),
                              trailing: _AvailableBadge(),
                            ),
                          ),
                        if (nearby.isNotEmpty) const SizedBox(height: 6),
                      ],
                      if (nearby.isNotEmpty) ...[
                        _SectionHeader(
                          label: AppLocalizations.t('ar.nearbySection'),
                          count: nearby.length,
                          color: const Color(0xFFDE8A46),
                        ),
                        for (final m in nearby)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MarkerRow(
                              marker: m,
                              icon: _iconFor(m),
                              trailing: _DistanceDirection(
                                direction: _directionFor(m),
                                distanceLabel: m.distanceMeters == null
                                    ? '--'
                                    : formatDistance(m.distanceMeters!),
                                animDuration: _distanceAnimDuration,
                              ),
                            ),
                          ),
                      ],
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 4, bottom: 4),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small caps section label + count, shared by both the Available and
/// Nearby lists (only the accent color differs).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Green "Available" pill shown as the trailing widget for a marker the
/// tourist is already standing inside the activation zone of.
class _AvailableBadge extends StatelessWidget {
  const _AvailableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF6FCF97).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF6FCF97).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 12, color: Color(0xFF6FCF97)),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.t('ar.markerAvailableBadge'),
            style: const TextStyle(
              color: Color(0xFF6FCF97),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Trailing widget for a "Nearby" row: relative direction + live
/// distance, e.g. "Left 157m". Wrapped in an [AnimatedSwitcher] keyed by
/// the formatted string so that as GPS/compass updates nudge the number
/// or direction, the change fades/slides in place instead of hard-
/// snapping to new text on every rebuild.
class _DistanceDirection extends StatelessWidget {
  const _DistanceDirection({
    required this.direction,
    required this.distanceLabel,
    required this.animDuration,
  });

  final String? direction;
  final String distanceLabel;
  final Duration animDuration;

  @override
  Widget build(BuildContext context) {
    final text = direction == null ? distanceLabel : '$direction $distanceLabel';

    return ClipRect(
      child: AnimatedSwitcher(
        duration: animDuration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axis: Axis.horizontal,
            axisAlignment: -1,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
        ),
        child: Text(
          text,
          key: ValueKey(text),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Display-only row — no tap/gesture handling of any kind. Narration is
/// started exclusively by tapping a marker rendered in the camera view
/// (see [ARMarkerOverlay]'s `onTapMarker`), never from this list.
class _MarkerRow extends StatelessWidget {
  const _MarkerRow({required this.marker, required this.icon, required this.trailing});

  final ARMarker marker;
  final IconData icon;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: const Color(0xFFDE8A46)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              marker.name,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}