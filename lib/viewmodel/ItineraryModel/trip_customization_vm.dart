import 'package:flutter/foundation.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/business_logic/itinerary_service/itinerary_validation_service.dart';

/// ViewModel for Step 2 (Trip Style).
class Step2TripStyleVM extends ChangeNotifier {
  final TripDraft _incomingDraft;

  Step2TripStyleVM(this._incomingDraft);

  String _tripName = '';
  String? _travelType;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _exploration;
  String? _pace;
  String? _transportation;
  final Set<String> _interests = {};

  // ─── Getters ──────────────────────────────────────────────────────

  String get tripName => _tripName;
  String? get travelType => _travelType;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  String? get exploration => _exploration;
  String? get pace => _pace;
  String? get transportation => _transportation;
  Set<String> get interests => Set.unmodifiable(_interests);

  // ✅ FIX: _draft → _incomingDraft
  List<String> get destinations => _incomingDraft.destinations;

  int get totalDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  /// Weather coverage status for the selected dates.
  WeatherCoverage get weatherCoverage =>
      ItineraryValidationService.getWeatherCoverage(_startDate, _endDate);

  /// Warning message for weather (null = no warning).
  String? get weatherWarning =>
      ItineraryValidationService.getWeatherWarning(_startDate, _endDate);

  bool get canProceed {
    return _tripName.trim().isNotEmpty &&
        _travelType != null &&
        _startDate != null &&
        _endDate != null &&
        _exploration != null &&
        _pace != null &&
        _interests.isNotEmpty &&
        _transportation != null;
  }

  // ─── Mutators ──────────────────────────────────────────────────────

  void setTripName(String value) {
    _tripName = value;
    notifyListeners();
  }

  void setTravelType(String value) {
    _travelType = value;
    notifyListeners();
  }

  /// Set dates with business-logic clamping.
  /// Returns true if dates were clamped (for snackbar in UI).
  bool setDates({required DateTime start, required DateTime end}) {
    final clampedEnd = ItineraryValidationService.clampEndDate(start, end);
    final wasClamped = clampedEnd != end;

    _startDate = start;
    _endDate = clampedEnd;
    notifyListeners();

    return wasClamped;
  }

  /// Check if a proposed end date would be clamped.
  bool wouldClamp(DateTime start, DateTime end) {
    return ItineraryValidationService.clampEndDate(start, end) != end;
  }

  /// Latest end date the user can pick, considering:
  /// 1. Weather forecast window (16 days from today)
  /// 2. Max trip length (5 days from start)
  ///
  /// Used as `lastDate` in the date picker.
  DateTime latestPossibleEndDate({DateTime? fromStart}) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    // Constraint 1: Weather forecast limit
    final weatherLimit = todayOnly.add(
      Duration(days: ItineraryValidationService.primaryForecastDays - 1),
    );

    // Constraint 2: If start is known, end can't exceed start + maxTripDays
    if (fromStart != null) {
      final tripLimit = fromStart.add(
        Duration(days: ItineraryValidationService.maxTripDays - 1),
      );
      // Return whichever is earlier
      return tripLimit.isBefore(weatherLimit) ? tripLimit : weatherLimit;
    }

    return weatherLimit;
  }

  /// Latest start date the user can pick so that
  /// the full trip (start + maxTripDays) stays within forecast.
  DateTime get latestPossibleStartDate {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return todayOnly.add(
      Duration(
        days: ItineraryValidationService.primaryForecastDays
            - ItineraryValidationService.maxTripDays,
      ),
    );
  }

  void setExploration(String value) {
    _exploration = value;
    notifyListeners();
  }

  void setPace(String value) {
    _pace = value;
    notifyListeners();
  }

  void setTransportation(String value) {
    _transportation = value;
    notifyListeners();
  }

  void toggleInterest(String interest) {
    if (_interests.contains(interest)) {
      _interests.remove(interest);
    } else {
      if (_interests.length < ItineraryValidationService.maxInterests) {
        _interests.add(interest);
      }
    }
    notifyListeners();
  }

  // ─── Validation ───────────────────────────────────────────────────

  Map<String, String> validate() {
    final errors = ItineraryValidationService.validateAll(
      tripName: _tripName,
      startDate: _startDate,
      endDate: _endDate,
      exploration: _exploration,
      pace: _pace,
      interests: _interests,
      transportation: _transportation
    );

    return errors;
  }

  // ─── Build Draft ─────────────────────────────────────────────

  TripDraft buildDraft() {
    final errors = validate();
    if (errors.isNotEmpty) {
      throw StateError(errors.values.first);
    }

    return _incomingDraft.copyWith(
      title: _tripName.trim(),
      startDate: _startDate,
      endDate: _endDate,
      explorationTime: _exploration,
      travelPace: _pace,
      interests: _interests.toList(),
      transportation: _transportation,
      travelType: _travelType,
    );
  }
}