import 'dart:math';
import 'coordinates.dart';

class TripDraft {
  // Step 1: Destinations
  final List<String> destinations;
  final Map<String, Coordinates> destinationCoordinates;

  // Step 2: Trip Style & Preferences
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? explorationTime;
  final String? travelPace;
  final List<String> interests;
  final String additionalNotes;
  final String transportation; // 'walking', 'driving', 'transit'
  final String? travelType;     // 'Solo', 'Family', 'Group', etc.

  // Step 3: Database Bookmarks & Wizard Selections
  final List<String> bookmarkedPlaceIds; // Loaded from DB (public.bookmarks)
  final List<String> mustVisitPlaceIds;  // Selected by traveler in Step 3

  // Step 4: Day Allocations
  final Map<String, int> daySplit;

  // Step 5 / Calculated Meta
  final Coordinates? tripLocation;

  const TripDraft({
    this.destinations = const [],
    this.destinationCoordinates = const {},
    this.title = '',
    this.startDate,
    this.endDate,
    this.explorationTime,
    this.travelPace,
    this.interests = const [],
    this.additionalNotes = '',
    this.transportation = 'walking',
    this.travelType,
    this.bookmarkedPlaceIds = const [],
    this.mustVisitPlaceIds = const [],
    this.daySplit = const {},
    this.tripLocation,
  });

  /// Total trip duration in days (defaults to 1 if dates are unselected).
  int get totalDays {
    if (startDate == null || endDate == null) return 1;
    final diff = endDate!.difference(startDate!).inDays + 1;
    return max(1, diff);
  }

  /// Primary target coordinates (first resolved destination or custom location).
  Coordinates? get primaryCoordinates =>
      tripLocation ?? destinationCoordinates.values.firstOrNull;

  /// Validates if all required wizard inputs are present before running ScoringService.
  bool get isReadyForGeneration {
    return destinations.isNotEmpty &&
        title.trim().isNotEmpty &&
        startDate != null &&
        endDate != null &&
        explorationTime != null &&
        travelPace != null &&
        interests.isNotEmpty;
  }

  /// Immutably copies state with optional updates across wizard steps.
  TripDraft copyWith({
    List<String>? destinations,
    Map<String, Coordinates>? destinationCoordinates,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? explorationTime,
    String? travelPace,
    List<String>? interests,
    String? additionalNotes,
    String? transportation,
    String? travelType,
    List<String>? bookmarkedPlaceIds,
    List<String>? mustVisitPlaceIds,
    Map<String, int>? daySplit,
    Coordinates? tripLocation,
  }) {
    return TripDraft(
      destinations: destinations != null ? List.unmodifiable(destinations) : this.destinations,
      destinationCoordinates: destinationCoordinates != null
          ? Map.unmodifiable(destinationCoordinates)
          : this.destinationCoordinates,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      explorationTime: explorationTime ?? this.explorationTime,
      travelPace: travelPace ?? this.travelPace,
      interests: interests != null ? List.unmodifiable(interests) : this.interests,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      transportation: transportation ?? this.transportation,
      travelType: travelType ?? this.travelType,
      bookmarkedPlaceIds: bookmarkedPlaceIds != null
          ? List.unmodifiable(bookmarkedPlaceIds)
          : this.bookmarkedPlaceIds,
      mustVisitPlaceIds: mustVisitPlaceIds != null
          ? List.unmodifiable(mustVisitPlaceIds)
          : this.mustVisitPlaceIds,
      daySplit: daySplit != null ? Map.unmodifiable(daySplit) : this.daySplit,
      tripLocation: tripLocation ?? this.tripLocation,
    );
  }
}