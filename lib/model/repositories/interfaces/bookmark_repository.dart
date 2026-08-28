import '../../dto/bookmark_with_place_dto.dart';
import '../../entities/bookmark.dart';

abstract class BookmarkRepository {
  /// Fetch all bookmarks with their associated place details for a user.
  Future<List<BookmarkWithPlaceDTO>> getBookmarksWithPlaces(String userId);

  /// Add a new bookmark.
  Future<void> addBookmark(Bookmark bookmark);

  /// Remove a bookmark by ID.
  Future<void> removeBookmark(String bookmarkId);

  /// Check if a place is already bookmarked by a user.
  Future<bool> isBookmarked(String userId, String placeId);
}