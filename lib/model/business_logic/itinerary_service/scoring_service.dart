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

/// Candidate Scoring and Ranking Service.
///
/// Determines how RELEVANT a candidate place is to the user.
/// It does NOT build the itinerary: no day assignment, no route sequencing,
/// no start/end times, no stop count, no transportation routing.
///
/// Scoring model (simple weighted):
///   Interest Relevance = 70%
///   Google Rating      = 30%
///
/// Deliberately NOT used as scoring dimensions (they are passed to DeepSeek
/// as planning context instead):
///   - traveler type
///   - travel pace
///   - transportation mode
///   - destination-center geographic distance
class ScoringService {
  static const double weightInterest = 0.70;
  static const double weightRating = 0.30;

  static const double nonInterestPenalty = 0.0;

  static const List<String> _foodTypes = [
    'restaurant',
    'cafe',
    'bakery',
    'meal_takeaway',
    'meal_delivery',
  ];

  static const List<String> _attractionTypes = [
    'tourist_attraction',
    'museum',
    'art_gallery',
    'park',
    'natural_feature',
    'place_of_worship',
    'amusement_park',
    'zoo',
    'aquarium',
    'shopping_mall',
    'night_club',
    'casino',
    'stadium',
    'bowling_alley',
    'movie_theater',
    'garden',
    'beach',
  ];

  /// Hard-blocked types — transport / utility places are never candidates.
  static const Set<String> _hardBlockedTypes = {
    'airport',
    'train_station',
    'transit_station',
    'subway_station',
    'bus_station',
    'taxi_stand',
    'gas_station',
    'parking',
    'police',
    'fire_station',
    'local_government_office',
    'cemetery',
  };

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
    bool strictInterestFilter = true,
    int minPoolFloor = 3,
    bool enableDebugLogs = false,
  }) {
    if (enableDebugLogs) {
      debugPrint('[SCORING] ── INPUT ──────────────────────────────────');
      debugPrint('[SCORING] Total places     : ${places.length}');
      debugPrint('[SCORING] Interests        : $selectedInterests');
      debugPrint('[SCORING] Must-visit IDs   : $mustVisitIds');
      debugPrint('[SCORING] Weight model     : interest=$weightInterest '
          'rating=$weightRating');
    }

    final mustVisitIdsSet = mustVisitIds.toSet();

    // ── STAGE 1: Eligibility + scoring ─────────────────────────────────────
    final scored = <ScoredAttraction>[];
    int blockedCount = 0;

    for (final place in places) {
      // Hard-block transport / utility types (must-visits still allowed).
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

      // ── Interest relevance (0..1) ──────────────────────────────
      final interestScore = _calculateInterestScore(
        place.types,
        selectedInterests,
      );
      final matchedInterest = _findMatchedInterest(
        place.types,
        selectedInterests,
      );

      // ── Google rating (0..1) ───────────────────────────────────
      final ratingScore = (place.rating / 5.0).clamp(0.0, 1.0);

      // ── Weighted total ─────────────────────────────────────────
      final rawScore =
          interestScore * weightInterest +
              ratingScore * weightRating;

      final totalScore = rawScore.clamp(0.0, 1.0);

      final reasons = <String>[];
      if (isMustVisit) {
        reasons.add('Selected as a must-visit place');
      }
      if (matchedInterest.isNotEmpty && matchedInterest != 'Unknown') {
        reasons.add('Matches traveler interest: $matchedInterest');
      }
      if (ratingScore >= 0.8) {
        reasons.add('Highly rated by Google Places');
      }
      if (interestScore <= 0.0 && selectedInterests.isNotEmpty) {
        reasons.add('Does not match any selected interest');
      }

      scored.add(ScoredAttraction(
        place: place,
        score: (totalScore * 100).roundToDouble() / 100,
        breakdown: {
          'interest': interestScore,
          'rating': ratingScore,
          'total': totalScore,
        },
        isMustVisit: isMustVisit,
        matchedInterest: matchedInterest,
        isEligible: true,
        reasons: reasons,
      ));
    }

    if (enableDebugLogs) {
      debugPrint('[SCORING] After scoring    : ${scored.length} eligible '
          '(blocked $blockedCount)');
    }

    // ── STAGE 2: Strict interest filter with pool floor ────────────────────
    // A verified must-visit is NEVER removed by this filter.
    var pool = scored;
    if (strictInterestFilter && selectedInterests.isNotEmpty) {
      final matching = scored
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

    // ── STAGE 3: Sort by score ─────────────────────────────────────────────
    pool.sort((a, b) => b.score.compareTo(a.score));

    if (enableDebugLogs) {
      final resultAttrs =
          pool.where((s) => _isAttractionPlace(s.place)).length;
      final resultFood = pool.where((s) => _isFoodPlace(s.place)).length;
      debugPrint('[SCORING] ── OUTPUT ─────────────────────────────────');
      debugPrint('[SCORING] Total survived   : ${pool.length}');
      debugPrint('[SCORING] Attractions      : $resultAttrs');
      debugPrint('[SCORING] Food/Drink       : $resultFood');
      debugPrint('[SCORING] Must-visits      : '
          '${pool.where((s) => s.isMustVisit).length}');
      for (final s in pool.take(10)) {
        debugPrint(
          '[SCORING]   ${s.score.toStringAsFixed(2)} | ${s.place.name} '
              '| interest=${s.matchedInterest} | '
              'mustVisit=${s.isMustVisit}',
        );
      }
    }

    return pool;
  }

  // ============================================================
  // INTEREST SCORE
  // ============================================================

  /// Computes how strongly a place matches the user's selected interests.
  ///
  /// A place is not punished merely because the user selected many interests.
  /// The score reflects the strongest single match: a place matching one
  /// interest well receives a meaningful score rather than a diluted one.
  double _calculateInterestScore(
      List<String> placeTypes,
      List<String> selectedInterests,
      ) {
    if (selectedInterests.isEmpty || placeTypes.isEmpty) return 0.0;

    final placeTypeSet = placeTypes.map((t) => t.toLowerCase()).toSet();
    double best = 0.0;

    for (final interest in selectedInterests) {
      final interestTypes = InterestMapping
          .getGoogleTypesForInterest(interest)
          .map((t) => t.toLowerCase())
          .toList();
      if (interestTypes.isEmpty) continue;

      // Fraction of this interest's types matched by the place.
      var matched = 0;
      for (final type in interestTypes) {
        if (placeTypeSet.contains(type)) matched++;
      }
      final coverage = matched / interestTypes.length;
      if (coverage > best) best = coverage;
    }

    return best.clamp(0.0, 1.0);
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
  // PLACE CATEGORY HELPERS
  // ============================================================

  bool _isFoodPlace(Place place) {
    final types = place.types.map((t) => t.toLowerCase()).toSet();
    final category = (place.category ?? '').toLowerCase();
    return types.any(_foodTypes.contains) ||
        category.contains('restaurant') ||
        category.contains('food') ||
        category.contains('cafe') ||
        category.contains('bar');
  }

  bool _isAttractionPlace(Place place) {
    final types = place.types.map((t) => t.toLowerCase()).toSet();
    final category = (place.category ?? '').toLowerCase();
    return types.any(_attractionTypes.contains) ||
        category.contains('attraction') ||
        category.contains('landmark') ||
        category.contains('museum') ||
        category.contains('park');
  }
}
