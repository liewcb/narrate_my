import '../../../core/config/itinerary_constants.dart';
import 'schedule_construction_service.dart';

/// Represents a validation issue.
class ValidationIssue {
  final String type;
  final String severity; // 'error' or 'warning'
  final String message;
  final int? dayIndex;
  final String? placeName;

  const ValidationIssue({
    required this.type,
    required this.severity,
    required this.message,
    this.dayIndex,
    this.placeName,
  });
}

/// Result of validation.
class ValidationResult {
  final bool passed;
  final List<ValidationIssue> issues;
  final List<ValidationIssue> warnings;

  const ValidationResult({
    required this.passed,
    required this.issues,
    required this.warnings,
  });
}

/// Pipeline Step 9: Hard-Constraint Validation.
///
/// Checks the scheduled itinerary against hard constraints:
///   1. Daily capacity fits the exploration window
///   2. No time overlaps between consecutive stops
///   3. No duplicate places in a day
///   4. Must-visit places appear somewhere (warning)
///   5. Places are open on the scheduled date
class ValidationService {

  String? validateTripName(String? name) {
    // 1. Presence Check
    if (name == null || name.trim().isEmpty) {
      return 'Trip name cannot be empty.';
    }

    final trimmedName = name.trim();

    // 2. Length Check (Max 50 characters)
    if (trimmedName.length > 50) {
      return 'Trip name must be 50 characters or less.';
    }

    // 3. Format/Pattern Check (Alphanumeric, spaces, hyphens, commas)
    final isValidFormat = RegExp(r'^[a-zA-Z0-9\s\-,]+$').hasMatch(trimmedName);
    if (!isValidFormat) {
      return 'Invalid characters. Use only letters, numbers, spaces, hyphens, or commas.';
    }

    // Passed all checks!
    return null;
  }

  /// Validate the complete itinerary against hard constraints.
  ValidationResult validate({
    required List<ScheduledDay> scheduledDays,
    required List<String> mustVisitIds,
    required String explorationTime,
  }) {
    final issues = <ValidationIssue>[];
    final warnings = <ValidationIssue>[];

    final window = ItineraryConstants.explorationWindows[explorationTime] ??
        ItineraryConstants.explorationWindows['Standard']!;
    final totalWindowMinutes = window.totalMinutes;

    for (final day in scheduledDays) {
      // 1. Check daily capacity
      final totalMinutes =
          day.totalDuration + day.totalTravelTime.toInt();
      if (totalMinutes > totalWindowMinutes) {
        issues.add(ValidationIssue(
          type: 'daily_capacity',
          severity: 'error',
          message: 'Day ${day.dayIndex + 1} exceeds available time',
          dayIndex: day.dayIndex,
        ));
      }

      // 2. Check chronological order (no overlaps)
      for (int i = 0; i < day.stops.length - 1; i++) {
        final current = day.stops[i];
        final next = day.stops[i + 1];

        if (current.endTime.isAfter(next.startTime)) {
          issues.add(ValidationIssue(
            type: 'chronological',
            severity: 'error',
            message: 'Time overlap: ${current.attraction.place.name} '
                'overlaps with ${next.attraction.place.name}',
            dayIndex: day.dayIndex,
            placeName: current.attraction.place.name,
          ));
        }
      }

      // 3. Check duplicate places
      final placeIds = <String>{};
      for (final stop in day.stops) {
        if (placeIds.contains(stop.attraction.place.placeId)) {
          issues.add(ValidationIssue(
            type: 'duplicate',
            severity: 'error',
            message: 'Duplicate place: ${stop.attraction.place.name}',
            dayIndex: day.dayIndex,
            placeName: stop.attraction.place.name,
          ));
        }
        placeIds.add(stop.attraction.place.placeId);
      }

      // 4. Check must-visit fulfillment
      final dayPlaceIds =
          day.stops.map((s) => s.attraction.place.placeId).toList();
      for (final mustId in mustVisitIds) {
        if (mustId.isNotEmpty && !dayPlaceIds.contains(mustId)) {
          warnings.add(ValidationIssue(
            type: 'must_visit',
            severity: 'warning',
            message: 'Must-visit attraction not found in itinerary',
            dayIndex: day.dayIndex,
          ));
        }
      }

      // 5. Check opening hours (simplified — assumes isOpenOnDay implemented)
      for (final stop in day.stops) {
        final openingHours = stop.attraction.place.openingHours;
        if (openingHours != null) {
          final isOpen = openingHours.isOpenOnDay(day.date.weekday);
          if (!isOpen) {
            issues.add(ValidationIssue(
              type: 'opening_hours',
              severity: 'error',
              message: '${stop.attraction.place.name} is not open on ${day.date}',
              dayIndex: day.dayIndex,
              placeName: stop.attraction.place.name,
            ));
          }
        }
      }
    }

    return ValidationResult(
      passed: issues.isEmpty,
      issues: issues,
      warnings: warnings,
    );
  }
}
