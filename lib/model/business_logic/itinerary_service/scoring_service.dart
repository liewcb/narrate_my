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

  /// Hard-blocked types — transport, medical, and utility places are never candidates.
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
    'pharmacy',
    'drugstore',
    'convenience_store',
    'supermarket',
    'grocery_or_supermarket',
    'bank',
    'atm',
    'post_office',
    'hospital',
    'doctor',
    'dentist',
    'physiotherapist',
    'car_repair',
    'car_dealer',
    'car_rental',
    'car_wash',
    'laundry',
    'hair_care',
    'beauty_salon',
    'storage',
    'funeral_home',
    'travel_agency',
  };

  List<ScoredAttraction> scorePlaces({
    required List<Place> places,
    required List<String> selectedInterests,
    required List<String> mustVisitIds,
    required String explorationTime,
    Coordinates? tripLocation,
    String travelerType = 'Solo',
    String transportMode = 'walking',
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
      debugPrint('[SCORING] Traveler type    : $travelerType');
      debugPrint('[SCORING] Transport mode   : $transportMode');
      debugPrint('[SCORING] Weight model     : interest=$weightInterest '
          'rating=$weightRating');
    }

    final mustVisitIdsSet = mustVisitIds.toSet();

    // ── STAGE 1: Eligibility + scoring ─────────────────────────────────────
    final scored = <ScoredAttraction>[];
    int blockedCount = 0;

    for (final place in places) {
      // Hard-block transport / utility / retail pharmacy types (must-visits still allowed).
      final isMustVisit = mustVisitIdsSet.contains(place.placeId);
      final placeTypesLower = place.types.map((t) => t.toLowerCase()).toSet();
      final isBlockedType = placeTypesLower.any(_hardBlockedTypes.contains);

      final nameLower = place.name.toLowerCase();
      final isBlockedName = nameLower.contains('guardian') ||
          nameLower.contains('watsons') ||
          nameLower.contains('caring pharmacy') ||
          nameLower.contains('7-eleven') ||
          nameLower.contains('familymart') ||
          nameLower.contains('kk super mart') ||
          nameLower.contains('clinic') ||
          nameLower.contains('klinik') ||
          nameLower.contains('dental') ||
          nameLower.contains('pharmacy') ||
          nameLower.contains('taxi') ||
          nameLower.contains('hotel transfer') ||
          nameLower.contains('car rental') ||
          nameLower.contains('van rental') ||
          nameLower.contains('tour package');

      if ((isBlockedType || isBlockedName) && !isMustVisit) {
        blockedCount++;
        if (enableDebugLogs) {
          debugPrint('[SCORING] BLOCKED (utility/pharmacy/taxi) : ${place.name} '
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

      // ── Core Sightseeing & Landmark Bonus ──────────────────────
      final isFoodVenue = placeTypesLower.any((t) =>
          t == 'restaurant' ||
          t == 'cafe' ||
          t == 'bakery' ||
          t == 'food' ||
          t == 'meal_takeaway' ||
          t == 'meal_delivery') ||
          (place.category ?? '').toLowerCase().contains('food') ||
          (place.category ?? '').toLowerCase().contains('restaurant') ||
          (place.category ?? '').toLowerCase().contains('cafe');

      final isNightlifeVenue = placeTypesLower.any((t) =>
          t == 'bar' ||
          t == 'night_club' ||
          t == 'casino' ||
          t == 'wine_bar' ||
          t == 'liquor_store') ||
          (place.category ?? '').toLowerCase().contains('bar') ||
          (place.category ?? '').toLowerCase().contains('nightlife');

      final isReligiousPlace = !isFoodVenue && !isNightlifeVenue && placeTypesLower.any((t) =>
          t == 'place_of_worship' ||
          t == 'hindu_temple' ||
          t == 'church' ||
          t == 'mosque' ||
          t == 'synagogue');

      final isSecularAttraction = !isFoodVenue && !isNightlifeVenue && !isReligiousPlace && placeTypesLower.any((t) =>
          t == 'tourist_attraction' ||
          t == 'museum' ||
          t == 'art_gallery' ||
          t == 'park' ||
          t == 'natural_feature' ||
          t == 'amusement_park' ||
          t == 'theme_park' ||
          t == 'water_park' ||
          t == 'zoo' ||
          t == 'aquarium' ||
          t == 'botanical_garden' ||
          t == 'hiking_area' ||
          t == 'beach' ||
          t == 'historical_landmark' ||
          t == 'monument' ||
          t == 'scenic_viewpoint');

      var adjustedInterestScore = interestScore;
      if (isSecularAttraction && adjustedInterestScore < 0.65) {
        adjustedInterestScore = 0.65;
      } else if (isReligiousPlace && adjustedInterestScore < 0.52) {
        adjustedInterestScore = 0.52;
      }

      // Food cap: food venues are for meals, not primary tourist sights
      if (isFoodVenue && adjustedInterestScore > 0.40) {
        adjustedInterestScore = 0.40;
      }

      // Nightlife cap: nightlife venues score moderately so they can be chosen for evening
      if (isNightlifeVenue && adjustedInterestScore > 0.42) {
        adjustedInterestScore = 0.42;
      }

      // ── Google rating (0..1) ───────────────────────────────────
      final ratingScore = (place.rating / 5.0).clamp(0.0, 1.0);

      // Core attraction boost: secular sights get +0.12, religious places get +0.03
      final attractionBonus = isSecularAttraction
          ? 0.12
          : (isReligiousPlace ? 0.03 : (isNightlifeVenue ? 0.05 : 0.0));

      // Local authentic coffee & regional specialty boost for dining
      var localSpecialtyBonus = 0.0;
      if (isFoodVenue) {
        final nameLower = place.placeName.toLowerCase();
        if (nameLower.contains('kopi') ||
            nameLower.contains('coffee') ||
            nameLower.contains('kopitiam') ||
            nameLower.contains('cafe') ||
            nameLower.contains('nyonya') ||
            nameLower.contains('cendol') ||
            nameLower.contains('satay') ||
            nameLower.contains('chicken rice') ||
            nameLower.contains('laksa') ||
            nameLower.contains('peranakan') ||
            nameLower.contains('baba') ||
            nameLower.contains('jonker') ||
            nameLower.contains('melaka') ||
            nameLower.contains('dim sum') ||
            nameLower.contains('roti')) {
          localSpecialtyBonus = 0.18;
        }
      }

      // ── Traveler Type Alignment (Family / Couple / Friends / Solo) ─────
      var travelerTypeBonus = 0.0;
      final typeLower = travelerType.toLowerCase();
      if (typeLower.contains('family')) {
        // Family friendly: parks, zoos, aquariums, theme parks, museums, beaches
        final isFamilyFriendly = placeTypesLower.any((t) =>
            t == 'amusement_park' ||
            t == 'theme_park' ||
            t == 'water_park' ||
            t == 'zoo' ||
            t == 'aquarium' ||
            t == 'park' ||
            t == 'museum' ||
            t == 'botanical_garden' ||
            t == 'beach');
        if (isFamilyFriendly) {
          travelerTypeBonus = 0.14;
        } else if (isNightlifeVenue || isBlockedName) {
          travelerTypeBonus = -0.30; // Strongly avoid bars/clubs for families
        }
      } else if (typeLower.contains('couple')) {
        // Romantic / aesthetic: viewpoints, art galleries, cafes, quiet nature
        final isCoupleFriendly = placeTypesLower.any((t) =>
            t == 'scenic_viewpoint' ||
            t == 'art_gallery' ||
            t == 'cafe' ||
            t == 'beach' ||
            t == 'botanical_garden') ||
            nameLower.contains('sunset') ||
            nameLower.contains('view') ||
            nameLower.contains('bistro') ||
            nameLower.contains('lounge');
        if (isCoupleFriendly) {
          travelerTypeBonus = 0.14;
        }
      } else if (typeLower.contains('friend')) {
        // Vibrant: markets, amusement, entertainment, street food
        final isSocial = placeTypesLower.any((t) =>
            t == 'amusement_park' ||
            t == 'bowling_alley' ||
            t == 'cafe' ||
            t == 'night_club' ||
            t == 'bar') ||
            nameLower.contains('market') ||
            nameLower.contains('food court');
        if (isSocial) travelerTypeBonus = 0.10;
      }

      // ── Distance & Transport Penalty ────────────────────────────
      // Prevents recommending distant places (e.g. driving 2 hours for curry puff)
      var distancePenalty = 0.0;
      if (tripLocation != null &&
          place.latitude.abs() <= 90 &&
          place.longitude.abs() <= 180 &&
          !(place.latitude == 0 && place.longitude == 0)) {
        final distKm = tripLocation.distanceTo(place.coordinates);
        final mode = transportMode.toLowerCase();

        if (mode == 'walking') {
          if (distKm > 2.0) {
            distancePenalty = ((distKm - 2.0) * 0.08).clamp(0.0, 0.45);
          }
        } else {
          // Driving or transit: reasonable destination area is ~12km
          if (distKm > 12.0) {
            distancePenalty = ((distKm - 12.0) * 0.02).clamp(0.0, 0.45);
          }
          // Extra penalty for minor food / snack stalls far from city center
          if (isFoodVenue && distKm > 10.0 && !isMustVisit) {
            distancePenalty += 0.20;
          }
        }
      }

      // ── Weighted total ─────────────────────────────────────────
      final rawScore = adjustedInterestScore * weightInterest +
          ratingScore * weightRating +
          attractionBonus +
          localSpecialtyBonus +
          travelerTypeBonus -
          distancePenalty;

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
