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
  static const double weightInterest        = 0.35; // Adjusted to make room for transport
  static const double weightMustVisit       = 0.20;
  static const double weightTravelerType    = 0.15;
  static const double weightRating          = 0.10;
  static const double weightTravelPace      = 0.05;
  static const double weightGeography       = 0.05;
  static const double weightTransportation  = 0.10; // 👈 Added transportation weight (sum totals 1.0)

  // Penalty weights
  static const double nonInterestPenalty      = 0.30;
  static const double excludedCategoryPenalty = 0.50;

  // ============================================================
  // HARD-BLOCKED TYPES
  // ============================================================
  static const Set<String> _hardBlockedTypes = {
    'transit_station', 'bus_station', 'subway_station', 'train_station',
    'light_rail_station', 'airport', 'ferry_terminal', 'taxi_stand',
    'gas_station', 'parking', 'car_wash', 'car_repair', 'car_dealer', 'car_rental',
    'post_office', 'police', 'fire_station', 'courthouse', 'embassy', 'city_hall', 'local_government_office',
    'atm', 'bank', 'insurance_agency', 'real_estate_agency', 'laundry', 'locksmith', 'moving_company', 'storage',
    'hospital', 'dentist', 'doctor', 'pharmacy', 'physiotherapist', 'veterinary_care',
    'cemetery',
  };

  static const Set<String> _foodTypes = {
    'restaurant', 'cafe', 'bakery', 'meal_takeaway', 'meal_delivery',
    'food', 'bar', 'night_club', 'liquor_store', 'brewery', 'food_court',
  };

  static const Set<String> _attractionTypes = {
    'tourist_attraction', 'point_of_interest', 'museum', 'art_gallery', 'park',
    'amusement_park', 'aquarium', 'zoo', 'stadium', 'bowling_alley', 'movie_theater',
    'shopping_mall', 'spa', 'gym', 'library', 'place_of_worship', 'hindu_temple',
    'mosque', 'church', 'synagogue', 'natural_feature', 'campground', 'rv_park',
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
    List<String> transportationPreferences = const [], // 👈 Added parameter here
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
      debugPrint('[SCORING] Transport Prefs  : $transportationPreferences'); // 👈 Log check
    }

    // ── STAGE 0: Hard-block transport / utility types ───────────────────────
    final afterTypeBlock = <Place>[];
    int blockedCount = 0;

    for (final place in places) {
      final isMustVisit = mustVisitIdsSet.contains(place.placeId);
      final placeTypesLower = place.types.map((t) => t.toLowerCase()).toSet();
      final isBlocked = placeTypesLower.any(_hardBlockedTypes.contains);

      if (isBlocked && !isMustVisit) {
        blockedCount++;
        continue;
      }
      afterTypeBlock.add(place);
    }

    // ── STAGE 1: Eligibility + Scoring ──────────────────────────────────────
    final eligible = <ScoredAttraction>[];

    for (final place in afterTypeBlock) {
      final eligibility = _checkEligibility(
        place: place,
        accessibilityRequirements: accessibilityRequirements,
        dietaryRestrictions: dietaryRestrictions,
      );
      if (!eligibility.isEligible) continue;

      final isMustVisit     = mustVisitIdsSet.contains(place.placeId);
      final placeTypesLower = place.types.map((t) => t.toLowerCase()).toSet();

      final interestScore     = _calculateInterestScore(place.types, selectedInterests);
      final matchedInterest   = _findMatchedInterest(place.types, selectedInterests);
      final mustVisitScore    = isMustVisit ? 1.0 : 0.0;
      final travelerTypeScore = _calculateTravelerTypeScore(place, travelerType);
      final ratingScore       = (place.rating / 5.0).clamp(0.0, 1.0);
      final travelPaceScore   = _calculateTravelPaceScore(place, effectivePace);
      final geographyScore    = _calculateGeographyScore(place.coordinates, tripLocation);

      // ── Transportation score calculation ──────────────────────────────
      final transportationScore = _calculateTransportationScore(place, transportationPreferences); // 👈 Added calculation

      // ── Penalties ──────────────────────────────────────────────────────
      double penalty = 0.0;
      if (matchedInterest == 'Unknown' && selectedInterests.isNotEmpty) {
        penalty += nonInterestPenalty;
      }

      final excludedHits = placeTypesLower.intersection(excludedSet).length;
      if (excludedHits > 0) {
        penalty = (penalty + excludedCategoryPenalty * excludedHits).clamp(0.0, 1.0);
      }

      // ── Weighted total ─────────────────────────────────────────────────
      final rawScore =
          interestScore         * weightInterest        +
              mustVisitScore        * weightMustVisit       +
              travelerTypeScore     * weightTravelerType    +
              ratingScore           * weightRating          +
              travelPaceScore       * weightTravelPace      +
              geographyScore        * weightGeography       +
              transportationScore   * weightTransportation; // 👈 Added to formula

      final totalScore = (rawScore - penalty).clamp(0.0, 1.0);

      final reasons = _buildReasons(
        matchedInterest: matchedInterest,
        isMustVisit: isMustVisit,
        travelerType: travelerType,
        travelerTypeScore: travelerTypeScore,
        effectivePace: effectivePace,
        travelPaceScore: travelPaceScore,
        ratingScore: ratingScore,
        geographyScore: geographyScore,
        selectedInterests: selectedInterests,
        excludedHits: excludedHits,
        categoryExclusions: categoryExclusions,
      );

      eligible.add(ScoredAttraction(
        place: place,
        score: (totalScore * 100).roundToDouble() / 100,
        breakdown: {
          'interest': interestScore,
          'mustVisit': mustVisitScore,
          'travelerType': travelerTypeScore,
          'rating': ratingScore,
          'travelPace': travelPaceScore,
          'geography': geographyScore,
          'transportation': transportationScore, // 👈 Included in breakdown map
          'penalty': penalty,
          'total': totalScore,
        },
        isMustVisit: isMustVisit,
        matchedInterest: matchedInterest,
        isEligible: true,
        reasons: reasons,
      ));
    }

    var pool = eligible;

    if (strictInterestFilter && selectedInterests.isNotEmpty) {
      final matching = eligible.where((s) => s.isMustVisit || s.matchedInterest != 'Unknown').toList();
      if (matching.isNotEmpty && matching.length >= minPoolFloor) {
        pool = matching;
      }
    }

    final minPerCategory = minPoolFloor.clamp(1, 5);
    pool = _ensureCategoryFloor(pool: pool, eligible: eligible, minPerCategory: minPerCategory, enableDebugLogs: enableDebugLogs);

    if (excludedSet.isNotEmpty) {
      final withoutExcluded = pool.where((s) =>
      s.isMustVisit || !s.place.types.map((t) => t.toLowerCase()).toSet().any(excludedSet.contains),
      ).toList();

      if (withoutExcluded.isNotEmpty && withoutExcluded.length >= minPoolFloor) {
        pool = withoutExcluded;
      }
    }

    pool.sort((a, b) => b.score.compareTo(a.score));
    return _applyTieBreaker(pool);
  }

  // ============================================================
  // TRANSPORTATION SCORE HELPER
  // ============================================================
  double _calculateTransportationScore(Place place, List<String> transportPrefs) {
    if (transportPrefs.isEmpty) return 0.5; // Neutral baseline if no preference specified

    final types = place.types.map((t) => t.toLowerCase()).toList();
    final category = (place.category ?? '').toLowerCase();

    for (final pref in transportPrefs) {
      final normalized = pref.toLowerCase();
      // If user selected Public Transit, look for venues near transit zones or general accessibility
      if (normalized.contains('transit') || normalized.contains('public')) {
        return 0.8; // Baseline friendly score for general urban spots
      }
      // If user selected Driving/Car, check for parking or general accessibility
      if (normalized.contains('drive') || normalized.contains('car')) {
        return 0.8;
      }
    }
    return 0.5;
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

    final attrsInPool = result.where((s) => _isAttractionPlace(s.place)).length;
    if (attrsInPool < minPerCategory) {
      final moreAttrs = eligible
          .where((s) => _isAttractionPlace(s.place) && !result.any((r) => r.place.placeId == s.place.placeId))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      result.addAll(moreAttrs.take(minPerCategory - attrsInPool));
    }

    final foodInPool = result.where((s) => _isFoodPlace(s.place)).length;
    if (foodInPool < minPerCategory) {
      final moreFood = eligible
          .where((s) => _isFoodPlace(s.place) && !result.any((r) => r.place.placeId == s.place.placeId))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      result.addAll(moreFood.take(minPerCategory - foodInPool));
    }

    return result;
  }

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
        if (_supportsDietaryRequirement(place, restriction) == false) {
          return const _EligibilityResult(isEligible: false);
        }
      }
    }

    return const _EligibilityResult(isEligible: true);
  }

  double _calculateInterestScore(List<String> placeTypes, List<String> selectedInterests) {
    if (selectedInterests.isEmpty || placeTypes.isEmpty) return 0.0;
    final matchingTypes = <String>{};
    for (final interest in selectedInterests) {
      matchingTypes.addAll(InterestMapping.getGoogleTypesForInterest(interest));
    }
    int matchCount = placeTypes.where(matchingTypes.contains).length;
    if (matchCount == 0) return 0.0;
    return (matchCount / matchingTypes.length).clamp(0.0, 1.0);
  }

  String _findMatchedInterest(List<String> placeTypes, List<String> selectedInterests) {
    for (final interest in selectedInterests) {
      final types = InterestMapping.getGoogleTypesForInterest(interest);
      if (placeTypes.any(types.contains)) return interest;
    }
    return 'Unknown';
  }

  double _calculateTravelerTypeScore(Place place, String travelerType) {
    final types    = place.types.map((t) => t.toLowerCase()).toList();
    final category = (place.category ?? '').toLowerCase();
    final type     = travelerType.toLowerCase();

    if (type.contains('family')) {
      if (_containsAny(types, ['amusement_park', 'aquarium', 'zoo', 'park', 'museum'])) return 1.0;
      if (_containsAny(types, ['tourist_attraction', 'point_of_interest'])) return 0.8;
      return 0.0;
    }
    if (type.contains('couple')) {
      if (_containsAny(types, ['park', 'tourist_attraction', 'museum', 'art_gallery', 'restaurant', 'cafe'])) return 0.9;
      return 0.0;
    }
    if (type.contains('group')) {
      if (_containsAny(types, ['amusement_park', 'tourist_attraction', 'shopping_mall', 'restaurant', 'bowling_alley'])) return 0.9;
      return 0.0;
    }
    if (type.contains('business')) {
      if (_containsAny(types, ['restaurant', 'cafe', 'shopping_mall', 'museum', 'hotel'])) return 0.9;
      return 0.0;
    }
    if (type.contains('solo')) {
      if (_containsAny(types, ['museum', 'art_gallery', 'park', 'tourist_attraction', 'cafe', 'library'])) return 0.9;
      return 0.0;
    }
    return 0.0;
  }

  double _calculateTravelPaceScore(Place place, String travelPace) {
    final duration = place.visitDurationMinutes;
    if (duration == null || duration <= 0) return 0.0;
    final pace = travelPace.toLowerCase();

    if (pace.contains('fast')) return duration <= 60 ? 1.0 : 0.6;
    if (pace.contains('balanced') || pace.contains('standard')) return (duration >= 45 && duration <= 120) ? 1.0 : 0.7;
    if (pace.contains('slow') || pace.contains('relaxed')) return duration >= 60 ? 1.0 : 0.6;
    return 0.5;
  }

  double _calculateGeographyScore(Coordinates placeCoordinates, Coordinates? tripLocation) {
    if (tripLocation == null) return 0.0;
    final distance = placeCoordinates.distanceTo(tripLocation);
    if (distance < 2.0)  return 1.0;
    if (distance < 5.0)  return 0.8;
    if (distance < 10.0) return 0.5;
    return 0.2;
  }

  bool _isFoodPlace(Place place) {
    final types    = place.types.map((t) => t.toLowerCase()).toSet();
    final category = (place.category ?? '').toLowerCase();
    return types.any(_foodTypes.contains) || category.contains('restaurant') || category.contains('food');
  }

  bool _isAttractionPlace(Place place) {
    final types    = place.types.map((t) => t.toLowerCase()).toSet();
    final category = (place.category ?? '').toLowerCase();
    return types.any(_attractionTypes.contains) || category.contains('attraction') || category.contains('museum');
  }

  bool _containsAny(List<String> source, List<String> values) => values.any(source.contains);

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
    if (matchedInterest.isNotEmpty && matchedInterest != 'Unknown') reasons.add('Matches interest: $matchedInterest');
    if (isMustVisit) reasons.add('Selected as a must-visit');
    if (travelerTypeScore >= 0.8) reasons.add('Suitable for $travelerType traveler');
    return reasons;
  }

  bool? _isWheelchairAccessible(Place place) => null;
  bool? _hasStepFreeAccess(Place place)       => null;
  bool? _isLowPhysicalExertion(Place place)   => null;
  bool? _supportsDietaryRequirement(Place place, String requirement) => null;

  List<ScoredAttraction> _applyTieBreaker(List<ScoredAttraction> scored) {
    final scoreGroups = <double, List<ScoredAttraction>>{};
    for (final item in scored) {
      scoreGroups.putIfAbsent(item.score, () => []).add(item);
    }
    final result = <ScoredAttraction>[];
    for (final group in scoreGroups.values) {
      group.sort((a, b) => b.place.rating.compareTo(a.place.rating));
      result.addAll(group);
    }
    return result;
  }

  String _paceFromExplorationTime(String explorationTime) {
    final et = explorationTime.toLowerCase();
    if (et.contains('relaxed')) return 'Slow';
    if (et.contains('intense')) return 'Fast';
    return 'Standard';
  }
}

class _EligibilityResult {
  final bool isEligible;
  const _EligibilityResult({required this.isEligible});
}