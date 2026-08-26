import 'package:flutter/foundation.dart';
import '../../entities/trip_request.dart';
import 'candidate_retrieval_service.dart';
import 'clustering_service.dart';
import 'scoring_service.dart';

class ItineraryRepairService {
  final CandidateRetrievalService _retrievalService;
  final ScoringService _scoringService;

  ItineraryRepairService({
    required CandidateRetrievalService retrievalService,
    required ScoringService scoringService,
  })  : _retrievalService = retrievalService,
        _scoringService = scoringService;

  /// Repairs a cluster that has fallen below the minimum required attractions.
  ///
  /// Tier 1: Attempts to borrow unused places from the Global Pool (Fast).
  /// Tier 2: Triggers On-Demand Micro-Discovery via API (Safe).
  Future<Cluster> repairDeficientDay({
    required TripRequest request,
    required Cluster deficientCluster,
    required List<ScoredAttraction> globalPool,
    required List<ScoredAttraction> alreadyUsedPlaces,
    required int minRequired,
  }) async {
    List<ScoredAttraction> currentAttractions =
    List.from(deficientCluster.attractions);

    debugPrint(
      '⚠️ [REPAIR SERVICE] '
          'Day ${deficientCluster.dayIndex} is deficient '
          '(${currentAttractions.length}/$minRequired). '
          'Initiating repair protocol.',
    );

    // ============================================================
    // TIER 1: GLOBAL POOL BORROWING
    // ============================================================

    if (currentAttractions.length < minRequired) {
      debugPrint('  ▶ Tier 1: Searching Global Pool...');

      final availablePool = globalPool.where((place) {
        final bool isUsed = alreadyUsedPlaces.any(
              (used) => used.place.placeId == place.place.placeId,
        );

        final bool isFood = place.place.types.any(
              (type) =>
              CandidateRetrievalService.foodTypes.contains(type),
        );

        return !isUsed && !isFood;
      }).toList();

      // Sort by distance from deficient day's cluster center.
      availablePool.sort((a, b) {
        final distA =
        a.place.coordinates.distanceTo(deficientCluster.center);

        final distB =
        b.place.coordinates.distanceTo(deficientCluster.center);

        return distA.compareTo(distB);
      });

      int borrowedCount = 0;

      for (final backupPlace in availablePool) {
        if (currentAttractions.length >= minRequired) {
          break;
        }

        final distance = backupPlace.place.coordinates
            .distanceTo(deficientCluster.center);

        // Prevent borrowing places that are too far away.
        if (distance <= 15.0) {
          currentAttractions.add(backupPlace);
          alreadyUsedPlaces.add(backupPlace);
          borrowedCount++;
        }
      }

      debugPrint(
        '  ▶ Tier 1 Result: '
            'Borrowed $borrowedCount places from Global Pool.',
      );
    }

    // ============================================================
    // TIER 2: ON-DEMAND MICRO-DISCOVERY
    // ============================================================

    if (currentAttractions.length < minRequired) {
      final int shortfall =
          minRequired - currentAttractions.length;

      debugPrint(
        '  ▶ Tier 2: Still deficient by $shortfall. '
            'Triggering Micro-Discovery API...',
      );

      // ----------------------------------------------------------
      // Determine emergency search anchor
      // ----------------------------------------------------------

      final searchAnchor = currentAttractions.isNotEmpty
          ? currentAttractions.first.place.coordinates
          : deficientCluster.center;

      debugPrint(
        '  ▶ Emergency Search Anchor: '
            '${searchAnchor.latitude}, '
            '${searchAnchor.longitude}',
      );

      // ----------------------------------------------------------
      // Create a repair-specific TripRequest.
      //
      // IMPORTANT:
      // We preserve the original request's:
      // - interests
      // - dates
      // - travel pace
      // - transport mode
      // - title
      // - notes
      // - must-visit IDs
      //
      // Only the destination/search coordinate is changed.
      // ----------------------------------------------------------

      final TripRequest repairRequest = request.copyWith(
        destinations: [
          'Emergency Anchor Day ${deficientCluster.dayIndex}',
        ],
        destinationCoordinates: {
          'Emergency Anchor Day ${deficientCluster.dayIndex}':
          searchAnchor,
        },
        tripLocation: searchAnchor,

        // Repair is only discovering candidates for ONE day.
        startDate: request.startDate,
        endDate: request.startDate,
      );

      // ----------------------------------------------------------
      // Retrieve candidates using the NEW TripRequest API
      // ----------------------------------------------------------

      final emergencyPlaces =
      await _retrievalService.retrieveCandidates(
        request: repairRequest,
      );

      debugPrint(
        '  ▶ Tier 2 Retrieval Result: '
            '${emergencyPlaces.attractions.length} attractions, '
            '${emergencyPlaces.food.length} food.',
      );

      // ----------------------------------------------------------
      // Score newly discovered attractions
      // ----------------------------------------------------------

      final emergencyScored =
      _scoringService.scorePlaces(
        places: emergencyPlaces.attractions,
        selectedInterests: request.interests,
        mustVisitIds: [],
        explorationTime: request.explorationTime,
      );

      // ----------------------------------------------------------
      // Add best emergency places
      // ----------------------------------------------------------

      int apiCount = 0;

      for (final newPlace in emergencyScored) {
        if (currentAttractions.length >= minRequired) {
          break;
        }

        final bool alreadyExists =
        alreadyUsedPlaces.any(
              (used) =>
          used.place.placeId ==
              newPlace.place.placeId,
        );

        if (!alreadyExists) {
          currentAttractions.add(newPlace);
          alreadyUsedPlaces.add(newPlace);
          apiCount++;
        }
      }

      debugPrint(
        '  ▶ Tier 2 Result: '
            'Discovered and added $apiCount new places via API.',
      );
    }

    // ============================================================
    // FINALIZE REPAIR
    // ============================================================

    debugPrint(
      '✅ [REPAIR SERVICE] '
          'Day ${deficientCluster.dayIndex} repair complete. '
          'Final count: ${currentAttractions.length}/$minRequired.',
    );

    return Cluster(
      dayIndex: deficientCluster.dayIndex,
      center: deficientCluster.center,
      attractions: currentAttractions,
    );
  }
}