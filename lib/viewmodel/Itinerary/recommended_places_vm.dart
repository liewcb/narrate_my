// lib/viewmodel/Itinerary/recommended_places_vm.dart
//
// ViewModel for the day-scoped "Recommended Places" flow.
//
// Scope is STRICTLY the currently selected day:
//   - Recommendations are retrieved once (deterministic retrieval + filter +
//     rank via CustomPlaceService.recommendForDay) and cached, so switching
//     between the Attractions / Restaurants tabs never re-hits the network.
//   - Selecting a place runs ONE compact DeepSeek insertion request (3s hard
//     timeout) with a deterministic fallback, then Dart constructs the exact
//     schedule and hard-validates it (CustomPlaceService.planInsertion).
//   - Nothing is written to the database and no other day is touched — the
//     validated proposed day is returned to the host editor's working state.

import 'package:flutter/foundation.dart';

import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/place.dart';

/// Recommendation category tabs shown by the UI.
enum RecommendationCategory { attractions, restaurants }

/// ViewModel driving "Recommended Places" for a single itinerary day.
class RecommendedPlacesVM extends ChangeNotifier {
  /// 1-based day number (UI labels only).
  final int dayNumber;
  final DateTime dayDate;

  /// The selected day's CURRENT working stops (from the editor's temporary
  /// state — never the database).
  final List<ExistingStopContext> existingStops;

  /// Every place id already used across the whole itinerary (duplicate guard).
  final Set<String> usedPlaceIds;

  final List<String> interests;
  final String transportMode;
  final String explorationTime;
  final String travelPace;
  final Coordinates? destinationCenter;

  final CustomPlaceService _service;

  /// Hard ceiling for the DeepSeek insertion request (spec: ~3 seconds).
  static const Duration aiTimeout = Duration(seconds: 3);

  RecommendedPlacesVM({
    required this.dayNumber,
    required this.dayDate,
    required this.existingStops,
    required this.usedPlaceIds,
    required this.interests,
    required this.transportMode,
    required this.explorationTime,
    required this.travelPace,
    this.destinationCenter,
    CustomPlaceService? service,
  }) : _service = service ?? CustomPlaceService();

  // ─── Recommendation state ─────────────────────────────────────
  bool isLoadingRecommendations = false;
  String? recommendationsError;
  bool _recommendationsLoaded = false;
  List<NearbyPlaceResult> _attractions = const [];
  List<NearbyPlaceResult> _restaurants = const [];

  List<NearbyPlaceResult> get attractions => _attractions;
  List<NearbyPlaceResult> get restaurants => _restaurants;
  bool get recommendationsLoaded => _recommendationsLoaded;

  /// Returns the cached list for [category] — no network call on tab switch.
  List<NearbyPlaceResult> forCategory(RecommendationCategory category) =>
      category == RecommendationCategory.attractions ? _attractions : _restaurants;

  // ─── Selection + planning state ───────────────────────────────
  Place? _selectedPlace;
  bool isPlanning = false;
  String? planError;
  CustomPlacePlanResult? _planResult;

  Place? get selectedPlace => _selectedPlace;
  CustomPlacePlanResult? get planResult => _planResult;
  bool get hasPlan => _planResult != null;

  /// Loads recommendations once and caches them. Safe to call repeatedly.
  Future<void> loadRecommendations() async {
    if (_recommendationsLoaded || isLoadingRecommendations) return;
    isLoadingRecommendations = true;
    recommendationsError = null;
    notifyListeners();

    try {
      final rec = await _service.recommendForDay(
        dayPlaces: existingStops.map((s) => s.place).toList(),
        interests: interests,
        destinationCenter: destinationCenter ?? _centroidOfStops(),
        usedPlaceIds: usedPlaceIds,
        dayOfWeek: dayDate.weekday,
        transportMode: transportMode,
      );
      _attractions = rec.attractions;
      _restaurants = rec.restaurants;
      _recommendationsLoaded = true;
      if (rec.isEmpty) {
        recommendationsError =
            'No recommended places were found for this day.';
      }
    } catch (e) {
      debugPrint('[RecommendedPlaces] load failed: $e');
      recommendationsError =
          "We couldn't load recommendations right now. Please try again.";
    } finally {
      isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  /// Selects a place and runs the single compact AI insertion request (3s)
  /// with deterministic fallback + hard validation. On success the validated
  /// proposed day is available via [confirmedProposedDay].
  Future<void> selectAndPlan(Place place) async {
    if (isPlanning) return;
    _selectedPlace = place;
    _planResult = null;
    planError = null;
    isPlanning = true;
    notifyListeners();

    try {
      final result = await _service.planInsertion(
        dayIndex: dayNumber - 1, // 0-based for the pipeline
        date: dayDate,
        existingStops: existingStops,
        newPlace: place,
        explorationTime: explorationTime,
        transportMode: transportMode,
        travelPace: travelPace,
        interests: interests,
        tripLocation: destinationCenter ?? _centroidOfStops(),
        aiTimeoutOverride: aiTimeout,
        placeIdContract: true,
        // Re-check whole-itinerary duplicates at commit time (placeId).
        itineraryUsedPlaceIds: usedPlaceIds,
      );
      _planResult = result;
      if (!result.success) {
        planError = result.message ??
            'This place cannot fit into Day $dayNumber.';
      }
    } catch (e) {
      debugPrint('[RecommendedPlaces] planning failed: $e');
      _planResult = null;
      planError = 'This place cannot fit into Day $dayNumber.';
    } finally {
      isPlanning = false;
      notifyListeners();
    }
  }

  /// Clears the current selection so the traveler can pick another place.
  void clearSelection() {
    _selectedPlace = null;
    _planResult = null;
    planError = null;
    notifyListeners();
  }

  /// The validated proposed day, or null when planning failed / is running.
  ScheduledDay? confirmedProposedDay() {
    final plan = _planResult;
    if (plan == null || !plan.success) return null;
    return plan.proposedDay;
  }

  Coordinates? _centroidOfStops() {
    double lat = 0, lng = 0;
    var n = 0;
    for (final s in existingStops) {
      final p = s.place;
      if (p.latitude == 0 && p.longitude == 0) continue;
      lat += p.latitude;
      lng += p.longitude;
      n++;
    }
    if (n == 0) return null;
    return Coordinates(latitude: lat / n, longitude: lng / n);
  }
}
