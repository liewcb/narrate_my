enum ItineraryTemporalStatus {
  past,
  ongoing,
  upcoming;

  bool get isReadOnly => this == past;
  // Editable for both ongoing and upcoming
  bool get isEditable => this == ongoing || this == upcoming;
  bool get allowsProgressRecording => this == ongoing;
  bool get isUpcoming => this == upcoming;
  bool get isPast => this == past;
  bool get isOngoing => this == ongoing;
}

/// Resolves the temporal status from itinerary dates, comparing only the
/// calendar day (year-month-day) so stored time-of-day never affects
/// whether a trip is upcoming / ongoing / past.
class ItineraryStatusResolver {
  ItineraryStatusResolver._();

  static ItineraryTemporalStatus resolve({
    required DateTime startDate,
    required DateTime endDate,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    // Normalise to calendar-day boundaries so time-of-day stored in
    // startDate / endDate never causes misclassification.
    final today = DateTime(current.year, current.month, current.day);
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);

    if (today.isBefore(startDay)) {
      return ItineraryTemporalStatus.upcoming;
    }

    if (today.isAfter(endDay)) {
      return ItineraryTemporalStatus.past;
    }

    return ItineraryTemporalStatus.ongoing;
  }
}