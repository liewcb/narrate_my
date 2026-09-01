import '../../dto/bookmark_with_place_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/place.dart';

abstract class BookmarkRepository {
  /// Current authenticated Supabase user, or null for a guest session.
  String? get currentUserId;

  /// Fetch all bookmarks with their associated place details for a user.
  Future<List<BookmarkWithPlaceDTO>> getBookmarksWithPlaces(String userId);

  /// Add a new bookmark.
  Future<void> addBookmark(Bookmark bookmark);

  /// Saves/upserts [place] remotely, stores the returned places.id in the
  /// bookmark, then updates SQLite. Returns true only for a newly-created
  /// bookmark; an existing bookmark is an idempotent false result.
  Future<bool> addPlaceBookmark(Place place, {required String itemType});

  /// Remove a bookmark by ID.
  Future<void> removeBookmark(String bookmarkId);

  /// Find the user's bookmark using Google's canonical place_id.
  Future<Bookmark?> getPlaceBookmark(String userId, String googlePlaceId);

  /// Check if a place is already bookmarked by a user.
  Future<bool> isBookmarked(String userId, String placeId);
}