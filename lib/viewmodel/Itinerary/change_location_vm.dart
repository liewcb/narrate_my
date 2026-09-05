// lib/viewmodel/Itinerary/change_location_vm.dart
//
// ViewModel for the "Change Location" workflow of a single itinerary stop.
//
// Thin bridge between the Edit Stop UI and [ChangeLocationService]:
//   1. loadRecommendations() → AI-ranked, Dart-filtered replacement
//      candidates (editability is validated FIRST — no AI for locked stops).
//   2. confirmReplacement() → final validation + replacement + schedule
//      recalculation + persistence via the same service.
//
// Every user-facing message comes from the service's structured result
// types — raw exceptions never reach the UI.

import 'package:flutter/foundation.dart';

import '../../model/business_logic/itinerary_service/change_location_service.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';

class ChangeLocationViewModel extends ChangeNotifier {
  final ChangeLocationService _service = ChangeLocationService();

  final ItineraryStop stop;

  ChangeLocationRecommendationResult? _recommendationResult;
  bool _isLoadingRecommendations = false;

  ChangeLocationViewModel({required this.stop});

  // ─── State ──────────────────────────────────────────────────

  ChangeLocationRecommendationResult? get recommendationResult =>
      _recommendationResult;

  /// AI-ranked + Dart-filtered recommendations (empty until loaded).
  List<ChangeLocationRecommendation> get recommendations =>
      _recommendationResult?.recommendations ?? const [];

  /// True while recommendations are being generated (bounded by the
  /// service's 10-second hard budget).
  bool get isLoadingRecommendations => _isLoadingRecommendations;

  /// Traveler-facing Problem message when the stop cannot be changed or
  /// recommendations are unavailable; null otherwise.
  String? get problemMessage =>
      _recommendationResult != null && !_recommendationResult!.isSuccessful
          ? _recommendationResult!.message
          : null;

  /// Whether the recommendation flow degraded to deterministic ranking.
  bool get usedFallback =>
      _recommendationResult?.outcome == ChangeLocationOutcome.fallbackSuccess;

  // ─── Actions ────────────────────────────────────────────────

  /// Loads AI replacement recommendations for this stop. The service first
  /// validates editability (date AND time) and returns a Problem result —
  /// without calling the AI — when the stop is locked.
  Future<void> loadRecommendations() async {
    if (_isLoadingRecommendations) return;
    _isLoadingRecommendations = true;
    notifyListeners();
    try {
      _recommendationResult = await _service.getReplacementRecommendations(
        itineraryId: stop.itineraryId,
        stopId: stop.stopId,
      );
    } finally {
      _isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  /// Loads AI replacement recommendations for the PREVIEW editor
  /// (EditItineraryScreen): candidates are hard-filtered against the
  /// in-memory scheduled place IDs of the temporary itinerary instead of
  /// the database. Same rules, same AI ranking, same 10-second budget.
  Future<void> loadPreviewRecommendations({
    required Set<String> scheduledPlaceIds,
    required DateTime tripDate,
    required int visitDurationMinutes,
    List<String> interests = const [],
    String explorationTime = 'Standard',
  }) async {
    if (_isLoadingRecommendations) return;
    _isLoadingRecommendations = true;
    notifyListeners();
    try {
      _recommendationResult =
          await _service.getPreviewReplacementRecommendations(
        currentPlace: stop.place ??
            Place.empty(stop.placeId),
        tripDate: tripDate,
        visitDurationMinutes: visitDurationMinutes,
        scheduledPlaceIds: scheduledPlaceIds,
        interests: interests,
        explorationTime: explorationTime,
      );
    } finally {
      _isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  /// Performs the final validation + replacement + recalculation + save
  /// for the traveler-confirmed place. The original stop stays unchanged
  /// until this succeeds.
  Future<ChangeLocationResult> confirmReplacement(Place place) {
    return _service.replaceItineraryStop(
      itineraryId: stop.itineraryId,
      stopId: stop.stopId,
      newPlaceId: place.placeId,
    );
  }
}
