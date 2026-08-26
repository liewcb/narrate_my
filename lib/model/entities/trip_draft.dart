// lib/model/entities/trip_draft.dart
import 'coordinates.dart';

/// Mutable trip draft shared across the 5‑step wizard.
class TripDraft {
  // Step 1
  final List<String> destinations;
  /// Destination name → coordinates (resolved in Step 1 from the DB).
  final Map<String, Coordinates> destinationCoordinates;
  // Step 2
  final String tripName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? explorationTime;
  final String? travelPace;
  final List<String> interests;
  final String additionalNotes;
  final String transportMode; // 'walking', 'driving', 'transit'
  // Step 3
  final List<String> mustVisitIds;
  // Step 4
  final Map<String, int> daySplit; // destination name -> allocated days

  const TripDraft({
    this.destinations = const [],
    this.destinationCoordinates = const {},
    this.tripName = '',
    this.startDate,
    this.endDate,
    this.explorationTime,
    this.travelPace,
    this.interests = const [],
    this.additionalNotes = '',
    this.transportMode = 'walking',
    this.mustVisitIds = const [],
    this.daySplit = const {},
  });

  int get totalDays {
    if (startDate == null || endDate == null) return 1;
    return endDate!.difference(startDate!).inDays + 1;
  }

  /// Coordinates for a destination, or null when not resolved yet.
  Coordinates? coordinatesFor(String destination) =>
      destinationCoordinates[destination];

  TripDraft copyWith({
    List<String>? destinations,
    Map<String, Coordinates>? destinationCoordinates,
    String? tripName,
    DateTime? startDate,
    DateTime? endDate,
    String? explorationTime,
    String? travelPace,
    List<String>? interests,
    String? additionalNotes,
    String? transportMode,
    List<String>? mustVisitIds,
    Map<String, int>? daySplit,
  }) {
    return TripDraft(
      destinations: destinations ?? this.destinations,
      destinationCoordinates:
          destinationCoordinates ?? this.destinationCoordinates,
      tripName: tripName ?? this.tripName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      explorationTime: explorationTime ?? this.explorationTime,
      travelPace: travelPace ?? this.travelPace,
      interests: interests ?? this.interests,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      transportMode: transportMode ?? this.transportMode,
      mustVisitIds: mustVisitIds ?? this.mustVisitIds,
      daySplit: daySplit ?? this.daySplit,
    );
  }
}
