import 'dart:math';
import 'destination.dart';
import 'coordinates.dart';

/// Validated must-visit metadata preserved across the wizard.
///
/// Keyed by the stable Google `place_id` so the AI generation context and the
/// saved `itinerary_must_visits` rows receive the real place identity (never
/// only a name) together with its destination association and source.
class MustVisitPlaceInfo {
  final String placeId;
  final String placeName;
  final String? destinationId;
  final String source; // 'BOOKMARK' | 'GOOGLE_SEARCH'
  final double? latitude;
  final double? longitude;

  const MustVisitPlaceInfo({
    required this.placeId,
    required this.placeName,
    this.destinationId,
    this.source = 'GOOGLE_SEARCH',
    this.latitude,
    this.longitude,
  });
}

/// Domain model for the trip-building wizard.
///
/// This is the single source of truth for all user inputs across the wizard.
/// It is persisted via the DraftRepository using the TripDraftDto for JSON.
class TripDraft {
  // ─── Step 1: Destinations ────────────────────────────────
  final List<Destination> destinations;

  // ─── Step 2: Trip Style & Preferences ────────────────────
  final String tripName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? exploration;      // 'Standard', 'Relaxed', 'Intense'
  final String? pace;             // 'Slow', 'Standard', 'Fast'
  final Set<String> interests;    // e.g. {'History & Culture', 'Nature & Outdoors'}
  final String transportation;    // e.g. 'walking', 'driving', 'transit'
  final String? travelType;       // 'Solo', 'Couple', 'Family', 'Friends'
  final String additionalNotes;

  // ─── Step 3: Must-visit places ───────────────────────────
  final List<String> bookmarkedPlaceIds; // from DB (public.bookmarks)
  final List<String> mustVisitPlaceIds;  // selected by user in Step 3

  /// Validated must-visit metadata keyed by stable place_id (place name,
  /// destination association, source, coordinates).
  final Map<String, MustVisitPlaceInfo> mustVisitPlaceInfo;

  // ─── Step 4: Day allocations ─────────────────────────────
  final Map<String, int> daySplit; // destination name -> days allocated

  // ─── Calculated / meta ────────────────────────────────────
  /// Per-destination coordinates (resolved from the DB in Step 1 or
  /// geocoded in Step 5). Keyed by destination NAME.
  final Map<String, Coordinates> destinationCoordinates;

  /// Custom/primary trip location overriding the destination default.
  final Coordinates? tripLocation;

  // ─── Constructor ──────────────────────────────────────────
  const TripDraft({
    this.destinations = const [],
    this.tripName = '',
    this.startDate,
    this.endDate,
    this.exploration,
    this.pace,
    this.interests = const {},
    this.transportation = 'walking',
    this.travelType,
    this.additionalNotes = '',
    this.bookmarkedPlaceIds = const [],
    this.mustVisitPlaceIds = const [],
    this.mustVisitPlaceInfo = const {},
    this.daySplit = const {},
    this.destinationCoordinates = const {},
    this.tripLocation,
  });

  // ─── Computed getters ─────────────────────────────────────

  /// Total trip duration in days (defaults to 1 if dates unset).
  int get totalDays {
    if (startDate == null || endDate == null) return 1;
    final diff = endDate!.difference(startDate!).inDays + 1;
    return max(1, diff);
  }

  /// Primary target coordinates (custom trip location, else the first
  /// destination's latitude/longitude, else null).
  Coordinates? get primaryCoordinates {
    if (tripLocation != null) return tripLocation;
    final first = destinations.firstOrNull;
    if (first == null) return null;
    if (first.latitude != null && first.longitude != null) {
      return Coordinates(
        latitude: first.latitude!,
        longitude: first.longitude!,
      );
    }
    return null;
  }

  /// List of destination names (for UI/pipeline convenience).
  List<String> get destinationNames =>
      destinations.map((d) => d.destinationName).toList();

  /// Validates if all required wizard inputs are present.
  bool get isReadyForGeneration {
    return destinations.isNotEmpty &&
        tripName.trim().isNotEmpty &&
        startDate != null &&
        endDate != null &&
        exploration != null &&
        pace != null &&
        interests.isNotEmpty;
  }

  // ─── Immutable copy ───────────────────────────────────────

  TripDraft copyWith({
    List<Destination>? destinations,
    String? tripName,
    DateTime? startDate,
    DateTime? endDate,
    String? exploration,
    String? pace,
    Set<String>? interests,
    String? transportation,
    String? travelType,
    String? additionalNotes,
    List<String>? bookmarkedPlaceIds,
    List<String>? mustVisitPlaceIds,
    Map<String, MustVisitPlaceInfo>? mustVisitPlaceInfo,
    Map<String, int>? daySplit,
    Map<String, Coordinates>? destinationCoordinates,
    Coordinates? tripLocation,
  }) {
    return TripDraft(
      destinations: destinations ?? this.destinations,
      tripName: tripName ?? this.tripName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      exploration: exploration ?? this.exploration,
      pace: pace ?? this.pace,
      interests: interests ?? this.interests,
      transportation: transportation ?? this.transportation,
      travelType: travelType ?? this.travelType,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      bookmarkedPlaceIds: bookmarkedPlaceIds ?? this.bookmarkedPlaceIds,
      mustVisitPlaceIds: mustVisitPlaceIds ?? this.mustVisitPlaceIds,
      mustVisitPlaceInfo: mustVisitPlaceInfo ?? this.mustVisitPlaceInfo,
      daySplit: daySplit ?? this.daySplit,
      destinationCoordinates:
          destinationCoordinates ?? this.destinationCoordinates,
      tripLocation: tripLocation ?? this.tripLocation,
    );
  }

  // ─── Empty draft factory ──────────────────────────────────

  static TripDraft empty() => const TripDraft();
}

// ─── Extension for firstOrNull on List ─────────────────────
extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
