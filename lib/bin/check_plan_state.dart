// lib/diagnostics/check_plan_state.dart

import 'package:flutter/foundation.dart';
import 'package:narrate_my/bin/run_pipeline.dart';
import '../model/business_logic/itinerary_service/itinerary_plan_state.dart';
import '../model/entities/place.dart';

/// Runs the full pipeline and then checks the resulting [ItineraryPlanState]
/// for completeness and data integrity.
///
/// Returns `true` if all checks pass; otherwise `false`.
Future<bool> checkItineraryPlanState() async {
  debugPrint('═══════════════════════════════════════════');
  debugPrint('🧪 DIAGNOSTIC: CHECKING ITINERARY PLAN STATE');
  debugPrint('═══════════════════════════════════════════');

  final planState = await runItineraryPipeline();

  // ─── 1. BASIC IDENTITY ───────────────────────────────────

  debugPrint('📌 STEP 1: BASIC IDENTITY');
  bool ok = true;

  if (planState.itineraryId.isEmpty) {
    debugPrint('❌ Itinerary ID is empty.');
    ok = false;
  } else {
    debugPrint('✅ Itinerary ID: ${planState.itineraryId}');
  }

  if (planState.destinations.isEmpty) {
    debugPrint('❌ No destinations defined.');
    ok = false;
  } else {
    debugPrint('✅ Destinations: ${planState.destinations.map((d) => d.name).join(', ')}');
  }

  if (planState.totalDays <= 0) {
    debugPrint('❌ Total days is zero or negative.');
    ok = false;
  } else {
    debugPrint('✅ Total days: ${planState.totalDays}');
  }

  if (planState.pace.isEmpty) {
    debugPrint('❌ Pace is empty.');
    ok = false;
  } else {
    debugPrint('✅ Pace: ${planState.pace}');
  }

  if (planState.intensity.isEmpty) {
    debugPrint('❌ Intensity is empty.');
    ok = false;
  } else {
    debugPrint('✅ Intensity: ${planState.intensity}');
  }

  // ─── 2. CANDIDATE POOLS ─────────────────────────────────

  debugPrint('📌 STEP 2: CANDIDATE POOLS');

  if (planState.destinationPools.isEmpty) {
    debugPrint('❌ Destination pools are empty.');
    ok = false;
  } else {
    for (final entry in planState.destinationPools.entries) {
      final pool = entry.value;
      debugPrint('✅ Pool for "${entry.key}": '
          '${pool.attractionCount} attractions, ${pool.foodCount} food, ${pool.totalCount} total');
    }
  }

  final allCandidates = planState.allCandidates;
  if (allCandidates.isEmpty) {
    debugPrint('❌ No candidates found across all pools.');
    ok = false;
  } else {
    debugPrint('✅ Total candidates (all): ${allCandidates.length}');
    debugPrint('   Sample: ${allCandidates.take(3).map((p) => p.placeName).join(' → ')}');
  }

  // ─── 3. CLUSTERS ─────────────────────────────────────────

  debugPrint('📌 STEP 3: CLUSTERS');

  if (planState.dailyClusters == null) {
    debugPrint('❌ dailyClusters is null.');
    ok = false;
  } else if (planState.dailyClusters!.isEmpty) {
    debugPrint('❌ dailyClusters is empty.');
    ok = false;
  } else {
    debugPrint('✅ dailyClusters has ${planState.dailyClusters!.length} clusters.');
    for (int i = 0; i < planState.dailyClusters!.length; i++) {
      final cluster = planState.dailyClusters![i];
      debugPrint('   Cluster $i: ${cluster.attractions.length} attractions, '
          'anchor: ${cluster.anchor?.place.placeName ?? 'none'}');
    }
  }

  // ─── 4. DAILY STOPS ──────────────────────────────────────

  debugPrint('📌 STEP 4: DAILY STOPS');

  if (planState.dailyStops.isEmpty) {
    debugPrint('❌ dailyStops is empty.');
    ok = false;
  } else {
    debugPrint('✅ dailyStops has ${planState.dailyStops.length} days.');
    for (int i = 0; i < planState.dailyStops.length; i++) {
      final day = planState.dailyStops[i];
      debugPrint('   Day ${i + 1}: ${day.length} stops → '
          '${day.map((p) => p.placeName).join(' → ')}');
      if (day.isEmpty) {
        debugPrint('      ⚠️ Day ${i + 1} has no stops.');
      }
    }
  }

  // ─── 5. AI SCHEDULE ──────────────────────────────────────

  debugPrint('📌 STEP 5: AI SCHEDULE');

  if (planState.aiDaySchedules == null) {
    debugPrint('❌ aiDaySchedules is null.');
    ok = false;
  } else if (planState.aiDaySchedules!.isEmpty) {
    debugPrint('❌ aiDaySchedules is empty.');
    ok = false;
  } else {
    debugPrint('✅ aiDaySchedules has ${planState.aiDaySchedules!.length} days.');
    for (final day in planState.aiDaySchedules!) {
      debugPrint('   Day ${day.dayIndex} (${day.date}): ${day.schedule.length} stops');
      for (final stop in day.schedule) {
        final placeName = planState.findPlace(stop.placeId)?.placeName ?? '❓ Unknown';
        debugPrint('      - ${stop.startTime} → ${stop.endTime} : $placeName');
      }
    }
  }

  // ─── 6. USED PLACES VS CANDIDATES ───────────────────────

  debugPrint('📌 STEP 6: USED PLACES VALIDATION');

  final usedIds = planState.usedPlaceIds;
  final allIds = allCandidates.map((p) => p.placeId).toSet();

  if (usedIds.isEmpty) {
    debugPrint('❌ No places are marked as used.');
    ok = false;
  } else {
    debugPrint('✅ Used place IDs: ${usedIds.length}');
  }

  final orphaned = usedIds.difference(allIds);
  if (orphaned.isNotEmpty) {
    debugPrint('❌ Orphaned used places (not in candidates): ${orphaned.join(', ')}');
    ok = false;
  } else {
    debugPrint('✅ All used places are present in candidate pools.');
  }

  final unused = allIds.difference(usedIds);
  debugPrint('ℹ️ Unused candidates: ${unused.length}');

  // ─── 7. FINAL VERDICT ─────────────────────────────────────

  debugPrint('═══════════════════════════════════════════');
  if (ok) {
    debugPrint('✅✅✅ PLAN STATE IS COMPLETE AND VALID ✅✅✅');
  } else {
    debugPrint('❌❌❌ PLAN STATE HAS ISSUES – SEE ABOVE ❌❌❌');
  }
  debugPrint('═══════════════════════════════════════════');

  return ok;
}