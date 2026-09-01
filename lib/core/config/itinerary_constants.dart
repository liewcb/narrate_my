// lib/core/config/itinerary_constants.dart

/// Central configuration for itinerary generation.
///
/// IMPORTANT:
/// This file contains RULES and CONFIGURATION only.
///
/// It should NOT store:
/// - Google Places results
/// - CandidatePool
/// - generated itinerary data
/// - current itinerary state
/// - user-specific data
///
/// Runtime data should be stored in CandidatePool / ItineraryPlanState.
class ItineraryConstants {
  ItineraryConstants._();

  // ============================================================
  // 1. GOOGLE PLACES / CANDIDATE DISCOVERY
  // ============================================================

  /// Initial radius used when searching around each destination.
  ///
  /// This is a SEARCH REFERENCE, not a hard itinerary boundary.
  static const double searchRadiusKm = 20.0;

  /// Maximum radius that progressive discovery can reach.
  static const double maxSearchRadiusKm = 50.0;

  /// Multiplier used when the current candidate pool
  /// is insufficient.
  ///
  /// Example:
  ///
  /// 20 km
  ///   ↓
  /// 30 km
  ///   ↓
  /// 45 km
  static const double expansionMultiplier = 1.5;

  /// Maximum number of broader-search attempts.
  static const int maxExpansionAttempts = 2;

  /// Prevent progressive discovery from expanding
  /// indefinitely away from the original destination.
  static const double maxDistanceFromOriginalAnchorKm = 50.0;

  // ============================================================
  // 2. BASIC PLACE QUALITY FILTERING
  // ============================================================

  /// Minimum Google rating accepted during basic filtering.
  ///
  /// This is NOT the final recommendation score.
  static const double minRating = 3.0;

  /// Default rating when a downstream service needs
  /// a fallback value.
  static const double defaultRating = 3.5;

  /// Default visit duration if the place does not
  /// have a calculated duration.
  static const int defaultDurationMinutes = 90;

  /// Default travel distance fallback.
  static const double defaultDistanceKm = 5.0;

  /// Maximum acceptable travel time between consecutive
  /// itinerary stops before validation raises an issue.
  static const double maxTravelTimeMinutes = 45.0;

  // ============================================================
  // 3. CANDIDATE POOL SUFFICIENCY
  // ============================================================

  /// Minimum number of candidates retained as a safety floor.
  ///
  /// This is NOT the only sufficiency rule.
  /// Actual sufficiency depends on:
  /// - trip duration
  /// - pace
  /// - stops per day
  /// - food requirements
  static const int minCandidatesAbsolute = 15;

  /// Extra candidates to retrieve because some candidates
  /// may later fail:
  ///
  /// - scoring
  /// - clustering
  /// - opening hours
  /// - travel time
  /// - schedule validation
  /// - user customization
  static const double candidateOverfetchFactor = 2.0;

  /// Maximum number of candidates kept by a higher-level
  /// candidate management layer if one is introduced.
  static const int maxCandidates = 150;

  /// Minimum food candidates expected for each trip day.
  ///
  /// Food is treated as supporting candidates rather than
  /// replacing attraction candidates.
  static const int minimumFoodCandidatesPerDay = 1;

  /// Maximum number of candidates sent to DeepSeek for the AI candidate
  /// evaluation / itinerary-planning pool.
  ///
  /// Keeps the prompt concise and avoids the timeouts caused by sending an
  /// unlimited candidate set (e.g. 103 candidates / ~40k-char prompts).
  /// The remaining scored candidates stay available as a RESERVE pool for
  /// feasibility-driven replacement during regeneration/repair.
  static const int maxAiPlanningPoolSize = 45;

  // ============================================================
  // 4. DAILY STOP LIMITS
  // ============================================================

  /// Minimum number of activity/attraction stops per day.
  static const int minAttractionsPerDay = 2;

  /// Maximum number of activity/attraction stops per day.
  static const int maxAttractionsPerDay = 6;

  /// Minimum total stops per day.
  ///
  /// Depending on the schedule, food may also become a stop.
  static const int minStopsPerDay = 2;

  /// Maximum total stops per day.
  static const int maxStopsPerDay = 12;

  // ============================================================
  // 5. PACE
  // ============================================================

  /// Number of attraction/activity stops targeted per day
  /// according to travel pace.
  ///
  /// DEPRECATED for candidate-target calculation: travel pace is a SOFT
  /// scheduling preference for DeepSeek, NOT a places-per-day formula.
  /// Kept only for legacy services (daily allocation, old clusterPlaces).
  static const Map<String, int> paceToAttractionsPerDay = {
    'Slow': 2,
    'Standard': 4,
    'Fast': 6,
  };

  /// Returns the target number of attraction stops per day.
  @Deprecated('Travel pace must not drive places/day. Use '
      'retrievalCandidateTarget() instead.')
  static int attractionsPerDayFor(String pace) {
    return paceToAttractionsPerDay[pace] ??
        paceToAttractionsPerDay['Standard']!;
  }

  /// Returns the target number of attractions for
  /// the complete trip.
  @Deprecated('Travel pace must not drive places/day. Use '
      'retrievalCandidateTarget() instead.')
  static int targetAttractions({
    required int days,
    required String pace,
  }) {
    return days *
        attractionsPerDayFor(pace);
  }

  /// ============================================================
  /// CANDIDATE POOL TARGETS (pace-independent)
  ///
  /// The candidate pool is a RETRIEVAL target, NOT a final itinerary size.
  /// Travel pace is deliberately NOT used as a places/day multiplier.
  /// ============================================================

  /// Neutral baseline of candidate places considered per trip day when
  /// sizing the retrieval target. This is NOT a final-stops-per-day rule —
  /// it is only used to decide how many alternatives to fetch.
  static const double candidatePerDayRetrievalBaseline = 6.0;

  /// Exploration-window factor: a longer available window can reasonably
  /// absorb more candidate alternatives.
  static double explorationRetrievalFactor(String? explorationTime) {
    switch (explorationTime) {
      case 'Relaxed':
        return 0.8;
      case 'Intense':
        return 1.2;
      case 'Standard':
      default:
        return 1.0;
    }
  }

  /// Retrieval target for the RAW (pre-filter) candidate pool.
  ///
  /// Based on: trip duration + exploration requirements + must-visit count +
  /// candidate diversity buffer. Travel pace is NOT used.
  static int retrievalCandidateTarget({
    required int days,
    required int mustVisitCount,
    String? explorationTime,
  }) {
    final base =
        (days * candidatePerDayRetrievalBaseline *
                explorationRetrievalFactor(explorationTime))
            .ceil();
    final buffered = (base * candidateOverfetchFactor).ceil() + mustVisitCount;
    return buffered < minCandidatesAbsolute
        ? minCandidatesAbsolute
        : buffered;
  }

  /// Minimum number of USABLE (post-filter) candidates that must remain
  /// before clustering + DeepSeek scheduling can proceed.
  static const int minimumUsableCandidatePool = 12;

  /// Usable candidate target: the post-filter pool must be comfortably
  /// larger than any plausible final itinerary so DeepSeek has alternatives.
  ///
  /// Based on trip duration × baseline × a usability buffer.  Does NOT
  /// compound the full overfetch factor (that already sized the raw pool).
  static int usableCandidateTarget({
    required int days,
    required int mustVisitCount,
    String? explorationTime,
  }) {
    final base =
        (days * candidatePerDayRetrievalBaseline *
                explorationRetrievalFactor(explorationTime) *
                1.5)
            .ceil();
    final usable = base + mustVisitCount;
    return usable < minimumUsableCandidatePool
        ? minimumUsableCandidatePool
        : usable;
  }

  /// Calculates how many attraction candidates should
  /// ideally be retrieved before filtering and planning.
  ///
  /// Backward-compatible wrapper. Travel pace is no longer used as a
  /// places/day multiplier; the target is derived from trip duration,
  /// exploration requirements and a diversity buffer.
  ///
  /// Example:
  ///
  /// 5 days × baseline + overfetch ≈ 60+ candidates
  static int targetCandidateCount({
    required int days,
    required String pace,
    int mustVisitCount = 0,
    String? explorationTime,
  }) {
    return retrievalCandidateTarget(
      days: days,
      mustVisitCount: mustVisitCount,
      explorationTime: explorationTime,
    );
  }

  // ============================================================
  // 6. EXPLORATION WINDOW
  // ============================================================

  static const Map<String, ExplorationWindow>
  explorationWindows = {
    'Relaxed': ExplorationWindow(
      startHour: 10,
      startMinute: 0,
      endHour: 18,
      endMinute: 0,
    ),

    'Standard': ExplorationWindow(
      startHour: 9,
      startMinute: 0,
      endHour: 20,
      endMinute: 0,
    ),

    'Intense': ExplorationWindow(
      startHour: 8,
      startMinute: 0,
      endHour: 22,
      endMinute: 0,
    ),
  };

  /// Returns the configured exploration window.
  ///
  /// Accepts either the bare label (`'Relaxed'`, `'Standard'`, `'Intense'`)
  /// or the Step 2 UI display label (`'Relaxed (10 AM - 6 PM)'`, …).
  static ExplorationWindow explorationWindowFor(
      String intensity,
      ) {
    // Normalise the display label "Standard (9 AM - 8 PM)" → "Standard".
    final trimmed = intensity.trim();
    final bare = trimmed.contains('(')
        ? trimmed.substring(0, trimmed.indexOf('(')).trim()
        : trimmed;

    // Also tolerate "Intense" ↔ "Fast" and "Slow" ↔ "Relaxed" synonyms.
    String key = bare;
    final lower = bare.toLowerCase();
    if (lower.contains('fast') || lower.contains('intense')) {
      key = 'Intense';
    } else if (lower.contains('slow') || lower.contains('relaxed')) {
      key = 'Relaxed';
    } else if (lower.contains('standard') || lower.contains('balanced')) {
      key = 'Standard';
    }

    return explorationWindows[key] ??
        explorationWindows['Standard']!;
  }

  // ============================================================
  // 7. SCHEDULING
  // ============================================================

  /// Buffer between activities.
  static const int bufferMinutes = 15;

  /// Minimum useful time for an activity.
  static const int minimumVisitDurationMinutes = 30;

  /// Maximum practical duration for a single activity.
  static const int maximumVisitDurationMinutes = 240;

  // ------------------------------------------------------------
  // Travel-pace buffers
  // ------------------------------------------------------------

  /// Transition buffer (minutes) between consecutive stops.
  /// FIXED values (not ranges) so the AI cannot drift:
  /// Fast 10, Standard 15, Relaxed 25.
  static const Map<String, int> paceToBufferMinutes = {
    'Slow': 25,
    'Standard': 15,
    'Fast': 10,
  };

  /// Normalise a pace label ("Relaxed", "Slow", "Balanced", "Fast", …)
  /// to a canonical key: Slow / Standard / Fast.
  static String _canonicalPace(String pace) {
    final lower = pace.trim().toLowerCase();
    if (lower.contains('slow') || lower.contains('relaxed')) return 'Slow';
    if (lower.contains('fast')) return 'Fast';
    return 'Standard';
  }

  static int bufferForPace(String pace) =>
      paceToBufferMinutes[_canonicalPace(pace)] ??
      paceToBufferMinutes['Standard']!;

  // ------------------------------------------------------------
  // Travel-pace duration factor
  // ------------------------------------------------------------

  /// Multiplier applied to the base visit duration.
  /// Relaxed → 1.20 (linger longer), Standard → 1.00, Fast → 0.85 (quicker).
  static const Map<String, double> paceToDurationFactor = {
    'Slow': 1.20,
    'Standard': 1.0,
    'Fast': 0.85,
  };

  static double durationFactorForPace(String pace) =>
      paceToDurationFactor[_canonicalPace(pace)] ??
      paceToDurationFactor['Standard']!;

  // ------------------------------------------------------------
  // Pace-aware preferred activity boundary (SOFT)
  // ------------------------------------------------------------

  /// Fraction of the exploration window that the scheduler normally fills
  /// with scheduled activity (visits + travel + buffers). The remainder is
  /// reserved as flexible / leisure time.
  ///
  /// This is a SOFT capacity: it is not a hard stop. Highly suitable stops
  /// (especially must-visits) may extend past it, but the day should not be
  /// packed merely because time remains. The HARD boundary is always
  /// [ExplorationWindow.endMinutes].
  static const Map<String, double> paceToPreferredCapacity = {
    'Slow': 0.65, // Relaxed: ~60-70%
    'Standard': 0.80, // Standard: ~75-85%
    'Fast': 0.92, // Fast: ~90-95%
  };

  /// The fraction of the exploration window normally used for scheduling.
  static double preferredCapacityForPace(String pace) =>
      paceToPreferredCapacity[_canonicalPace(pace)] ??
      paceToPreferredCapacity['Standard']!;

  /// Compute the preferred (soft) activity end boundary in minutes-of-day
  /// for [window], using [pace].
  static int preferredActivityEndMinute(ExplorationWindow window, String pace) {
    final capacity = preferredCapacityForPace(pace);
    final span = window.endMinutes - window.startMinutes;
    final used = (span * capacity).round();
    return window.startMinutes + used;
  }

  // ------------------------------------------------------------
  // Category-aware base visit durations (minutes)
  // ------------------------------------------------------------

  /// Reasonable base visit duration by place category (midpoint of the
  /// reasonable estimate ranges from the prompt spec). Used by the
  /// deterministic scheduler so it never assigns a uniform duration to
  /// every place.
  static const Map<String, int> categoryBaseDurationMinutes = {
    'landmark': 65, // 45-90
    'religious': 65, // 45-90 (historic/cultural site)
    'museum': 105, // 90-120+
    'cultural': 105, // 90-120+ (galleries/exhibitions)
    'art_gallery': 105, // 90-120+
    'nature': 60, // 45-75 (parks/outdoors/bridges)
    'park': 60, // 45-75
    'restaurant': 75, // 60-90 (full restaurants/bistros)
    'cafe': 50, // 45-60 (cafes/casual)
    'bakery': 50, // 45-60
    'shopping': 90, // 60-120+ (malls)
    'nightlife': 90, // 60-120+
    'adventure': 120, // theme parks etc.
  };

  /// Resolve a category-aware base duration for a place.
  ///
  /// Falls back to [defaultDurationMinutes] when the category is unknown.
  static int baseDurationForCategory(String? category, int fallback) {
    if (category == null || category.isEmpty) return fallback;
    final key = category.toLowerCase().trim();
    return categoryBaseDurationMinutes[key] ?? fallback;
  }

  // ------------------------------------------------------------
  // Travel-pace planning rules (for the AI prompt)
  // ------------------------------------------------------------

static const String paceSlowRules = '''
════════════════════════════════════════════════════════════════
MANDATORY TIME & PLACEMENT RULES (NON-NEGOTIABLE)
════════════════════════════════════════════════════════════════

1. FULL WINDOW UTILIZATION (STOP AT {explorationEnd})
   - The FIRST stop MUST start at EXACTLY {explorationStart}.
   - EVERY subsequent stop chains consecutively: startTime = previous endTime + travelTime + buffer.
   - THE FINAL STOP OF THE DAY MUST END AS CLOSE TO {explorationEnd} AS POSSIBLE.
   - A relaxed pace does NOT mean finishing the day early. You must continue scheduling stops (with generous buffers and longer visits) until the final stop naturally reaches {explorationEnd}.
   - ABSOLUTE LIMIT: No stop may end after {explorationEnd}.

2. DYNAMIC & UNLIMITED PLACE COUNT (RELAXED PACE RULES)
   - THERE IS NO FIXED PLACE COUNT. Do not default to 3 or any arbitrary number.
   - For [RELAXED] pace: Use fewer, high-quality places, longer visit durations, and large buffers (25-40m). Because visits and buffers are longer, fewer total places will be needed to stretch all the way from {explorationStart} to {explorationEnd}.
   - Keep adding places sequentially until the next stop would exceed {explorationEnd}. Ensure the day feels complete and stretches right up to the end time.

3. TRAVEL PACE BEHAVIOR
   - [FAST]: Denser schedule, short buffers, maximum locations ending near {explorationEnd}.
   - [STANDARD]: Balanced schedule, moderate buffers, steady flow ending near {explorationEnd}.
   - [RELAXED]: Spacious schedule, longer visits, generous buffers, meaning fewer total stops, but still stretching comfortably all the way until {explorationEnd}.
''';

  static const String paceStandardRules = '''
════════════════════════════════════════════════════════════════
MANDATORY TIME & PLACEMENT RULES — STANDARD PACE
════════════════════════════════════════════════════════════════

1. FULL WINDOW UTILIZATION (STOP AT {explorationEnd})
   - The FIRST stop MUST start at EXACTLY {explorationStart}.
   - EVERY subsequent stop chains consecutively: startTime = previous endTime + travelTime + buffer.
   - THE FINAL STOP OF THE DAY MUST END AS CLOSE TO {explorationEnd} AS POSSIBLE. Maintain a steady, comfortable flow that naturally spans the entire day.
   - ABSOLUTE LIMIT: No stop may end after {explorationEnd}.

2. DYNAMIC & UNLIMITED PLACE COUNT (STANDARD PACE RULES)
   - THERE IS NO FIXED PLACE COUNT. Do not default to any arbitrary number.
   - For [STANDARD] pace: Use a balanced, moderate number of places with standard baseline visit durations and realistic transition buffers (15-20 mins).
   - Keep adding places sequentially until the next stop would exceed {explorationEnd}. Ensure the day feels well-paced, balanced, and stretches naturally all the way to the end time.
''';

  static const String paceFastRules = '''
════════════════════════════════════════════════════════════════
MANDATORY TIME & PLACEMENT RULES — FAST PACE
════════════════════════════════════════════════════════════════

1. FULL WINDOW UTILIZATION (STOP AT {explorationEnd})
   - The FIRST stop MUST start at EXACTLY {explorationStart}.
   - EVERY subsequent stop chains consecutively: startTime = previous endTime + travelTime + buffer.
   - THE FINAL STOP OF THE DAY MUST END AS CLOSE TO {explorationEnd} AS POSSIBLE. Pack the schedule densely so that the itinerary utilizes the available time right up to the deadline.
   - ABSOLUTE LIMIT: No stop may end after {explorationEnd}.

2. DYNAMIC & UNLIMITED PLACE COUNT (FAST PACE RULES)
   - THERE IS NO FIXED PLACE COUNT. Do not default to any arbitrary number.
   - For [FAST] pace: Maximize the number of suitable candidate places. Use concise, efficient visit durations and tight transition buffers (10-15 mins).
   - Keep adding subsequent places sequentially until adding another stop would exceed {explorationEnd}. Ensure a high-density, efficient flow across the entire window.
''';

  /// Resolve the pace rules for [pace], injecting the actual exploration
  /// window (e.g. "10:00 - 18:00") into the placeholders.
  static String paceRulesFor(
    String pace, {
    String explorationStart = 'exploration start',
    String explorationEnd = 'exploration end',
  }) {
    String rules;
    switch (_canonicalPace(pace)) {
      case 'Slow':
        rules = paceSlowRules;
        break;
      case 'Fast':
        rules = paceFastRules;
        break;
      default:
        rules = paceStandardRules;
    }
    return rules
        .replaceAll('{explorationStart}', explorationStart)
        .replaceAll('{explorationEnd}', explorationEnd);
  }

  // ------------------------------------------------------------
  // Meal windows
  // ------------------------------------------------------------

  static const int lunchStartHour = 11;
  static const int lunchEndHour = 14;

  static const int dinnerStartHour = 17;
  static const int dinnerEndHour = 21;

  /// Maximum number of food stops normally planned per day.
  ///
  /// This prevents the schedule from becoming mostly restaurants.
  static const int maxFoodStopsPerDay = 2;

  /// Minimum number of food options that should remain
  /// available for scheduling/alternatives.
  static const int minimumFoodOptionsPerDay = 1;

  // ============================================================
  // 8. ROUTE
  // ============================================================

  /// Preferred maximum walking distance between stops.
  static const double preferredMaxWalkKm = 2.0;

  /// Preferred maximum route travel time.
  static const int preferredMaxTravelMinutes = 30;

  /// Maximum route travel time before the route becomes
  /// a validation concern.
  static const int hardMaxTravelMinutes = 60;

  // ============================================================
  // 9. CLUSTERING
  // ============================================================

  /// Initial geographic clustering radius.
  static const double clusterRadiusKm = 5.0;

  /// Maximum clustering iterations.
  static const int maxClusteringIterations = 100;

  /// Minimum places required to create a meaningful cluster.
  static const int minimumPlacesPerCluster = 2;

  // ============================================================
  // 10. SCORING
  // ============================================================

  /// Weight for matching traveler interests.
  static const double weightInterest = 0.40;

  /// Weight for must-visit places.
  static const double weightMustVisit = 0.30;

  /// Weight for Google rating.
  static const double weightRating = 0.15;

  /// Weight for time/opening-hour suitability.
  static const double weightTimeFit = 0.10;

  /// Weight for geographic suitability.
  static const double weightGeography = 0.05;

  // ============================================================
  // 11. AI ROUTE / SCHEDULE
  // ============================================================

  /// Maximum number of AI attempts for route generation.
  static const int maxAIRouteAttempts = 3;

  /// Maximum number of AI attempts for schedule generation.
  static const int maxAIScheduleAttempts = 3;

  /// Maximum number of localized regeneration attempts.
  static const int maxLocalRegenerationAttempts = 3;

  /// Maximum number of complete itinerary regeneration attempts.
  static const int maxRegenerationAttempts = 3;

  // ============================================================
  // 12. VALIDATION
  // ============================================================

  /// Maximum validation attempts before deterministic
  /// force-repair is triggered.
  static const int maxValidationAttempts = 3;

  /// Whether validation should fail if a stop has no
  /// opening-hour information.
  ///
  /// FALSE because Google may not provide opening hours.
  static const bool missingOpeningHoursIsFatal = false;

  /// Whether missing rating should automatically invalidate
  /// a place.
  static const bool missingRatingIsFatal = false;

  // ============================================================
  // 13. PLAN STATE / EDITING
  // ============================================================

  /// Maximum number of historical plan versions retained
  /// during the current session.
  static const int maxPlanHistory = 5;

  /// Maximum number of stops allowed after a user adds
  /// a new place.
  static const int maxStopsAfterCustomization = 8;

  /// Radius (in meters) used when retrieving nearby places for
  /// inserting a custom place into an existing itinerary day.
  ///
  /// Configurable so the search area can be tuned without touching
  /// application code.
  static const double customPlaceSearchRadiusMeters = 2500.0;

  // ============================================================
  // 14. AI SAFETY
  // ============================================================

  /// AI must not invent a place that is not present
  /// in the known candidate pool.
  static const bool aiMustUseKnownCandidates = true;

  /// AI may select from the original candidate pool
  /// when modifying an existing itinerary.
  static const bool aiCanReuseCandidatePool = true;

  /// AI should not be responsible for creating
  /// geographic coordinates.
  static const bool aiCannotInventCoordinates = true;

  /// AI should not replace the original Place object.
  ///
  /// AI returns a placeId; the application retrieves
  /// the corresponding Place from CandidatePool.
  static const bool preserveOriginalPlaceData = true;

  // ============================================================
  // 15. CANDIDATE DISCOVERY POLICY
  // ============================================================

  /// Candidates are initially searched around the
  /// destination reference point.
  static const bool useDestinationAsSearchReference = true;
  /// Progressive discovery may expand the search area
  /// when the candidate pool is insufficient.
  static const bool allowProgressiveDiscovery = true;

  /// New candidates are merged into the existing pool
  /// rather than replacing the old pool.
  static const bool mergeExpandedCandidates = true;

  /// Candidate uniqueness is based on Google Place ID.
  static const bool deduplicateByPlaceId = true;

  // ============================================================
  // 16. DEBUG
  // ============================================================

  static const bool enableCandidateDebugLogs = true;

  static const bool enableScoringDebugLogs = true;

  static const bool enableClusteringDebugLogs = true;

  static const bool enableRouteDebugLogs = true;

  static const bool enableScheduleDebugLogs = true;

  static const bool enableValidationDebugLogs = true;
}

/// Represents the daily exploration time window.
class ExplorationWindow {
  final int startHour;
  final int startMinute;

  final int endHour;
  final int endMinute;

  const ExplorationWindow({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  int get startMinutes =>
      startHour * 60 + startMinute;

  int get endMinutes =>
      endHour * 60 + endMinute;

  int get totalMinutes =>
      endMinutes - startMinutes;

  int get availableMinutes =>
      endMinutes - startMinutes;

  @override
  String toString() {
    final start =
        '${startHour.toString().padLeft(2, '0')}:'
        '${startMinute.toString().padLeft(2, '0')}';

    final end =
        '${endHour.toString().padLeft(2, '0')}:'
        '${endMinute.toString().padLeft(2, '0')}';

    return '$start - $end';
  }
}