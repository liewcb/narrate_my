import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data_sources/local/boormark_local_data_source.dart';
import '../../data_sources/remote/bookmark_remote_data_source.dart';
import '../../dto/bookmark_with_place_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/place.dart';
import '../interfaces/bookmark_repository.dart';

/// Shared bookmark repository used by Itinerary, Nearby, AR, and AI Chat.
///
/// Supabase is authoritative. SQLite is updated only after the corresponding
/// remote operation succeeds, which prevents a failed network write from
/// appearing as a real bookmark on one phone.
class BookmarkRepositoryImpl implements BookmarkRepository {
  final BookmarkLocalSource _localSource;
  final BookmarkRemoteSource _remoteSource;

  BookmarkRepositoryImpl({
    BookmarkLocalSource? localSource,
    BookmarkRemoteSource? remoteSource,
  }) : _localSource = localSource ?? BookmarkLocalSource(),
       _remoteSource = remoteSource ?? BookmarkRemoteSource();

  @override
  String? get currentUserId => _remoteSource.currentUserId;

  @override
  Future<List<BookmarkWithPlaceDTO>> getBookmarksWithPlaces(
    String userId,
  ) async {
    try {
      final remoteResult = await _remoteSource.fetchBookmarksWithPlaces(userId);
      if (remoteResult.isNotEmpty) {
        try {
          await _localSource.cacheBookmarksWithPlaces(remoteResult);
        } catch (error) {
          debugPrint('Unable to cache remote bookmarks locally: $error');
        }
      }
      return remoteResult;
    } catch (error) {
      debugPrint('Remote bookmarks unavailable; using SQLite: $error');
      return _localSource.fetchBookmarksWithPlaces(userId);
    }
  }

  @override
  Future<void> addBookmark(Bookmark bookmark) async {
    final remoteBookmark = await _remoteSource.insertBookmark(bookmark);
    try {
      await _localSource.insertBookmark(remoteBookmark);
    } catch (error) {
      debugPrint('Remote bookmark saved but local cache failed: $error');
    }
  }

  @override
  Future<bool> addPlaceBookmark(Place place, {required String itemType}) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const BookmarkPersistenceException('Login is required.');
    }

    // The upsert is keyed by Google place_id. Supabase returns the canonical
    // places.id, which is the FK stored in bookmarks.place_id.
    final remotePlace = await _remoteSource.upsertPlaceByGoogleId(place);
    var bookmark = await _remoteSource.findPlaceBookmark(
      userId: userId,
      internalPlaceId: remotePlace.id,
    );
    var created = false;

    if (bookmark == null) {
      try {
        bookmark = await _remoteSource.insertBookmark(
          Bookmark(
            id: '',
            userId: userId,
            itemType: itemType,
            placeId: remotePlace.id,
          ),
        );
        created = true;
      } on PostgrestException catch (error) {
        if (error.code != '23505') rethrow;
        // Another module/device won the race. Return the row it created.
        bookmark = await _remoteSource.findPlaceBookmark(
          userId: userId,
          internalPlaceId: remotePlace.id,
        );
        if (bookmark == null) rethrow;
      }
    }

    try {
      await _localSource.cacheBookmarkWithPlace(
        BookmarkWithPlaceDTO(bookmark: bookmark, place: remotePlace),
      );
    } catch (error) {
      debugPrint('Remote bookmark saved but local cache failed: $error');
    }
    return created;
  }

  @override
  Future<void> removeBookmark(String bookmarkId) async {
    await _remoteSource.deleteBookmark(bookmarkId);
    try {
      await _localSource.deleteBookmark(bookmarkId);
    } catch (error) {
      debugPrint('Remote bookmark removed but local cache failed: $error');
    }
  }

  @override
  Future<Bookmark?> getPlaceBookmark(String userId, String googlePlaceId) {
    return _remoteSource.findPlaceBookmarkByGoogleId(
      userId: userId,
      googlePlaceId: googlePlaceId,
    );
  }

  @override
  Future<bool> isBookmarked(String userId, String googlePlaceId) async {
    final bookmark = await getPlaceBookmark(userId, googlePlaceId);
    return bookmark != null;
  }
}
