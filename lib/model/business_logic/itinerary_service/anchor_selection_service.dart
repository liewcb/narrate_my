import 'clustering_service.dart';
import 'scoring_service.dart';

/// Represents a full day plan with an anchor and surrounding attractions.
class DailyPlan {
  final int dayIndex;
  final ScoredAttraction anchor;
  final List<ScoredAttraction> attractions;
  final DateTime? date;
  final bool isThemeParkDay;

  const DailyPlan({
    required this.dayIndex,
    required this.anchor,
    required this.attractions,
    this.date,
    this.isThemeParkDay = false,
  });

  /// Get attractions sorted with anchor first, then by score.
  List<ScoredAttraction> get sortedAttractions {
    final rest = attractions.where((a) => a != anchor).toList();
    rest.sort((a, b) => b.score.compareTo(a.score));
    return [anchor, ...rest];
  }

  @override
  String toString() =>
      'DailyPlan(dayIndex: $dayIndex, date: $date, anchor: ${anchor.place.name}, stops: ${attractions.length})';
}



/// Pipeline Step 5: Anchor Selection.
///
/// Picks one "hero" attraction per cluster (day). Theme parks become
/// full-day anchors; otherwise the highest-scored place anchors the day.
class AnchorSelectionService {
  static const List<String> _themeParkTypes = [
    'amusement_park',
    'theme_park',
    'water_park',
  ];

  /// Select one high-priority anchor for each geographic cluster.
  List<DailyPlan> selectAnchors({
    required List<Cluster> clusters,
    required DateTime startDate,
  }) {
    final List<DailyPlan> dailyPlans = [];

    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final date = startDate.add(Duration(days: i));
      if (cluster.attractions.isEmpty) {
        // Skip empty cluster – this should not happen, but fallback
        continue;
      }
      // 1. Check if any attraction in cluster is a theme park
      final hasThemePark = cluster.attractions.any((a) =>
          a.place.types.any(_themeParkTypes.contains));

      // 2. If theme park, make it the ONLY major activity that day
      if (hasThemePark) {
        final themePark = cluster.attractions.firstWhere((a) =>
            a.place.types.any(_themeParkTypes.contains));

        dailyPlans.add(DailyPlan(
          dayIndex: i,
          anchor: themePark,
          attractions: [themePark],
          date: date,
          isThemeParkDay: true,
        ));
        continue;
      }

      // 3. Normal case: select highest scored attraction as anchor
      final sorted = [...cluster.attractions]
        ..sort((a, b) => b.score.compareTo(a.score));
      final anchor = sorted.first;

      dailyPlans.add(DailyPlan(
        dayIndex: i,
        anchor: anchor,
        attractions: sorted,
        date: date,
        isThemeParkDay: false,
      ));
    }

    return dailyPlans;
  }

  List<DailyPlan> createDailyPlans({
    required List<Cluster> clusters,
    required DateTime startDate,
  }) {
    final List<DailyPlan> plans = [];

    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final date = startDate.add(Duration(days: i));

      // Sort by score descending
      final sorted = List<ScoredAttraction>.from(cluster.attractions)
        ..sort((a, b) => b.score.compareTo(a.score));

      // Use the highest‑scored as the anchor (no theme‑park special case)
      final anchor = sorted.first;

      plans.add(DailyPlan(
        dayIndex: i,
        anchor: anchor,
        attractions: sorted,
        date: date,
        isThemeParkDay: false,
      ));
    }

    return plans;
  }
}
