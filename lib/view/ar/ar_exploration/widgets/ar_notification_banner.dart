import 'package:flutter/material.dart';
import '../../../../model/entities/ar_object.dart';

/// UC100 BF-5: "System displays a notification banner at the top of the
/// screen indicating the number of nearby markers detected." (REQ_101_4)
///
/// Collapsed by default: tapping the pill toggles the panel open/closed.
/// When expanded, a dark panel lists every nearby marker, grouped into
/// distance bands (<80m, <150m, ...), each row showing a category icon +
/// name + distance. Rows are display-only — no tap action, no narration
/// trigger here. Starting narration only happens via tapping a marker
/// rendered in the camera view ([ARMarkerOverlay]'s `onTapMarker`).
class ARNotificationBanner extends StatefulWidget {
  const ARNotificationBanner({
    super.key,
    required this.markers,
  });

  /// Already sorted nearest-first by the ViewModel.
  final List<ARMarker> markers;

  @override
  State<ARNotificationBanner> createState() => _ARNotificationBannerState();
}

class _ARNotificationBannerState extends State<ARNotificationBanner> {
  bool _expanded = false;

  // Distance bucket ceilings shown in the list — <80m and <150m only.
  // Anything at or beyond the last ceiling is left out of the list
  // entirely (not lumped into the last band).
  static const List<int> _bandCeilings = [80, 150];

  Map<int, List<ARMarker>> _groupByBand() {
    final groups = <int, List<ARMarker>>{};
    for (final m in widget.markers) {
      final dist = m.distanceMeters ?? double.infinity;
      final ceilingIndex = _bandCeilings.indexWhere((c) => dist < c);
      if (ceilingIndex == -1) continue; // beyond 150m — not shown here
      final ceiling = _bandCeilings[ceilingIndex];
      groups.putIfAbsent(ceiling, () => []).add(m);
    }
    return groups;
  }

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

  @override
  Widget build(BuildContext context) {
    final groups = _groupByBand();
    final sortedCeilings = groups.keys.toList()..sort();
    final count = groups.values.fold<int>(0, (sum, list) => sum + list.length);
    final label = count == 0
        ? 'No heritage markers detected nearby'
        : count == 1
        ? '1 heritage marker detected nearby'
        : '$count heritage markers detected nearby';

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
              borderRadius: _expanded && groups.isNotEmpty
                  ? const BorderRadius.vertical(top: Radius.circular(14))
                  : BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: groups.isEmpty ? null : () => setState(() => _expanded = !_expanded),
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
                      if (groups.isNotEmpty)
                        Icon(
                          _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.black45,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // --- Expanded grouped list ---
            if (_expanded && groups.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 340),
                decoration: const BoxDecoration(
                  color: Color(0xE6142020), // dark translucent panel
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final ceiling in sortedCeilings) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                          child: Text(
                            '<${ceiling}M ATTRACTIONS',
                            style: const TextStyle(
                              color: Color(0xFFDE8A46),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        for (final m in groups[ceiling]!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MarkerRow(marker: m, icon: _iconFor(m)),
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

/// Display-only row — no tap/gesture handling of any kind. Narration is
/// started exclusively by tapping a marker rendered in the camera view
/// (see [ARMarkerOverlay]'s `onTapMarker`), never from this list.
class _MarkerRow extends StatelessWidget {
  const _MarkerRow({required this.marker, required this.icon});

  final ARMarker marker;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final distanceLabel = marker.distanceMeters == null
        ? '--'
        : '${marker.distanceMeters!.round()}m';

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
          Text(
            distanceLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}