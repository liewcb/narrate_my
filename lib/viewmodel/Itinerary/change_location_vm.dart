// lib/viewmodel/Itinerary/change_location_vm.dart
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

  List<ChangeLocationRecommendation> get recommendations =>
      _recommendationResult?.recommendations ?? const [];

  bool get isLoadingRecommendations => _isLoadingRecommendations;

  String? get problemMessage =>
      _recommendationResult != null && !_recommendationResult!.isSuccessful
          ? _recommendationResult!.message
          : null;

  bool get usedFallback =>
      _recommendationResult?.outcome == ChangeLocationOutcome.fallbackSuccess;

  // ─── Actions ────────────────────────────────────────────────

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

  // ✅ UPDATED: Accepts the AI's suggested duration
  Future<ChangeLocationResult> confirmReplacement(Place place, {int? suggestedDuration}) {
    return _service.replaceItineraryStop(
      itineraryId: stop.itineraryId,
      stopId: stop.stopId,
      newPlace: place, // ⬅️ CHANGED THIS LINE
      newDurationMinutes: suggestedDuration ?? place.visitDurationMinutes ?? stop.durationMinutes,
    );
  }
}