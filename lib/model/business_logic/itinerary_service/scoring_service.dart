import 'package:flutter/foundation.dart';
import '../../../core/config/interest_mapping.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';

class ScoredAttraction {
  final Place place;
  final double score;
  final Map<String, double> breakdown;
  final bool isMustVisit;
  final String matchedInterest;
  final bool isEligible;
  final List<String> reasons;

  const ScoredAttraction({
    required this.place,
    required this.score,
    required this.breakdown,
    this.isMustVisit = false,
    this.matchedInterest = '',
    this.isEligible = true,
    this.reasons = const [],
  });
}

class ScoringService {
  // ============================================================
  // WEIGHTS
  // ============================================================
  static const double weightInterest     = 0.40; // raised — primary signal
  static const double weightMustVisit    = 0.20; // lowered — must-visit should not override interest
  static const double weightTravelerType = 0.15;
  static const double weightRating       = 0.15; // raised — quality matters
  static const double weightTravelPace   = 0.05; // lowered — secondary signal
  static const double weightGeography    = 0.05;

  // Penalty weights
  static const double nonInterestPenalty      = 0.30; // raised from 0.15
  static const double excludedCategoryPenalty = 0.50; // raised from 0.25
  static const double weightTransportation = 0.05;

  // ============================================================
  // HARD-BLOCKED TYPES
  // FIX PROBLEM 4: These place types are NEVER shown in a travel plan.
  // Transport, utility, and infrastructure places are rejected before
  // they even reach the scoring loop.
  // ============================================================
  static const Set<String> _hardBlockedTypes = {
    // Transport infrastructure
    'transit_station',
    'bus_station',
    'subway_station',
    'train_station',
    'light_rail_station',
    'airport',
    'ferry_terminal',
    'taxi_stand',
    // Vehicle services
    'gas_station',
    'parking',
    'car_wash',
    'car_repair',
    'car_dealer',
    'car_rental',
    // Utilities & services
    'post_office',
    'police',
    'fire_station',
    'courthouse',
    'embassy',
    'city_hall',
    'local_government_office',
    // Mundane retail
    'atm',
    'bank',
    'insurance_agency',
    'real_estate_agency',
    'laundry',
    'locksmith',
    'moving_company',
    'storage',
    // Medical
    'hospital',
    'dentist',
    'doctor',
    'pharmacy',
    'physiotherapist',
    'veterinary_care',
    // Industrial
    'cemetery',
  };

  // ============================================================
  // FOOD-ADJACENT TYPES
  // FIX PROBLEM 8: Expanded food detection includes bars and nightlife.
  // ============================================================
  static const Set<String> _foodTypes = {
    'restaurant',
    'cafe',
    'bakery',
    'meal_takeaway',
    'meal_delivery',
    'food',
    'bar',
    'night_club',
    'liquor_store',
    'brewery',
    'food_court',
  };

  // ============================================================
  // ATTRACTION TYPES
  // Only these types are considered "attractions" for pool balancing.
  // ============================================================
  static const Set<String> _attractionTypes = {
    'tourist_attraction',
    'point_of_interest',
    'museum',
    'art_gallery',
    'park',
    'amusement_park',
    'aquarium',
    'zoo',
    'stadium',
    'bowling_alley',
    'movie_theater',
    'shopping_mall',
    'spa',
    'gym',
    'library',
    'place_of_worship',
    'hindu_temple',
    'mosque',
    'church',
    'synagogue',
    'natural_feature',
    'campground',
    'rv_park',
  };

  // ============================================================
  // MAIN SCORING FUNCTION
  // ============================================================
  List<ScoredAttraction> scorePlaces({
    required List<Place> places,
    required List<String> selectedInterests,
    required List<String> mustVisitIds,
    required String explorationTime,
    Coordinates? tripLocation,
    String travelerType = 'Solo',
    String travelPace = 'Standard',
    List<String> accessibilityRequirements = const [],
    List<String> dietaryRestrictions = const [],
    List<String> categoryExclusions = const [],
    bool strictInterestFilter = true,
    int minPoolFloor = 3,
    bool enableDebugLogs = false,
  }) {
    final effectivePace = travelPace.isNotEmpty
        ? travelPace
        : _paceFromExplorationTime(explorationTime);

    final mustVisitIdsSet = mustVisitIds.toSet();
    final excludedSet     = categoryExclusions.map((c) => c.toLowerCase()).toSet();

    if (enableDebugLogs) {
      final total = places.length;
      debugPrint('[SCORING] ── INPUT ──────────────────────────────────');
      debugPrint('[SCORING] Total places     : $total');
      debugPrint('[SCORING] Interests        : $selectedInterests');
      debugPrint('[SCORING] Traveler type    : $travelerType');
      debugPrint('[SCORING] Travel pace      : $effectivePace');
      debugPrint('[SCORING] Exclusions       : $categoryExclusions');
      debugPrint('[SCORING] Strict filter    : $strictInterestFilter');
      debugPrint('[SCORING] Pool floor       : $minPoolFloor');
    }

    // ── STAGE 0: Hard-block transport / utility types ───────────────────────
    // FIX PROBLEM 4: Completely remove infrastructure places.
    // Must-visits are exempt from hard-blocking (user explicitly wants them).
    final afterTypeBlock = <Place>[];
    int blockedCount = 0;

    for (final place in places) {
      final isMustVisit = mustVisitIdsSet.contains(place.placeId);
      final placeTypesLower = place.types.map((t) => t.toLowerCase()).toSet();
      final isBlocked = placeTypesLower.any(_hardBlockedTypes.contains);

      if (isBlocked && !isMustVisit) {
        blockedCount++;
        if (enableDebugLogs) {
          debugPrint('[SCORING] BLOCKED (type) : ${place.name} '
              '| types=${place.types}');
        }
        continue;
      }
      afterTypeBlock.add(place);
    }

    if (enableDebugLogs) {
      debugPrint('[SCORING] After type block : '
          '${afterTypeBlock.length} (blocked $blockedCount)');
    }

    // ── STAGE 1: Eligibility + Scoring ──────────────────────────────────────
    final eligible = <ScoredAttraction>[];

    for (final place in afterTypeBlock) {
      // 1a. Accessibility / dietary eligibility
      final eligibility = _checkEligibility(
        place:                    place,
        accessibilityRequirements: accessibilityRequirements,
        dietaryRestrictions:       dietaryRestrictions,
      );
      if (!eligibility.isEligible) continue;

      final isMustVisit     = mustVisitIdsSet.contains(place.placeId);
      final placeTypesLower = place.types.map((t) => t.toLowerCase()).toSet();

      // ── Interest score ─────────────────────────────────────────────────
      // FIX PROBLEM 1: No hidden floor — 0.0 when no interests selected
      // and place has no types.
      final interestScore   = _calculateInterestScore(
        place.types,
        selectedInterests,
      );
      final matchedInterest = _findMatchedInterest(
        place.types,
        selectedInterests,
      );

      // ── Must-visit score ───────────────────────────────────────────────
      final mustVisitScore  = isMustVisit ? 1.0 : 0.0;

      // ── Traveler type score ────────────────────────────────────────────
      final travelerTypeScore = _calculateTravelerTypeScore(place, travelerType);

      // ── Rating score ───────────────────────────────────────────────────
      final ratingScore     = (place.rating / 5.0).clamp(0.0, 1.0);

      // ── Travel pace score ──────────────────────────────────────────────
      final travelPaceScore = _calculateTravelPaceScore(place, effectivePace);

      // ── Geography score ────────────────────────────────────────────────
      final geographyScore  = _calculateGeographyScore(
        place.coordinates,
        tripLocation,
      );

      // ── Penalties ──────────────────────────────────────────────────────
      // FIX PROBLEM 6 & 7: Stronger penalty, clearly documented.
      double penalty = 0.0;

      // Penalty: place matches none of the user's selected interests
      if (matchedInterest == 'Unknown' && selectedInterests.isNotEmpty) {
        penalty += nonInterestPenalty;
      }

      // Penalty: place contains an explicitly excluded category
      // FIX PROBLEM 7: Cap penalty at 1.0 so it cannot produce
      // artificially negative scores that confuse sorting.
      final excludedHits = placeTypesLower.intersection(excludedSet).length;
      if (excludedHits > 0) {
        penalty = (penalty + excludedCategoryPenalty * excludedHits).clamp(0.0, 1.0);
      }

      // ── Weighted total ─────────────────────────────────────────────────
      final rawScore =
          interestScore   * weightInterest     +
              mustVisitScore  * weightMustVisit     +
              travelerTypeScore * weightTravelerType +
              ratingScore     * weightRating        +
              travelPaceScore * weightTravelPace    +
              geographyScore  * weightGeography;

      // Clamp to [0, 1] so penalty cannot produce absurd negatives
      final totalScore = (rawScore - penalty).clamp(0.0, 1.0);

      // ── Reasons ────────────────────────────────────────────────────────
      final reasons = _buildReasons(
        matchedInterest:    matchedInterest,
        isMustVisit:        isMustVisit,
        travelerType:       travelerType,
        travelerTypeScore:  travelerTypeScore,
        effectivePace:      effectivePace,
        travelPaceScore:    travelPaceScore,
        ratingScore:        ratingScore,
        geographyScore:     geographyScore,
        selectedInterests:  selectedInterests,
        excludedHits:       excludedHits,
        categoryExclusions: categoryExclusions,
      );

      eligible.add(ScoredAttraction(
        place:           place,
        score:           (totalScore * 100).roundToDouble() / 100,
        breakdown: {
          'interest':     interestScore,
          'mustVisit':    mustVisitScore,
          'travelerType': travelerTypeScore,
          'rating':       ratingScore,
          'travelPace':   travelPaceScore,
          'geography':    geographyScore,
          'penalty':      penalty,
          'total':        totalScore,
        },
        isMustVisit:     isMustVisit,
        matchedInterest: matchedInterest,
        isEligible:      true,
        reasons:         reasons,
      ));
    }

    if (enableDebugLogs) {
      debugPrint('[SCORING] After scoring    : ${eligible.length} eligible');
    }

    // ── STAGE 2: Strict interest filter with pool floor ──────────────────────
    // FIX PROBLEM 5: Pool floor re-adds from eligible[] which is already
    // type-blocked, so no transport places sneak back in.
    var pool = eligible;

    if (strictInterestFilter && selectedInterests.isNotEmpty) {
      final matching = eligible
          .where((s) => s.isMustVisit || s.matchedInterest != 'Unknown')
          .toList();

      if (matching.isNotEmpty && matching.length >= minPoolFloor) {
        pool = matching;
        if (enableDebugLogs) {
          debugPrint('[SCORING] Strict filter    : kept ${pool.length} '
              '(interest-matched or must-visit)');
        }
      } else {
        if (enableDebugLogs) {
          debugPrint('[SCORING] Strict filter    : SKIPPED '
              '(only ${matching.length} matching < floor $minPoolFloor)');
        }
      }
    }

    // ── STAGE 3: Per-category retention floor ───────────────────────────────
    // FIX PROBLEM 5 & 8: Use _isAttractionPlace and _isFoodPlace which are
    // now both comprehensive. Only re-add from type-blocked-safe eligible[].
    final minPerCategory = minPoolFloor.clamp(1, 5);

    pool = _ensureCategoryFloor(
      pool:            pool,
      eligible:        eligible,
      minPerCategory:  minPerCategory,
      enableDebugLogs: enableDebugLogs,
    );

    // ── STAGE 4: Hard exclusion filter with floor ────────────────────────────
    if (excludedSet.isNotEmpty) {
      final withoutExcluded = pool.where((s) =>
      s.isMustVisit ||
          !s.place.types.map((t) => t.toLowerCase()).toSet()
              .any(excludedSet.contains),
      ).toList();

      if (withoutExcluded.isNotEmpty &&
          withoutExcluded.length >= minPoolFloor) {
        pool = withoutExcluded;
        if (enableDebugLogs) {
          debugPrint('[SCORING] Exclusion filter : kept ${pool.length}');
        }
      }
    }

    // ── STAGE 5: Sort + tie-break ────────────────────────────────────────────
    pool.sort((a, b) => b.score.compareTo(a.score));
    final result = _applyTieBreaker(pool);

    if (enableDebugLogs) {
      final resultAttrs = result.where((s) => _isAttractionPlace(s.place)).length;
      final resultFood  = result.where((s) => _isFoodPlace(s.place)).length;
      final resultOther = result.length - resultAttrs - resultFood;
      debugPrint('[SCORING] ── OUTPUT ─────────────────────────────────');
      debugPrint('[SCORING] Total survived   : ${result.length}');
      debugPrint('[SCORING] Attractions      : $resultAttrs');
      debugPrint('[SCORING] Food/Drink       : $resultFood');
      debugPrint('[SCORING] Other            : $resultOther');
      if (result.isEmpty) {
        debugPrint('[SCORING] ⚠️  EMPTY POOL — plan will fail');
      }
      debugPrint('[SCORING] Top 5 scores:');
      for (final s in result.take(5)) {
        debugPrint('[SCORING]   ${s.score.toStringAsFixed(2)} | '
            '${s.place.name} | interest=${s.matchedInterest} | '
            'types=${s.place.types.take(3).join(",")}');
      }
    }

    return result;
  }

  // ============================================================
  // STAGE 3 HELPER: Category floor enforcement
  // ============================================================
  List<ScoredAttraction> _ensureCategoryFloor({
    required List<ScoredAttraction> pool,
    required List<ScoredAttraction> eligible,
    required int minPerCategory,
    required bool enableDebugLogs,
  }) {
    final result = List<ScoredAttraction>.from(pool);

    // Check attractions
    final attrsInPool = result.where((s) => _isAttractionPlace(s.place)).length;
    if (attrsInPool < minPerCategory) {
      final moreAttrs = eligible
          .where((s) =>
      _isAttractionPlace(s.place) &&
          !result.any((r) => r.place.placeId == s.place.placeId))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      final toAdd = moreAttrs.take(minPerCategory - attrsInPool).toList();
      result.addAll(toAdd);

      if (enableDebugLogs && toAdd.isNotEmpty) {
        debugPrint('[SCORING] Floor: added ${toAdd.length} attraction(s) '
            '→ ${toAdd.map((s) => s.place.name).join(", ")}');
      }
    }

    // Check food
    final foodInPool = result.where((s) => _isFoodPlace(s.place)).length;
    if (foodInPool < minPerCategory) {
      final moreFood = eligible
          .where((s) =>
      _isFoodPlace(s.place) &&
          !result.any((r) => r.place.placeId == s.place.placeId))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      final toAdd = moreFood.take(minPerCategory - foodInPool).toList();
      result.addAll(toAdd);

      if (enableDebugLogs && toAdd.isNotEmpty) {
        debugPrint('[SCORING] Floor: added ${toAdd.length} food place(s) '
            '→ ${toAdd.map((s) => s.place.name).join(", ")}');
      }
    }

    return result;
  }

  double _calculateTransportationScore(Place place, List<String> transportationPreferences) {
    if (transportationPreferences.isEmpty) return 0.0;
    final types = place.types.map((t) => t.toLowerCase()).toList();

    // Check if the place matches requested transport modes/types (e.g., train, bus, rental)
    for (final pref in transportationPreferences) {
      final normalized = pref.toLowerCase();
      if (types.contains(normalized) || types.any((t) => t.contains(normalized))) {
        return 1.0;
      }
    }
    return 0.2; // Baseline score if transport preferences are provided but no direct match
  }
  // ============================================================
  // ELIGIBILITY
  // ============================================================
  _EligibilityResult _checkEligibility({
    required Place place,
    required List<String> accessibilityRequirements,
    required List<String> dietaryRestrictions,
  }) {
    for (final requirement in accessibilityRequirements) {
      final normalized = requirement.toLowerCase();
      bool? result;
      if (normalized.contains('wheelchair'))   result = _isWheelchairAccessible(place);
      if (normalized.contains('step-free'))    result = _hasStepFreeAccess(place);
      if (normalized.contains('low physical')) result = _isLowPhysicalExertion(place);
      if (result == false) return const _EligibilityResult(isEligible: false);
    }

    if (_isFoodPlace(place) && dietaryRestrictions.isNotEmpty) {
      for (final restriction in dietaryRestrictions) {
        final supported = _supportsDietaryRequirement(place, restriction);
        if (supported == false) return const _EligibilityResult(isEligible: false);
      }
    }

    return const _EligibilityResult(isEligible: true);
  }

  // ============================================================
  // INTEREST SCORE
  // FIX PROBLEM 1: When selectedInterests is empty, return 0.0
  // not 0.5 — no free score for unknown intent.
  // ============================================================
  double _calculateInterestScore(
      List<String> placeTypes,
      List<String> selectedInterests,
      ) {
    // No interests selected → neutral 0.0 (does not inflate or deflate)
    if (selectedInterests.isEmpty) return 0.0;
    if (placeTypes.isEmpty) return 0.0;

    final matchingTypes = <String>{};
    for (final interest in selectedInterests) {
      matchingTypes.addAll(
        InterestMapping.getGoogleTypesForInterest(interest),
      );
    }

    int matchCount = 0;
    for (final type in placeTypes) {
      if (matchingTypes.contains(type)) matchCount++;
    }

    if (matchCount == 0) return 0.0; // no hidden floor

    // FIX PROBLEM 6: Score against matched types relative to interest pool
    // not place type count — prevents dilution by unrelated tags.
    return (matchCount / matchingTypes.length).clamp(0.0, 1.0);
  }

  // ============================================================
  // MATCHED INTEREST
  // ============================================================
  String _findMatchedInterest(
      List<String> placeTypes,
      List<String> selectedInterests,
      ) {
    for (final interest in selectedInterests) {
      final types = InterestMapping.getGoogleTypesForInterest(interest);
      if (placeTypes.any(types.contains)) return interest;
    }
    return 'Unknown';
  }

  // ============================================================
  // TRAVELER TYPE SCORE
  // ============================================================
  double _calculateTravelerTypeScore(Place place, String travelerType) {
    final types    = place.types.map((t) => t.toLowerCase()).toList();
    final category = (place.category ?? '').toLowerCase();
    final type     = travelerType.toLowerCase();

    if (type.contains('family')) {
      if (_containsAny(types, ['amusement_park', 'aquarium', 'zoo', 'park', 'museum'])) return 1.0;
      if (_containsAny(types, ['tourist_attraction', 'point_of_interest']))             return 0.8;
      if (category.contains('nightlife'))                                                return 0.1;
      return 0.0;
    }
    if (type.contains('couple')) {
      if (_containsAny(types, ['park', 'tourist_attraction', 'museum',
        'art_gallery', 'restaurant', 'cafe']))                                         return 0.9;
      return 0.0;
    }
    if (type.contains('group')) {
      if (_containsAny(types, ['amusement_park', 'tourist_attraction',
        'shopping_mall', 'restaurant', 'bowling_alley']))                              return 0.9;
      return 0.0;
    }
    if (type.contains('business')) {
      if (_containsAny(types, ['restaurant', 'cafe', 'shopping_mall',
        'museum', 'hotel']))                                                           return 0.9;
      return 0.0;
    }
    if (type.contains('solo')) {
      if (_containsAny(types, ['museum', 'art_gallery', 'park',
        'tourist_attraction', 'cafe', 'library']))                                    return 0.9;
      return 0.0;
    }
    return 0.0;
  }

  // ============================================================
  // TRAVEL PACE SCORE
  // ============================================================
  double _calculateTravelPaceScore(Place place, String travelPace) {
    final duration = place.visitDurationMinutes;
    if (duration == null || duration <= 0) return 0.0;

    final pace = travelPace.toLowerCase();

    if (pace.contains('fast')) {
      if (duration <= 60)  return 1.0;
      if (duration <= 120) return 0.8;
      if (duration <= 180) return 0.6;
      return 0.4;
    }
    if (pace.contains('balanced') || pace.contains('standard')) {
      if (duration >= 45 && duration <= 120) return 1.0;
      if (duration <= 180)                   return 0.8;
      return 0.5;
    }
    if (pace.contains('slow') || pace.contains('relaxed')) {
      if (duration >= 60 && duration <= 180) return 1.0;
      if (duration >= 45)                    return 0.8;
      return 0.6;
    }
    return 0.0;
  }

  // ============================================================
  // GEOGRAPHY SCORE
  // ============================================================
  double _calculateGeographyScore(
      Coordinates placeCoordinates,
      Coordinates? tripLocation,
      ) {
    if (tripLocation == null) return 0.0;
    final distance = placeCoordinates.distanceTo(tripLocation);
    if (distance < 2.0)  return 1.0;
    if (distance < 5.0)  return 0.8;
    if (distance < 10.0) return 0.5;
    if (distance < 20.0) return 0.2;
    return 0.0;
  }

  // ============================================================
  // PLACE CATEGORY HELPERS
  // ============================================================

  /// Returns true when a place is a food/drink/dining venue.
  bool _isFoodPlace(Place place) {
    final types    = place.types.map((t) => t.toLowerCase()).toSet();
    final category = (place.category ?? '').toLowerCase();
    return types.any(_foodTypes.contains) ||
        category.contains('restaurant') ||
        category.contains('food')       ||
        category.contains('cafe')       ||
        category.contains('bar');
  }

  /// Returns true when a place is a tourist attraction/activity.
  bool _isAttractionPlace(Place place) {
    final types    = place.types.map((t) => t.toLowerCase()).toSet();
    final category = (place.category ?? '').toLowerCase();
    return types.any(_attractionTypes.contains) ||
        category.contains('attraction') ||
        category.contains('landmark')   ||
        category.contains('museum')     ||
        category.contains('park');
  }

  bool _containsAny(List<String> source, List<String> values) =>
      values.any(source.contains);

  // ============================================================
  // REASONS BUILDER
  // ============================================================
  List<String> _buildReasons({
    required String matchedInterest,
    required bool isMustVisit,
    required String travelerType,
    required double travelerTypeScore,
    required String effectivePace,
    required double travelPaceScore,
    required double ratingScore,
    required double geographyScore,
    required List<String> selectedInterests,
    required int excludedHits,
    required List<String> categoryExclusions,
  }) {
    final reasons = <String>[];

    if (matchedInterest.isNotEmpty && matchedInterest != 'Unknown') {
      reasons.add('Matches traveler interest: $matchedInterest');
    }
    if (isMustVisit) {
      reasons.add('Selected as a must-visit place');
    }
    if (travelerTypeScore >= 0.8) {
      reasons.add('Suitable for traveler type: $travelerType');
    }
    if (travelPaceScore >= 0.8) {
      reasons.add('Suitable for $effectivePace travel pace');
    }
    if (ratingScore >= 0.8) {
      reasons.add('Highly rated by Google Places');
    }
    if (geographyScore >= 0.8) {
      reasons.add('Located near the selected destination area');
    }
    if (matchedInterest == 'Unknown' && selectedInterests.isNotEmpty) {
      reasons.add('⚠️ Does not match any selected interest');
    }
    if (excludedHits > 0) {
      reasons.add('⚠️ Contains excluded category: '
          '${categoryExclusions.join(", ")}');
    }

    return reasons;
  }

  // ============================================================
  // ACCESSIBILITY (pass-through — unknown = eligible)
  // ============================================================
  bool? _isWheelchairAccessible(Place place) => null;
  bool? _hasStepFreeAccess(Place place)       => null;
  bool? _isLowPhysicalExertion(Place place)   => null;

  // ============================================================
  // DIETARY (pass-through — unknown = eligible)
  // ============================================================
  bool? _supportsDietaryRequirement(Place place, String requirement) => null;

  // ============================================================
  // TIE BREAKER
  // ============================================================
  List<ScoredAttraction> _applyTieBreaker(List<ScoredAttraction> scored) {
    final scoreGroups = <double, List<ScoredAttraction>>{};
    for (final item in scored) {
      scoreGroups.putIfAbsent(item.score, () => []).add(item);
    }

    final result = <ScoredAttraction>[];
    for (final group in scoreGroups.values) {
      group.sort((a, b) {
        final r = b.place.rating.compareTo(a.place.rating);
        return r != 0 ? r : a.place.name.compareTo(b.place.name);
      });
      result.addAll(group);
    }
    return result;
  }

  // ============================================================
  // PACE FROM EXPLORATION TIME
  // ============================================================
  String _paceFromExplorationTime(String explorationTime) {
    final et = explorationTime.toLowerCase();
    if (et.contains('relaxed')) return 'Slow';
    if (et.contains('intense')) return 'Fast';
    return 'Standard';
  }
}

// ============================================================
// INTERNAL ELIGIBILITY RESULT
// ============================================================
class _EligibilityResult {
  final bool isEligible;
  const _EligibilityResult({required this.isEligible});
}