import '../../data_sources/local/boormark_local_data_source.dart';
import '../../data_sources/remote/bookmark_remote_data_source.dart';
import '../../dto/bookmark_with_place_dto.dart';
import '../../entities/bookmark.dart';
import '../interfaces/bookmark_repository.dart';

class BookmarkRepositoryImpl implements BookmarkRepository {
  final BookmarkLocalSource _localSource;
  final BookmarkRemoteSource _remoteSource;

  BookmarkRepositoryImpl({
    BookmarkLocalSource? localSource,
    BookmarkRemoteSource? remoteSource,
  })  : _localSource = localSource ?? BookmarkLocalSource(),
        _remoteSource = remoteSource ?? BookmarkRemoteSource();

  // ─── Public Methods ──────────────────────────────────────────────

  @override
  Future<List<BookmarkWithPlaceDTO>> getBookmarksWithPlaces(String userId) async {
    // 1. Remote first (source of truth)
    final remoteResult = await _remoteSource.fetchBookmarksWithPlaces(userId);

    if (remoteResult.isNotEmpty) {
      // Cache the authoritative remote data.
      try {
        await _localSource.cacheBookmarksWithPlaces(remoteResult);
      } catch (e) {
        print('[BookmarkRepo] Local cache write failed: $e');
      }
      return remoteResult;
    }

    // 2. Local cache fallback (offline)
    List<BookmarkWithPlaceDTO> localResult = [];
    try {
      localResult = await _localSource.fetchBookmarksWithPlaces(userId);
    } catch (e) {
      print('Local bookmarks not available: $e');
    }
    return localResult;
  }

  @override
  Future<void> addBookmark(Bookmark bookmark) async {
    // 1. Insert remotely first (source of truth)
    try {
      await _remoteSource.addBookmark(bookmark);
    } catch (e) {
      print('[BookmarkRepo] Remote add bookmark failed: $e');
      rethrow;
    }

    // 2. Cache locally on remote success (best-effort)
    try {
      await _localSource.insertBookmark(bookmark);
    } catch (e) {
      print('[BookmarkRepo] Local cache insert failed: $e');
    }
  }

  @override
  Future<void> removeBookmark(String bookmarkId) async {
    // 1. Delete remotely first (source of truth)
    try {
      await _remoteSource.deleteBookmark(bookmarkId);
    } catch (e) {
      print('[BookmarkRepo] Remote delete bookmark failed: $e');
      rethrow;
    }

    // 2. Delete locally on remote success (best-effort)
    try {
      await _localSource.deleteBookmark(bookmarkId);
    } catch (e) {
      print('[BookmarkRepo] Local delete failed: $e');
    }
  }

  @override
  Future<bool> isBookmarked(String userId, String placeId) async {
    return _localSource.isBookmarked(userId, placeId);
  }
}