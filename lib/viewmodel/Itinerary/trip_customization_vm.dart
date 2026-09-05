// lib/viewmodel/Itinerary/trip_customization_vm.dart
//
// ViewModel for Step 2 (Trip Style) of the trip wizard.
//
// Holds the immutable [TripDraft] locally. No external manager – the
// draft is passed explicitly from the previous screen and later forwarded
// to the next step.

import 'package:flutter/foundation.dart';

import '../../core/config/itinerary_constants.dart';
import '../../model/business_logic/itinerary_service/itinerary_validation_service.dart';
import '../../model/entities/trip_draft.dart';

/// ViewModel for Step 2: Trip Customization.
class Step2TripStyleVM extends ChangeNotifier {
  // ─── Limits (single source of truth for this step) ─────────
  static const int maxTripDaysLimit = 3;
  static const int maxInterestsLimit = 2;
  final int maxTripDays = maxTripDaysLimit;
  final int maxInterests = maxInterestsLimit;

  TripDraft _draft;

  /// Transportation chosen by the user in this session. Null until the
  /// traveler explicitly picks a mode (the draft's storage default is not
  /// treated as a choice, preserving the "must select" rule).
  String? _transportationSelection;

  // ─── Constructor ────────────────────────────────────────────
  Step2TripStyleVM({required TripDraft initialDraft})
      : _draft = initialDraft;

  // ─── Getters ────────────────────────────────────────────────
  TripDraft get draft => _draft;
  String get tripName => _draft.tripName;
  DateTime? get startDate => _draft.startDate;
  DateTime? get endDate => _draft.endDate;
  String? get travelType => _draft.travelType;
  String? get exploration => _draft.exploration;
  String? get pace => _draft.pace;

  /// Selected interests as an unmodifiable [Set].
  Set<String> get interests => Set.unmodifiable(_draft.interests);

  /// Null until the traveler explicitly selects a transportation mode.
  String? get transportation => _transportationSelection;

  List<String> get destinations =>
      _draft.destinations.map((d) => d.destinationName).toList();

  int get totalDays {
    if (startDate == null || endDate == null) return 0;
    return endDate!.difference(startDate!).inDays + 1;
  }

  // ─── Weather (existing ItineraryValidationService logic) ────
  WeatherCoverage get weatherCoverage =>
      ItineraryValidationService.getWeatherCoverage(
          _draft.startDate, _draft.endDate);

  String? get weatherWarning => ItineraryValidationService.getWeatherWarning(
      _draft.startDate, _draft.endDate);

  // ─── User actions (called by the View) ─────────────────────

  void setTripName(String name) {
    _draft = _draft.copyWith(tripName: name);
    notifyListeners();
  }

  /// Sets the travel dates. Enforces [maxTripDays] (3): an end date beyond
  /// start + maxTripDays - 1 is clamped. Returns true when clamping was
  /// applied (the picker should already prevent this).
  bool setDates({required DateTime start, required DateTime end}) {
    final latest = latestPossibleEndDate(fromStart: start);
    final clampedEnd = end.isAfter(latest) ? latest : end;
    final wasClamped = clampedEnd != end;
    _draft = _draft.copyWith(startDate: start, endDate: clampedEnd);
    notifyListeners();
    return wasClamped;
  }

  void setTravelType(String type) {
    _draft = _draft.copyWith(travelType: type);
    notifyListeners();
  }

  void setExploration(String value) {
    _draft = _draft.copyWith(exploration: value);
    notifyListeners();
  }

  void setPace(String value) {
    _draft = _draft.copyWith(pace: value);
    notifyListeners();
  }

  /// Toggles an interest, enforcing [maxInterests] (2).
  void toggleInterest(String interest) {
    final updated = Set<String>.from(_draft.interests);
    if (updated.contains(interest)) {
      updated.remove(interest);
    } else {
      if (updated.length >= maxInterests) return;
      updated.add(interest);
    }
    _draft = _draft.copyWith(interests: updated);
    notifyListeners();
  }

  void setTransportation(String value) {
    _transportationSelection = value;
    _draft = _draft.copyWith(transportation: value);
    notifyListeners();
  }

  // ─── Date helpers ──────────────────────────────────────────

  /// Latest selectable end date: the earlier of
  ///   • start + (maxTripDays - 1)  — the 3-day trip limit
  ///   • the weather-forecast window from today
  DateTime latestPossibleEndDate({DateTime? fromStart}) {
    final start = fromStart ?? startDate;
    final tripLimit = start == null
        ? null
        : start.add(Duration(days: maxTripDays - 1));

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final weatherLimit = todayOnly.add(Duration(
      days: ItineraryValidationService.primaryForecastDays - 1,
    ));

    if (tripLimit == null) return weatherLimit;
    return tripLimit.isBefore(weatherLimit) ? tripLimit : weatherLimit;
  }

  // ─── Validation ────────────────────────────────────────────

  bool get canProceed {
    return startDate != null &&
        endDate != null &&
        travelType != null &&
        tripName.trim().isNotEmpty &&
        exploration != null &&
        pace != null &&
        interests.isNotEmpty &&
        transportation != null;
  }

  Map<String, String> validate() {
    final errors = <String, String>{};
    if (startDate == null || endDate == null) {
      errors['dates'] = 'Pick your travel dates.';
    } else if (totalDays > maxTripDays) {
      errors['dates'] = 'Trips are limited to $maxTripDays days.';
    }
    if (travelType == null) {
      errors['travelType'] = 'Select a travel type.';
    }
    if (tripName.trim().isEmpty) {
      errors['tripName'] = 'Give your trip a name.';
    }
    if (exploration == null) {
      errors['exploration'] = 'Select an exploration time.';
    }
    if (pace == null) {
      errors['pace'] = 'Select a travel pace.';
    }
    if (interests.isEmpty) {
      errors['interests'] = 'Select at least one interest.';
    }
    if (transportation == null) {
      errors['transportation'] = 'Select a transportation mode.';
    }
    return errors;
  }

  TripDraft buildDraft() => _draft;
}