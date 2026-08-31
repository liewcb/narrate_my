import 'package:flutter/foundation.dart';

import '../model/business_logic/shared_services/place_bookmark_service.dart';
import '../model/entities/place.dart';
import '../model/entities/bookmark.dart';

enum BookmarkResult { added, removed, alreadyBookmarked, loginRequired, failed }

/// Shared bookmark-button state for Nearby, AR, AI Chat, and other modules.
///
/// Usage guide:
/// 1. Create one VM for the details/card being displayed.
/// 2. Call [load] with its Google place_id.
/// 3. Call [toggleBookmark] when the user taps the button.
/// 4. If login is required, complete the login flow and then call
///    [retryPendingBookmark]. The VM keeps the pending [Place] in memory.
class BookmarkVm extends ChangeNotifier {
  final PlaceBookmarkService _service;

  BookmarkVm({PlaceBookmarkService? service})
    : _service = service ?? PlaceBookmarkService();

  bool _isChecking = false;
  bool _isSaving = false;
  bool _isBookmarked = false;
  String? _errorMessage;
  String? _statusMessage;
  Bookmark? _bookmark;
  Place? _pendingPlace;
  String? _pendingItemType;

  bool get isChecking => _isChecking;
  bool get isSaving => _isSaving;
  bool get isBookmarked => _isBookmarked;
  bool get isLoggedIn => _service.currentUserId != null;
  bool get hasPendingBookmark => _pendingPlace != null;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;

  Future<void> load(String googlePlaceId) async {
    if (!isLoggedIn) return;

    _isChecking = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();
    try {
      _bookmark = await _service.getBookmark(googlePlaceId);
      _isBookmarked = _bookmark != null;
    } catch (error) {
      debugPrint('Unable to check bookmark status: $error');
      _errorMessage = 'Unable to check bookmark status.';
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<BookmarkResult> toggleBookmark(
    Place place, {
    required String itemType,
  }) async {
    if (_isBookmarked) return _remove(place.placeId);
    return bookmark(place, itemType: itemType);
  }

  Future<BookmarkResult> bookmark(
    Place place, {
    required String itemType,
  }) async {
    if (!isLoggedIn) {
      _pendingPlace = place;
      _pendingItemType = itemType;
      return BookmarkResult.loginRequired;
    }
    return _save(place, itemType: itemType);
  }

  Future<BookmarkResult> retryPendingBookmark() async {
    final place = _pendingPlace;
    final itemType = _pendingItemType;
    if (place == null || itemType == null) {
      return BookmarkResult.failed;
    }
    if (!isLoggedIn) return BookmarkResult.loginRequired;
    return _save(place, itemType: itemType);
  }

  void clearPendingBookmark() {
    _pendingPlace = null;
    _pendingItemType = null;
  }

  Future<BookmarkResult> _save(Place place, {required String itemType}) async {
    if (_isBookmarked) {
      clearPendingBookmark();
      return BookmarkResult.alreadyBookmarked;
    }

    _isSaving = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();
    try {
      final created = await _service.bookmarkPlace(place, itemType: itemType);
      _bookmark = await _service.getBookmark(place.placeId);
      _isBookmarked = true;
      _statusMessage = created
          ? 'Attraction added to bookmarks.'
          : 'This attraction is already bookmarked.';
      clearPendingBookmark();
      return created ? BookmarkResult.added : BookmarkResult.alreadyBookmarked;
    } catch (error) {
      debugPrint('Unable to bookmark place: $error');
      _errorMessage = 'Unable to bookmark this place. Please try again.';
      _statusMessage = _errorMessage;
      return BookmarkResult.failed;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<BookmarkResult> _remove(String googlePlaceId) async {
    _isSaving = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();
    try {
      final bookmark = _bookmark ?? await _service.getBookmark(googlePlaceId);
      if (bookmark == null) {
        _isBookmarked = false;
        _statusMessage = 'Bookmark removed.';
        return BookmarkResult.removed;
      }
      await _service.removeBookmark(bookmark.id);
      _bookmark = null;
      _isBookmarked = false;
      _statusMessage = 'Bookmark removed.';
      return BookmarkResult.removed;
    } catch (error) {
      debugPrint('Unable to remove bookmark: $error');
      _errorMessage = 'Unable to remove this bookmark. Please try again.';
      _statusMessage = _errorMessage;
      return BookmarkResult.failed;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
