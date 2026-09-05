// lib/model/business_logic/itinerary_service/itinerary_generation_status.dart
//
// Structured, traveler-facing classification of an itinerary generation
// outcome. The generation pipeline classifies WHY it produced the result it
// did; the UI renders the mapped message verbatim and never guesses reasons
// or surfaces raw exception strings.

/// Traveler-facing classification of an itinerary generation result.
enum ItineraryGenerationStatus {
  /// Normal successful generation.
  success,

  /// No places matching the selected interests/requirements were found.
  noSuitablePlaces,

  /// Some suitable places were found, but not enough to fill the requested
  /// schedule — free time remains instead of forcing unrelated places in.
  fewSuitablePlaces,

  /// A must-visit place could not be retrieved, scheduled, or did not
  /// satisfy the itinerary constraints.
  mustVisitUnavailable,

  /// A must-visit place does not belong to the planned destination/travel
  /// area.
  mustVisitOutsideDestination,

  /// Places exist but their opening hours prevent them from being scheduled.
  openingHoursConflict,

  /// Too many selected activities for the available travel time/day capacity.
  scheduleTooFull,

  /// Places were removed because travel time/distance violated route
  /// constraints.
  travelDistanceTooLong,

  /// The AI service failed/unavailable, but the deterministic fallback
  /// successfully created an itinerary.
  aiUnavailable,

  /// The AI returned an invalid/unusable response, but an alternative
  /// fallback itinerary was successfully generated.
  aiResponseInvalid,
}

extension ItineraryGenerationStatusX on ItineraryGenerationStatus {
  /// The EXACT traveler-facing message for this status. The UI renders this
  /// verbatim — no technical/API/exception details may be appended.
  String get message => switch (this) {
        ItineraryGenerationStatus.success =>
          'Your itinerary has been created based on your preferences, '
              'travel pace, and available places.',
        ItineraryGenerationStatus.noSuitablePlaces =>
          'No suitable places found for your preferences.',
        ItineraryGenerationStatus.fewSuitablePlaces =>
          'Only a few suitable places were found. Some free time has been '
              'added to your itinerary.',
        ItineraryGenerationStatus.mustVisitUnavailable =>
          'One or more of your selected places could not be included in the '
              'itinerary.',
        ItineraryGenerationStatus.mustVisitOutsideDestination =>
          'Some selected places are outside your planned destination.',
        ItineraryGenerationStatus.openingHoursConflict =>
          'Some places could not be scheduled within their opening hours.',
        ItineraryGenerationStatus.scheduleTooFull =>
          'Your selected activities could not all fit into the available '
              'time.',
        ItineraryGenerationStatus.travelDistanceTooLong =>
          'Some places were excluded because they require too much travel '
              'time.',
        ItineraryGenerationStatus.aiUnavailable =>
          "We couldn't generate the personalized plan right now, so a "
              'standard itinerary was created for you.',
        ItineraryGenerationStatus.aiResponseInvalid =>
          "We couldn't complete the personalized plan, so we've created an "
              'alternative itinerary for you.',
      };

  /// Severity rank used when multiple problems occur — the LOWEST rank wins
  /// (requirement priority: must-visit issues > no places > constraint
  /// conflicts > partial results > AI degradation > success).
  int get severityRank => switch (this) {
        ItineraryGenerationStatus.mustVisitOutsideDestination => 0,
        ItineraryGenerationStatus.mustVisitUnavailable => 1,
        ItineraryGenerationStatus.noSuitablePlaces => 2,
        ItineraryGenerationStatus.openingHoursConflict => 3,
        ItineraryGenerationStatus.travelDistanceTooLong => 4,
        ItineraryGenerationStatus.scheduleTooFull => 5,
        ItineraryGenerationStatus.fewSuitablePlaces => 6,
        ItineraryGenerationStatus.aiUnavailable => 7,
        ItineraryGenerationStatus.aiResponseInvalid => 8,
        ItineraryGenerationStatus.success => 9,
      };
}

/// Picks the most important status from a set of findings (null-safe).
ItineraryGenerationStatus? mostSevereStatus(
  Iterable<ItineraryGenerationStatus?> statuses,
) {
  ItineraryGenerationStatus? best;
  for (final s in statuses) {
    if (s == null) continue;
    if (best == null || s.severityRank < best.severityRank) best = s;
  }
  return best;
}
