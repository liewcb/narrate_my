// lib/viewmodel/ItineraryModel/step2_trip_style_vm.dart
import 'package:flutter/foundation.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/business_logic/itinerary_service/itinerary_validation_service.dart';

/// ViewModel for Step 2 (Trip Style).
class Step2TripStyleVM extends ChangeNotifier {
  final TripDraft _incomingDraft;

  // ─── State ────────────────────────────────────────────────────

  String _tripName = '';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _exploration; // matches validation service & UI
  String? _pace;        // matches validation service & UI
  final Set<String> _interests = {};
  String _notes = '';

  // ─── Constructor ─────────────────────────────────────────────

  Step2TripStyleVM(this._incomingDraft) {
    _tripName = _incomingDraft.tripName;
    _startDate = _incomingDraft.startDate;
    _endDate = _incomingDraft.endDate;
    _exploration = _incomingDraft.explorationTime; // map from draft
    _pace = _incomingDraft.travelPace;             // map from draft
    _interests.clear();
    _interests.addAll(_incomingDraft.interests);
    _notes = _incomingDraft.additionalNotes;
  }

  // ─── Getters ─────────────────────────────────────────────────

  String get tripName => _tripName;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  String? get exploration => _exploration;
  String? get pace => _pace;
  Set<String> get interests => Set.unmodifiable(_interests);
  String get notes => _notes;
  List<String> get destinations => _incomingDraft.destinations;

  int get totalDays {
    if (_startDate == null || _endDate == null) return 1;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  bool get canProceed {
    return _tripName.trim().isNotEmpty &&
        _startDate != null &&
        _endDate != null &&
        _exploration != null &&
        _pace != null &&
        _interests.isNotEmpty;
  }

  Map<String, String> get validationErrors {
    return ItineraryValidationService.validateAll(
      tripName: _tripName,
      startDate: _startDate,
      endDate: _endDate,
      exploration: _exploration,
      pace: _pace,
      interests: _interests,
    );
  }

  // ─── Setters ─────────────────────────────────────────────────

  void setTripName(String value) {
    _tripName = value;
    notifyListeners();
  }

  void setDates({required DateTime start, required DateTime end}) {
    _startDate = start;
    _endDate = end;
    notifyListeners();
  }

  void setExploration(String value) {
    _exploration = value;
    notifyListeners();
  }

  void setPace(String value) {
    _pace = value;
    notifyListeners();
  }

  void toggleInterest(String label) {
    if (_interests.contains(label)) {
      _interests.remove(label);
    } else {
      _interests.add(label);
    }
    notifyListeners();
  }

  void setNotes(String value) {
    _notes = value;
    notifyListeners();
  }

  // ─── Validation ──────────────────────────────────────────────

  Map<String, String> validate() {
    return validationErrors;
  }

  // ─── Build Draft ─────────────────────────────────────────────

  TripDraft buildDraft() {
    final errors = validationErrors;
    if (errors.isNotEmpty) {
      throw StateError(errors.values.first);
    }

    return _incomingDraft.copyWith(
      tripName: _tripName.trim(),
      startDate: _startDate,
      endDate: _endDate,
      explorationTime: _exploration,     // map to correct field
      travelPace: _pace,                // map to correct field
      interests: _interests.toList(),
      additionalNotes: _notes,
    );
  }
}