// lib/viewmodel/Itinerary/add_place_to_day_vm.dart
//
// ViewModel for the "Add Place to Day" flow inside ManageEditItineraryScreen.
//
// Responsibilities:
//   - Hold the specific day context (day number, date, existing stops with
//     their ACTUAL scheduled times, exploration window, transport mode).
//   - Search Google Places by free-text query.
//   - Validate a selected candidate against the day via AddPlaceToDayService.
//   - Expose the structured AddPlaceValidationResult so the UI never parses
//     raw strings to determine success.
//   - Re-validate before insertion (stale-validation guard).
//   - On confirmation, produce the WizardPlace + insertion index so the
//     screen can update its _editedDays plan state.

import 'package:flutter/foundation.dart';

import '../../core/config/itinerary_constants.dart';
import '../../model/business_logic/itinerary_service/add_place_to_day_service.dart';
import '../../model/entities/place.dart';

/// ViewModel for adding a place to a single day of the current Plan State.
class AddPlaceToDayVM extends ChangeNotifier {
  final int dayIndex; // 1-based day number (for UI labels)
  final DateTime dayDate;
  final List<AddPlaceExistingStop> existingDayStops;
  final Set<String> allDayPlaceIds;
  final String transportMode;
  final AddPlaceToDayService _service;

  // ─── Search state ───────────────────────────────────────────
  String _query = '';
  List<Place> _results = [];
  bool _isSearching = false;
  String? _searchError;

  // ─── Selection + validation ─────────────────────────────────
  Place? _selectedPlace;
  AddPlaceValidationResult? _validation;
  bool _isValidating = false;

  // ─── Confirm ────────────────────────────────────────────────
  bool _confirmed = false;

  AddPlaceToDayVM({
    required this.dayIndex,
    required this.dayDate,
    required this.existingDayStops,
    this.allDayPlaceIds = const {},
    this.transportMode = 'walking',
    AddPlaceToDayService? service,
  }) : _service = service ?? AddPlaceToDayService();

  // ─── Getters ────────────────────────────────────────────────

  String get query => _query;
  set query(String value) => _query = value;

  List<Place> get results => List.unmodifiable(_results);
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  Place? get selectedPlace => _selectedPlace;
  AddPlaceValidationResult? get validation => _validation;
  bool get isValidating => _isValidating;
  bool get confirmed => _confirmed;

  /// Whether a valid insertion plan exists and the traveler can confirm.
  bool get canAdd =>
      _selectedPlace != null &&
      _validation != null &&
      _validation!.isValid &&
      !_isValidating;

  /// The chosen insertion index (0-based) within the day's stops.
  int get insertionIndex => _validation?.insertionIndex ?? 0;

  // ─── Actions ────────────────────────────────────────────────

  /// Search Google Places by the current query.
  Future<void> search() async {
    if (_query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    _results = [];
    _selectedPlace = null;
    _validation = null;
    notifyListeners();

    try {
      final locationBias = existingDayStops.isNotEmpty
          ? existingDayStops.first.coordinates
          : null;
      _results = await _service.searchPlaces(_query, locationBias: locationBias);
      if (_results.isEmpty) {
        _searchError = 'No places found. Try a different search.';
      }
    } catch (e) {
      _searchError = 'Unable to search for places. Please try again.';
      debugPrint('[AddPlaceToDay] Search error: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Validate a selected candidate against the specific day context.
  Future<void> validateCandidate(Place place) async {
    _selectedPlace = place;
    _validation = null;
    _isValidating = true;
    _confirmed = false;
    notifyListeners();

    try {
      _validation = await _service.evaluateInsertion(
        context: AddPlaceDayContext(
          dayNumber: dayIndex,
          date: dayDate,
          existingStops: existingDayStops,
          allDayPlaceIds: allDayPlaceIds,
          window: _explorationWindow(),
          transportMode: transportMode,
        ),
        candidate: place,
      );
    } catch (e) {
      debugPrint('[AddPlaceToDay] Validation error: $e');
      _validation = const AddPlaceValidationResult(
        isValid: false,
        errorMessage: 'Unable to validate this place. Please try again.',
      );
    } finally {
      _isValidating = false;
      notifyListeners();
    }
  }

  /// Defensive re-validation immediately before insertion (FAIL 10).
  ///
  /// The traveler may have left the sheet open while the itinerary changed.
  /// Re-run the deterministic validation against the CURRENT day context so
  /// a stale result can never be inserted. Returns `true` only when the
  /// candidate is still valid and can be inserted.
  Future<bool> revalidateBeforeInsert() async {
    final selected = _selectedPlace;
    if (selected == null) return false;

    final latest = await _service.evaluateInsertion(
      context: AddPlaceDayContext(
        dayNumber: dayIndex,
        date: dayDate,
        existingStops: existingDayStops,
        allDayPlaceIds: allDayPlaceIds,
        window: _explorationWindow(),
        transportMode: transportMode,
      ),
      candidate: selected,
    );

    _validation = latest;
    if (!latest.isValid) {
      _confirmed = false;
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Confirm the validated insertion.
  void confirm() {
    if (!canAdd) return;
    _confirmed = true;
    notifyListeners();
  }

  ExplorationWindow _explorationWindow() {
    // Default to Standard; the caller may override with the itinerary's value.
    return ItineraryConstants.explorationWindows['Standard']!;
  }
}
