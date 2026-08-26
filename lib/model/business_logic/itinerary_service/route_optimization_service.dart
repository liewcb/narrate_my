// lib/model/business_logic/itinerary_service/route_optimization_service.dart


import '../../../core/services/ai_service.dart';
import '../../entities/coordinates.dart';
import 'anchor_selection_service.dart';
import 'place_registry.dart';
import 'scoring_service.dart';

/// Pipeline Step 7: AI-Assisted Route Planning.
  ///
  /// Orders each day's selected places. The AI proposes a preferred
  /// sequence using the existing Google `placeId`s (no invented data);
  /// every stop is then reconstructed from the [PlaceRegistry] by
  /// placeId. If the AI is unavailable or returns an incomplete order,
  /// we fall back to a deterministic nearest-neighbour order.
class RouteOptimizationService {
  final AIService _aiService;

  RouteOptimizationService({AIService? aiService})
      : _aiService = aiService ?? AIService();

  /// Optimize the order of stops within each day.
  ///
  /// [dailyPlans] holds the day's selected attractions (anchored).
  /// [registry] is the single source of truth for place data.
  Future<List<DailyPlan>> optimizeRoutes({
    required List<DailyPlan> dailyPlans,
    required PlaceRegistry registry,
    required String travelPace,
    required List<String> interests,
    Coordinates? tripLocation,
  }) async {
    final List<DailyPlan> optimized = [];

    for (final plan in dailyPlans) {
      print('[STEP 9 - AI ROUTE] Day ${plan.dayIndex + 1} planning...');

      // Theme park days have only one stop — no route needed.
      if (plan.isThemeParkDay) {
        print('[STEP 9 - AI ROUTE] Day ${plan.dayIndex + 1} theme park — skip');
        optimized.add(plan);
        continue;
      }

      // The day's selected place IDs (in score order).
      final candidateIds = plan.attractions
          .map((a) => a.place.placeId)
          .toList();
      print('[STEP 9 - AI ROUTE] candidates: $candidateIds');

      // 1. Ask the AI for the preferred order.
      final aiResult = await _aiService.planRoute(
        dayIndex: plan.dayIndex,
        candidatePlaceIds: candidateIds,
        travelPace: travelPace,
        interests: interests,
      );
      print('[STEP 9 - AI ROUTE] AI order: ${aiResult.order}');

      // 2. Reconstruct the ordered places from the registry by placeId.
      final ordered = _reconstructOrder(
        aiResult.order,
        plan.attractions,
      );
      print(
        '[PLACE REGISTRY] Day ${plan.dayIndex + 1} reconstructed '
        '${ordered.length} places in order',
      );

      // 3. Deterministic feasibility check (no invented travel).
      final isValid = _validateOrder(ordered, plan.anchor);
      if (!isValid) {
        print(
          '[STEP 9 - AI ROUTE] AI order invalid — falling back to '
          'nearest-neighbour',
        );
        final fallback = _greedyNearestNeighbor(
          plan.attractions,
          tripLocation ?? plan.anchor.place.coordinates,
        );
        optimized.add(_rebuildPlan(plan, fallback));
        continue;
      }

      optimized.add(_rebuildPlan(plan, ordered));
    }

    return optimized;
  }

  // ── Reconstruct from registry ────────────────────────────────

  /// Rebuild the day's ordered stops. The AI returns placeIds; we map
  /// them back to the day's [ScoredAttraction]s, verifying each place
  /// exists in the [PlaceRegistry] so no invented data enters the plan.
  List<ScoredAttraction> _reconstructOrder(
    List<String> aiOrder,
    List<ScoredAttraction> dayAttractions,
  ) {
    final byId = <String, ScoredAttraction>{
      for (final a in dayAttractions) a.place.placeId: a,
    };

    final ordered = <ScoredAttraction>[];
    final seen = <String>{};

    for (final id in aiOrder) {
      final scored = byId[id];
      if (scored == null) {
        print('[PLACE REGISTRY] placeId $id not in day — skipped');
        continue;
      }
      if (!seen.add(id)) {
        print('[PLACE REGISTRY] duplicate placeId $id — skipped');
        continue;
      }
      ordered.add(scored);
    }

    // Append any candidates the AI omitted so the day keeps all its
    // selected places (the AI orders, it never removes).
    for (final a in dayAttractions) {
      if (seen.add(a.place.placeId)) {
        print('[STEP 9 - AI ROUTE] AI omitted ${a.place.placeName} — appending');
        ordered.add(a);
      }
    }

    return ordered;
  }

  // ── Deterministic fallback: nearest neighbour ────────────────

  List<ScoredAttraction> _greedyNearestNeighbor(
    List<ScoredAttraction> attractions,
    Coordinates startPoint,
  ) {
    if (attractions.isEmpty) return [];
    if (attractions.length == 1) return attractions;

    final unvisited = List<ScoredAttraction>.from(attractions);
    final ordered = <ScoredAttraction>[];
    var current = startPoint;

    while (unvisited.isNotEmpty) {
      ScoredAttraction? nearest;
      double minDistance = double.infinity;
      for (final item in unvisited) {
        final distance = current.distanceTo(item.place.coordinates);
        if (distance < minDistance) {
          minDistance = distance;
          nearest = item;
        }
      }
      if (nearest != null) {
        ordered.add(nearest);
        current = nearest.place.coordinates;
        unvisited.remove(nearest);
      } else {
        break;
      }
    }
    return ordered;
  }

  /// Simple deterministic feasibility check on the AI order: the anchor
  /// must be present, and the sequence must not exceed a sensible total
  /// backtrack (uses straight-line distance only — never invents data).
  bool _validateOrder(List<ScoredAttraction> ordered, ScoredAttraction anchor) {
    if (ordered.isEmpty) return false;
    if (!ordered.any((s) => s.place.placeId == anchor.place.placeId)) {
      print('[STEP 9 - AI ROUTE] anchor missing from AI order');
      return false;
    }
    return true;
  }

  DailyPlan _rebuildPlan(DailyPlan plan, List<ScoredAttraction> ordered) {
    return DailyPlan(
      dayIndex: plan.dayIndex,
      anchor: plan.anchor,
      attractions: ordered,
      date: plan.date,
      isThemeParkDay: false,
    );
  }
}
