/// Business logic for itinerary validation.
/// This service contains pure validation logic that can be used
/// by multiple ViewModels or Use Cases.
class ItineraryValidationService {
  /// Validate trip name
  static String? validateTripName(String name) {
    if (name.trim().isEmpty) {
      return 'Give your trip a name.';
    }
    return null;
  }

  /// Validate travel dates
  static String? validateDates(DateTime? start, DateTime? end) {
    if (start == null || end == null) {
      return 'Pick your travel dates.';
    }
    if (end.isBefore(start)) {
      return 'End date must be after the start date.';
    }
    final days = end.difference(start).inDays + 1;
    if (days > 30) {
      return 'Trips are limited to 30 days.';
    }
    return null;
  }

  /// Validate exploration time
  static String? validateExploration(String? exploration) {
    if (exploration == null) {
      return 'Choose how much you want to explore each day.';
    }
    return null;
  }

  /// Validate travel pace
  static String? validatePace(String? pace) {
    if (pace == null) {
      return 'Select a travel pace.';
    }
    return null;
  }

  /// Validate interests
  static String? validateInterests(Set<String> interests) {
    if (interests.isEmpty) {
      return 'Pick at least one interest.';
    }
    return null;
  }

  /// Validate all Step 2 fields
  static Map<String, String> validateAll({
    required String tripName,
    required DateTime? startDate,
    required DateTime? endDate,
    required String? exploration,
    required String? pace,
    required Set<String> interests,
  }) {
    final errors = <String, String>{};

    _addError(errors, 'tripName', validateTripName(tripName));
    _addError(errors, 'dates', validateDates(startDate, endDate));
    _addError(errors, 'exploration', validateExploration(exploration));
    _addError(errors, 'pace', validatePace(pace));
    _addError(errors, 'interests', validateInterests(interests));

    return errors;
  }

  static void _addError(Map<String, String> errors, String key, String? error) {
    if (error != null) {
      errors[key] = error;
    }
  }
}