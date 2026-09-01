import '../../entities/place.dart';
import '../../entities/bookmark.dart';
import '../../repositories/adapters/bookmark_repository_adapter.dart';
import '../../repositories/interfaces/bookmark_repository.dart';

/// One bookmark entry point shared by Nearby, AR, AI Chat, and Itinerary.
///
/// Screens and ViewModels never call Supabase directly. They pass a canonical
/// [Place] here, and the existing [BookmarkRepository] owns remote persistence,
/// duplicate handling, and post-success SQLite caching.
class PlaceBookmarkService {
  final BookmarkRepository _repository;

  PlaceBookmarkService({BookmarkRepository? repository})
      : _repository = repository ?? BookmarkRepositoryImpl();

  String? get currentUserId => _repository.currentUserId;

  Future<bool> isBookmarked(String googlePlaceId) {
    final userId = currentUserId;
    if (userId == null) return Future.value(false);
    return _repository.isBookmarked(userId, googlePlaceId);
  }

  Future<Bookmark?> getBookmark(String googlePlaceId) {
    final userId = currentUserId;
    if (userId == null) return Future.value(null);
    return _repository.getPlaceBookmark(userId, googlePlaceId);
  }

  Future<bool> bookmarkPlace(Place place, {required String itemType}) {
    return _repository.addPlaceBookmark(place, itemType: itemType);
  }

  Future<void> removeBookmark(String bookmarkId) {
    return _repository.removeBookmark(bookmarkId);
  }
}