import 'package:flutter/foundation.dart';
import '../../entities/place.dart';
import 'candidate_retrieval_service.dart';
import 'clustering_service.dart'; // <-- IMPORT CLUSTERING
import '../../../core/services/ai_service.dart'; // <-- IMPORT AI SERVICE (for AIDaySchedule)

/// Runtime state retained after itinerary generation.
class ItineraryPlanState {
  // ==========================================================
  // TRIP INFORMATION
  // ==========================================================
  final String itineraryId;
  final List<QueryDestination> destinations;
  final int totalDays;
  final String pace;
  final String intensity;
  final List<String> selectedInterests;
  final List<String> mustVisitPlaceIds;

  // ==========================================================
  // ORIGINAL CANDIDATE POOLS (MULTI-DESTINATION)
  // ==========================================================
  final Map<String, CandidatePool> destinationPools;

  // ==========================================================
  // DAY-BY-DAY HOTSPOT GROUPS (NEW ARCHITECTURE)
  // ==========================================================
  /// Pre-grouped, day-by-day hotspot candidates produced by
  /// CandidateRetrievalService (one hotspot = one day).  Kept alongside the
  /// flattened [destinationPools] for backward compatibility.
  final List<DailyCandidateGroup>? dailyCandidateGroups;

  // ==========================================================
  // GENERATED PLAN & RICH DATA
  // ==========================================================
  List<List<Place>> dailyStops;

  // NEW: Store the raw clusters and the rich AI schedule
  final List<Cluster>? dailyClusters;
  final List<AIDaySchedule>? aiDaySchedules;

  // ==========================================================
  // VERSION & VALIDATION & AI
  // ==========================================================
  int version;
  bool isValid;
  List<String> validationIssues;

  ItineraryPlanState({
    required this.itineraryId,
    required this.destinations,
    required this.totalDays,
    required this.pace,
    required this.intensity,
    required this.selectedInterests,
    required this.mustVisitPlaceIds,
    required this.destinationPools,
    required this.dailyStops,
    this.dailyCandidateGroups,
    this.dailyClusters, // <-- NEW
    this.aiDaySchedules, // <-- NEW
    this.version = 1,
    this.isValid = false,
    this.validationIssues = const [],
  });

  // ==========================================================
  // AGGREGATED CANDIDATE GETTERS
  // ==========================================================

  /// Flattens all destination pools into a single list of all candidates.
  List<Place> get allCandidates =>
      destinationPools.values.expand((pool) => pool.all).toList();

  /// Flattens all destination pools into a single list of attractions.
  List<Place> get attractionCandidates =>
      destinationPools.values.expand((pool) => pool.attractions).toList();

  /// Flattens all destination pools into a single list of food candidates.
  List<Place> get foodCandidates =>
      destinationPools.values.expand((pool) => pool.food).toList();

  /// Per-day candidate totals derived from the day-by-day hotspot groups.
  ///
  /// Returns a map of 1-based day index → (attractions, food) counts.  When
  /// no day groups exist (legacy flat pool) an empty map is returned.
  Map<int, (int, int)> get dayCandidateTotals {
    final groups = dailyCandidateGroups;
    if (groups == null) return const {};

    final result = <int, (int, int)>{};
    for (final group in groups) {
      result[group.dayIndex] = (group.attractionCount, group.foodCount);
    }
    return result;
  }

  // ==========================================================
  // CURRENTLY USED PLACES
  // ==========================================================
  List<Place> get usedPlaces {
    final result = <Place>[];
    for (final day in dailyStops) {
      result.addAll(day);
    }
    return result;
  }

  Set<String> get usedPlaceIds =>
      usedPlaces.map((p) => p.placeId).toSet();

  // ==========================================================
  // UNUSED CANDIDATES
  // ==========================================================
  List<Place> get unusedCandidates {
    return allCandidates
        .where((place) => !usedPlaceIds.contains(place.placeId))
        .toList();
  }

  List<Place> get unusedAttractions {
    return attractionCandidates
        .where((place) => !usedPlaceIds.contains(place.placeId))
        .toList();
  }

  List<Place> get unusedFood {
    return foodCandidates
        .where((place) => !usedPlaceIds.contains(place.placeId))
        .toList();
  }

  // ==========================================================
  // FIND PLACE
  // ==========================================================
  Place? findPlace(String placeId) {
    for (final place in allCandidates) {
      if (place.placeId == placeId) {
        return place;
      }
    }
    return null;
  }

  // ==========================================================
  // DAY OPERATIONS (Unchanged)
  // ==========================================================

  List<Place> getDay(int dayIndex) {
    if (dayIndex < 0 || dayIndex >= dailyStops.length) return [];
    return List.unmodifiable(dailyStops[dayIndex]);
  }

  bool addPlaceToDay({required int dayIndex, required String placeId, int? insertIndex}) {
    final place = findPlace(placeId);
    if (place == null || dayIndex < 0 || dayIndex >= dailyStops.length) return false;
    if (usedPlaceIds.contains(placeId)) return false;

    final day = dailyStops[dayIndex];
    if (day.length >= 8) return false;

    if (insertIndex == null || insertIndex < 0 || insertIndex > day.length) {
      day.add(place);
    } else {
      day.insert(insertIndex, place);
    }
    version++;
    return true;
  }

  bool removePlaceFromDay({required int dayIndex, required String placeId}) {
    if (dayIndex < 0 || dayIndex >= dailyStops.length) return false;
    final day = dailyStops[dayIndex];
    final index = day.indexWhere((p) => p.placeId == placeId);
    if (index == -1) return false;

    day.removeAt(index);
    version++;
    return true;
  }

  bool reorderPlace({required int dayIndex, required int oldIndex, required int newIndex}) {
    if (dayIndex < 0 || dayIndex >= dailyStops.length) return false;
    final day = dailyStops[dayIndex];
    if (oldIndex < 0 || oldIndex >= day.length || newIndex < 0 || newIndex >= day.length) return false;

    final place = day.removeAt(oldIndex);
    day.insert(newIndex, place);
    version++;
    return true;
  }

  void replaceDay(int dayIndex, List<Place> newStops) {
    if (dayIndex < 0 || dayIndex >= dailyStops.length) return;
    dailyStops[dayIndex] = List<Place>.from(newStops);
    version++;
  }

  void setValidationResult({required bool valid, required List<String> issues}) {
    isValid = valid;
    validationIssues = List<String>.from(issues);
  }

  // ==========================================================
  // DEBUG
  // ==========================================================
  void debugPrintState() {
    debugPrint('════════════════════════════════════');
    debugPrint('📦 ITINERARY PLAN STATE');
    debugPrint('Itinerary ID: $itineraryId');

    destinationPools.forEach((destName, pool) {
      debugPrint('--- Candidates for $destName ---');
      debugPrint('  Attractions: ${pool.attractionCount}');
      debugPrint('  Food: ${pool.foodCount}');
    });

    // Report per-day hotspot candidates when the day-by-day groups exist.
    final dayTotals = dayCandidateTotals;
    if (dayTotals.isNotEmpty) {
      debugPrint('--- Day-by-Day Hotspot Candidates ---');
      for (final entry in dayTotals.entries) {
        debugPrint(
          '  Day ${entry.key}: ${entry.value.$1} attr, '
          '${entry.value.$2} food',
        );
      }
    }

    // FIXED: Removed the () from unusedCandidates
    debugPrint('Total unused candidates: ${unusedCandidates.length}');
    debugPrint('Validation: ${isValid ? "VALID" : "INVALID"}');

    debugPrint('--- FINAL GENERATED SCHEDULE ---');
    if (aiDaySchedules != null && aiDaySchedules!.isNotEmpty) {
      for (final day in aiDaySchedules!) {
        // dayIndex is 0-based internally; display as Day 1/2/3.
        debugPrint('DAY ${day.dayIndex + 1} (${day.date}):');
        for (final stop in day.schedule) {
          final placeName = findPlace(stop.placeId)?.placeName ?? 'Unknown Place';
          debugPrint('  [${stop.startTime} - ${stop.endTime}] $placeName');
          debugPrint('    ↳ Duration: ${stop.visitDurationMinutes}m | Travel from prev: ${stop.travelFromPreviousMinutes}m');
          debugPrint('    ↳ Weather Note: ${stop.weatherNote}');
        }
      }
    } else {
      // Fallback if AI schedule is missing
      for (int i = 0; i < dailyStops.length; i++) {
        debugPrint('Day ${i + 1}: ${dailyStops[i].map((p) => p.placeName).join(" → ")}');
      }
    }
    debugPrint('════════════════════════════════════');
  }
}