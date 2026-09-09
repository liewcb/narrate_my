// lib/viewmodel/Itinerary/change_location_vm.dart
import 'package:flutter/foundation.dart';
import '../../core/services/database_manager.dart';
import '../../model/repositories/interfaces/bookmark/bookmark_repository.dart';

import '../../model/business_logic/itinerary_service/change_location_service.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';

class ChangeLocationViewModel extends ChangeNotifier {
  final ChangeLocationService _service = ChangeLocationService();

  final ItineraryStop stop;

  ChangeLocationRecommendationResult? _recommendationResult;
  bool _isLoadingRecommendations = false;

  final BookmarkRepository _bookmarkRepository;
  List<Place> bookmarks = [];
  bool isLoadingBookmarks = false;
  String? bookmarksError;
  bool _disposed = false;

  ChangeLocationViewModel({required this.stop, BookmarkRepository? bookmarkRepository})
      : _bookmarkRepository = bookmarkRepository ?? DatabaseManager().bookmarkRepository;

  Future<void> loadBookmarks([String userId = '']) async {
    if (isLoadingBookmarks) return;
    isLoadingBookmarks = true;
    bookmarksError = null;
    notifyListeners();
    try {
      final effectiveUserId = userId.isNotEmpty ? userId : _bookmarkRepository.currentUserId ?? '';
      final entries = effectiveUserId.isEmpty ? <Place>[] :
          (await _bookmarkRepository.getBookmarksWithPlaces(effectiveUserId)).map((entry) => entry.place).toList();
      if (!_disposed) bookmarks = entries;
    } catch (_) {
      if (!_disposed) bookmarksError = 'Could not load bookmarks.';
    } finally {
      isLoadingBookmarks = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() { _disposed = true; super.dispose(); }


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
      if (!_disposed) notifyListeners();
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
      if (!_disposed) notifyListeners();
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