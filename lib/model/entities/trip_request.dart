// lib/model/entities/trip_request.dart
import 'coordinates.dart';

class TripRequest {
  // ==================== STEP 1: DESTINATIONS ====================
  final List<String> destinations;
  final Map<String, Coordinates> destinationCoordinates; // name → coords

  // ==================== STEP 2: TRIP DETAILS ====================
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final String explorationTime;
  final String travelPace;
  final List<String> interests;
  final String additionalNotes;
  final String transportMode;

  // ==================== STEP 3: MUST-GO ATTRACTIONS ====================
  final List<String> mustVisitIds;

  // ==================== STEP 4: DAY ALLOCATION ====================
  final Map<String, int> daySplit; // destination name → allocated days

  // ==================== ADDITIONAL (optional) ====================
  final Coordinates? tripLocation;

  TripRequest({
    required this.destinations,
    this.destinationCoordinates = const {},
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.explorationTime,
    required this.travelPace,
    required this.interests,
    required this.additionalNotes,
    required this.mustVisitIds,
    this.daySplit = const {},
    this.tripLocation,
    this.transportMode = 'walking',
  });

  /// Total number of travel days
  int get duration => endDate.difference(startDate).inDays + 1;

  TripRequest copyWith({
    List<String>? destinations,
    Map<String, Coordinates>? destinationCoordinates,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? explorationTime,
    String? travelPace,
    List<String>? interests,
    String? additionalNotes,
    List<String>? mustVisitIds,
    Map<String, int>? daySplit,
    Coordinates? tripLocation,
    String? transportMode,
  }) {
    return TripRequest(
      destinations: destinations ?? this.destinations,
      destinationCoordinates:
          destinationCoordinates ?? this.destinationCoordinates,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      explorationTime: explorationTime ?? this.explorationTime,
      travelPace: travelPace ?? this.travelPace,
      interests: interests ?? this.interests,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      mustVisitIds: mustVisitIds ?? this.mustVisitIds,
      daySplit: daySplit ?? this.daySplit,
      tripLocation: tripLocation ?? this.tripLocation,
      transportMode: transportMode ?? this.transportMode,
    );
  }
}