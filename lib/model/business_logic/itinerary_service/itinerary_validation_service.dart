/// Business logic for itinerary validation.
/// This service contains pure validation logic that can be used
/// by multiple ViewModels or Use Cases.
class ItineraryValidationService {
  /// Maximum allowed trip length (inclusive) in days.
  static const int maxTripDays = 5;

  /// Maximum number of interests a user may select.
  static const int maxInterests = 3;

  // ─── Weather Forecast Limits ───────────────────────────────────────────

  /// Primary forecast (Open-Meteo) covers up to this many days ahead.
  static const int primaryForecastDays = 16;

  /// Fallback forecast (yr.no / MET Norway) covers up to this many days ahead.
  static const int fallbackForecastDays = 9;

  /// Combined limit: the start date must be early enough so that
  /// the entire trip (start → start + maxTripDays - 1) stays within
  /// at least the fallback forecast window.
  ///
  /// Calculation:
  ///   latestStart = today + fallbackForecastDays - maxTripDays
  ///   e.g. today + 9 - 5 = today + 4  → start no later than day 4
  static int get latestStartOffset => fallbackForecastDays - maxTripDays;

  // ─── Trip Name ─────────────────────────────────────────────────────────

  static String? validateTripName(String name) {
    if (name.trim().isEmpty) {
      return 'Give your trip a name.';
    }
    return null;
  }

  // ─── Dates ─────────────────────────────────────────────────────────────

  static String? validateDates(DateTime? start, DateTime? end) {
    if (start == null || end == null) {
      return 'Pick your travel dates.';
    }
    if (end.isBefore(start)) {
      return 'End date must be after the start date.';
    }
    final days = end.difference(start).inDays + 1;
    if (days > maxTripDays) {
      return 'Trips are limited to $maxTripDays days.';
    }
    return null;
  }

  /// Returns the clamped end date if the range exceeds [maxTripDays],
  /// otherwise returns [end] unchanged.
  static DateTime clampEndDate(DateTime start, DateTime end) {
    final days = end.difference(start).inDays + 1;
    if (days > maxTripDays) {
      return start.add(Duration(days: maxTripDays - 1));
    }
    return end;
  }

  // ─── Weather Availability ──────────────────────────────────────────────

  /// How well the selected dates are covered by weather forecast data.
  static WeatherCoverage getWeatherCoverage(DateTime? start, DateTime? end) {
    if (start == null || end == null) return WeatherCoverage.unknown;

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final daysUntilEnd = end.difference(todayOnly).inDays;

    if (daysUntilEnd >= primaryForecastDays) {
      return WeatherCoverage.outOfRange;
    } else if (daysUntilEnd >= fallbackForecastDays) {
      return WeatherCoverage.primaryOnly; // Open-Meteo only, yr.no won't cover
    }
    return WeatherCoverage.full; // Both APIs cover the dates
  }

  /// Warning message shown to user based on weather coverage.
  /// Returns null when coverage is full (no warning needed).
  static String? getWeatherWarning(DateTime? start, DateTime? end) {
    final coverage = getWeatherCoverage(start, end);

    switch (coverage) {
      case WeatherCoverage.outOfRange:
        return 'Selected dates are beyond the $primaryForecastDays-day '
            'weather forecast window. Weather data may be unavailable.';
      case WeatherCoverage.primaryOnly:
        return 'Fallback weather source covers only $fallbackForecastDays days. '
            'Primary source will be used instead.';
      case WeatherCoverage.full:
      case WeatherCoverage.unknown:
        return null;
    }
  }

  /// Earliest possible start date that guarantees the full trip
  /// is covered by the fallback provider (most conservative).
  static DateTime get earliestWeatherSafeStart {
    return DateTime.now().add(Duration(days: latestStartOffset));
  }

  /// Latest possible start date that guarantees the full trip
  /// is covered by the fallback provider.
  static DateTime get latestWeatherSafeStart {
    // If user starts today, end is today + 4.
    // yr.no covers today + 9. So today + 4 is safe.
    // Latest safe start = today + fallbackForecastDays - maxTripDays
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return todayOnly.add(Duration(days: latestStartOffset));
  }

  // ─── Exploration Time ──────────────────────────────────────────────────

  static String? validateExploration(String? exploration) {
    if (exploration == null) {
      return 'Choose how much you want to explore each day.';
    }
    return null;
  }

  // ─── Travel Pace ───────────────────────────────────────────────────────

  static String? validatePace(String? pace) {
    if (pace == null) {
      return 'Select a travel pace.';
    }
    return null;
  }

  // ─── Interests ─────────────────────────────────────────────────────────

  static String? validateInterests(Set<String> interests) {
    if (interests.isEmpty) {
      return 'Pick at least one interest.';
    }
    if (interests.length > maxInterests) {
      return 'You can select up to $maxInterests interests.';
    }
    return null;
  }

  static String? validateTransportation(String? transportation) {
    if (transportation == null) {
      return 'Pick a transportation mode.';
    }
    return null;
  }

  // ─── Validate All ──────────────────────────────────────────────────────

  /// Validate all Step 2 fields.
  /// Returns a map of field → error message (empty map = valid).
  static Map<String, String> validateAll({
    required String tripName,
    required DateTime? startDate,
    required DateTime? endDate,
    required String? exploration,
    required String? pace,
    required Set<String> interests,
    required String? transportation
  }) {
    final errors = <String, String>{};

    _addError(errors, 'tripName', validateTripName(tripName));
    _addError(errors, 'dates', validateDates(startDate, endDate));
    _addError(errors, 'exploration', validateExploration(exploration));
    _addError(errors, 'pace', validatePace(pace));
    _addError(errors, 'interests', validateInterests(interests));
    _addError(errors, 'transportation', validateTransportation(transportation));

    return errors;
  }

  static void _addError(Map<String, String> errors, String key, String? error) {
    if (error != null) {
      errors[key] = error;
    }
  }
}

/// Enum representing how well weather forecast covers the selected dates.
enum WeatherCoverage {
  /// Dates are within both primary and fallback forecast windows.
  full,

  /// Dates are only within the primary (Open-Meteo) forecast window.
  /// Fallback (yr.no) won't cover these dates.
  primaryOnly,

  /// Dates exceed even the primary forecast window.
  outOfRange,

  /// Dates have not been selected yet.
  unknown,
}