import 'package:flutter/foundation.dart';
import 'package:postgrest/postgrest.dart';

import '../../../core/services/database_manager.dart';
import '../../data_sources/local/boormark_local_data_source.dart';
import '../../data_sources/remote/bookmark_remote_data_source.dart';
import '../../dto/bookmark_with_place_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/place.dart';
import '../interfaces/bookmark_repository.dart';

class BookmarkRepositoryImpl implements BookmarkRepository {
  final BookmarkLocalSource _localSource;
  final BookmarkRemoteSource _remoteSource;

  BookmarkRepositoryImpl({
    BookmarkLocalSource? localSource,
    BookmarkRemoteSource? remoteSource,
  })  : _localSource =
      localSource ?? BookmarkLocalSource(),
        _remoteSource =
            remoteSource ?? BookmarkRemoteSource();

  // ─────────────────────────────────────────────────────────────
  // Current authenticated user
  // ─────────────────────────────────────────────────────────────

  @override
  String? get currentUserId => _remoteSource.currentUserId;

  // ─────────────────────────────────────────────────────────────
  // GET BOOKMARKS
  //
  // REMOTE = source of truth
  // LOCAL  = fallback cache
  // ─────────────────────────────────────────────────────────────

  @override
  Future<List<BookmarkWithPlaceDTO>> getBookmarksWithPlaces(
      String userId,
      ) async {
    try {
      debugPrint(
        '[BookmarkRepo] Fetching bookmarks from REMOTE...',
      );

      final remoteResult =
      await _remoteSource.fetchBookmarksWithPlaces(userId);

      debugPrint(
        '[BookmarkRepo] Remote returned '
            '${remoteResult.length} bookmark(s)',
      );

      // Remote returned data.
      // Cache each remote record locally.
      if (remoteResult.isNotEmpty) {
        try {
          for (final item in remoteResult) {
            await _localSource.cacheBookmarkWithPlace(item);
          }

          debugPrint(
            '[BookmarkRepo] Local cache updated successfully.',
          );
        } catch (e) {
          debugPrint(
            '[BookmarkRepo] Local cache update failed: $e',
          );
        }

        return remoteResult;
      }

      // Remote returned no bookmarks.
      debugPrint(
        '[BookmarkRepo] Remote returned no bookmarks. '
            'Checking local cache...',
      );

      try {
        final localResult =
        await _localSource.fetchBookmarksWithPlaces(userId);

        debugPrint(
          '[BookmarkRepo] Local cache returned '
              '${localResult.length} bookmark(s)',
        );

        return localResult;
      } catch (e) {
        debugPrint(
          '[BookmarkRepo] Local cache fallback failed: $e',
        );

        return [];
      }
    } catch (e) {
      debugPrint(
        '[BookmarkRepo] Remote fetch failed: $e',
      );

      try {
        final localResult =
        await _localSource.fetchBookmarksWithPlaces(userId);

        debugPrint(
          '[BookmarkRepo] Local fallback returned '
              '${localResult.length} bookmark(s)',
        );

        return localResult;
      } catch (localError) {
        debugPrint(
          '[BookmarkRepo] Local fallback failed: $localError',
        );

        return [];
      }
    }
  }
  // ─────────────────────────────────────────────────────────────
  // ADD BOOKMARK
  //
  // REMOTE FIRST
  // LOCAL CACHE ONLY AFTER REMOTE SUCCESS
  // ─────────────────────────────────────────────────────────────

  @override
  Future<void> addBookmark(
      Bookmark bookmark,
      ) async {
    debugPrint(
      '[BookmarkRepo] Adding bookmark REMOTE first...',
    );

    try {
      await _remoteSource.addBookmark(bookmark);

      debugPrint(
        '[BookmarkRepo] Remote bookmark insert SUCCESS',
      );
    } catch (e) {
      debugPrint(
        '[BookmarkRepo] Remote bookmark insert FAILED: $e',
      );

      // VERY IMPORTANT:
      // Do NOT write to SQLite when remote fails.
      rethrow;
    }

    // Remote succeeded.
    // SQLite is only a cache.
    try {
      await _localSource.insertBookmark(bookmark);

      debugPrint(
        '[BookmarkRepo] Local bookmark cache updated.',
      );
    } catch (e) {
      // Remote operation already succeeded.
      // Local cache failure must NOT turn remote success into failure.
      debugPrint(
        '[BookmarkRepo] Remote SUCCESS but local cache FAILED: $e',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // REMOVE BOOKMARK
  //
  // REMOTE FIRST
  // LOCAL CACHE ONLY AFTER REMOTE SUCCESS
  // ─────────────────────────────────────────────────────────────

  @override
  Future<void> removeBookmark(
      String bookmarkId,
      ) async {
    debugPrint(
      '[BookmarkRepo] Removing bookmark REMOTE first...',
    );

    try {
      await _remoteSource.deleteBookmark(bookmarkId);

      debugPrint(
        '[BookmarkRepo] Remote bookmark delete SUCCESS',
      );
    } catch (e) {
      debugPrint(
        '[BookmarkRepo] Remote bookmark delete FAILED: $e',
      );

      // Do NOT modify SQLite if remote deletion failed.
      rethrow;
    }

    try {
      await _localSource.deleteBookmark(bookmarkId);

      debugPrint(
        '[BookmarkRepo] Local bookmark cache deleted.',
      );
    } catch (e) {
      debugPrint(
        '[BookmarkRepo] Remote SUCCESS but local delete FAILED: $e',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ADD PLACE BOOKMARK
  //
  // 1. Verify/login
  // 2. Upsert Place REMOTELY
  // 3. Find existing bookmark REMOTELY
  // 4. Insert bookmark REMOTELY if necessary
  // 5. Cache locally AFTER remote success
  // ─────────────────────────────────────────────────────────────

  @override
  Future<bool> addPlaceBookmark(
      Place place, {
        required String itemType,
      }) async {
    final userId = currentUserId;

    if (userId == null) {
      throw const BookmarkPersistenceException(
        'Login is required.',
      );
    }

    debugPrint(
      '[BookmarkRepo] Bookmarking place: ${place.placeId}',
    );

    // ─────────────────────────────────────────────────────────
    // Step 1: Upsert Place remotely
    // ─────────────────────────────────────────────────────────

    final remotePlace =
    await _remoteSource.upsertPlaceByGoogleId(place);

    debugPrint(
      '[BookmarkRepo] Remote place ID: ${remotePlace.id}',
    );

    // ─────────────────────────────────────────────────────────
    // Step 2: Check existing bookmark remotely
    // ─────────────────────────────────────────────────────────

    var bookmark =
    await _remoteSource.findPlaceBookmark(
      userId: userId,
      internalPlaceId: remotePlace.id,
    );

    var created = false;

    // ─────────────────────────────────────────────────────────
    // Step 3: Create bookmark remotely if it doesn't exist
    // ─────────────────────────────────────────────────────────

    if (bookmark == null) {
      try {
        bookmark =
        await _remoteSource.insertBookmark(
          Bookmark(
            id: '',
            userId: userId,
            itemType: itemType,
            placeId: remotePlace.id,
          ),
        );

        created = true;

        debugPrint(
          '[BookmarkRepo] Remote bookmark CREATED',
        );
      } on PostgrestException catch (error) {
        // Another request/device may have created it.
        if (error.code != '23505') {
          rethrow;
        }

        debugPrint(
          '[BookmarkRepo] Bookmark race detected. '
              'Fetching existing bookmark...',
        );

        bookmark =
        await _remoteSource.findPlaceBookmark(
          userId: userId,
          internalPlaceId: remotePlace.id,
        );

        if (bookmark == null) {
          rethrow;
        }
      }
    } else {
      debugPrint(
        '[BookmarkRepo] Bookmark already exists remotely.',
      );
    }

    // ─────────────────────────────────────────────────────────
    // Step 4: Update SQLite cache AFTER remote success
    // ─────────────────────────────────────────────────────────

    try {
      await _localSource.cacheBookmarkWithPlace(
        BookmarkWithPlaceDTO(
          bookmark: bookmark,
          place: remotePlace,
        ),
      );

      debugPrint(
        '[BookmarkRepo] Local bookmark cache updated.',
      );
    } catch (error) {
      // Remote is already successful.
      // Do NOT report the bookmark operation as failed.
      debugPrint(
        '[BookmarkRepo] Remote bookmark saved but '
            'local cache failed: $error',
      );
    }

    return created;
  }

  // ─────────────────────────────────────────────────────────────
  // GET PLACE BOOKMARK
  // ─────────────────────────────────────────────────────────────

  @override
  Future<Bookmark?> getPlaceBookmark(
      String userId,
      String googlePlaceId,
      ) {
    return _remoteSource.findPlaceBookmarkByGoogleId(
      userId: userId,
      googlePlaceId: googlePlaceId,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // IS BOOKMARKED
  // ─────────────────────────────────────────────────────────────

  @override
  Future<bool> isBookmarked(
      String userId,
      String placeId,
      ) async {
    // Remote is the source of truth.
    //
    // Check remote first.
    final remoteBookmark =
    await _remoteSource.findPlaceBookmarkByGoogleId(
      userId: userId,
      googlePlaceId: placeId,
    );

    if (remoteBookmark != null) {
      return true;
    }

    return false;
  }
}