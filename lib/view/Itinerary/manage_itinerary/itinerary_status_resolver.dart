// lib/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart
//
// Determines the temporal status of an itinerary (Past / Ongoing / Upcoming)
// from its start and end dates, without relying on a stored status field.

/// The three temporal states an itinerary can be in.
enum ItineraryTemporalStatus {
  past,
  ongoing,
  upcoming;

  bool get isReadOnly => this == past;
  bool get isEditable => this == ongoing;
  bool get allowsProgressRecording => this == ongoing;
  bool get isUpcoming => this == upcoming;
  bool get isPast => this == past;
  bool get isOngoing => this == ongoing;
}

/// Resolves the temporal status from itinerary dates and the current time.
class ItineraryStatusResolver {
  ItineraryStatusResolver._();

  /// Determine the [ItineraryTemporalStatus] for the given dates.
  static ItineraryTemporalStatus resolve({
    required DateTime startDate,
    required DateTime endDate,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    if (current.isBefore(startDate) &&
        !_isSameDay(current, startDate)) {
      return ItineraryTemporalStatus.upcoming;
    }

    if (current.isAfter(endDate) && !_isSameDay(current, endDate)) {
      return ItineraryTemporalStatus.past;
    }

    // current is within [startDate, endDate] (inclusive of both boundaries).
    return ItineraryTemporalStatus.ongoing;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}