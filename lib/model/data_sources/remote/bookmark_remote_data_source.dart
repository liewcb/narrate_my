// lib/data/data_sources/remote/bookmark_remote_data_source.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_manager.dart';
import '../../dto/bookmark_dto.dart';
import '../../dto/bookmark_with_place_dto.dart';
import '../../dto/place_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/place.dart';

/// Shared Supabase persistence for bookmarks created by Itinerary, Nearby,
/// AR, AI Chat, or any future module.
///
/// All default access goes through [DatabaseManager] so the application has
/// one initialized Supabase client. Tests may still inject a client.
class BookmarkRemoteSource {
  final SupabaseClient _client;

  BookmarkRemoteSource({SupabaseClient? client})
      : _client = client ?? DatabaseManager().remote.client;

  /// Current authenticated user ID.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Fetch bookmarks together with their associated Place records.
  Future<List<BookmarkWithPlaceDTO>> fetchBookmarksWithPlaces(
      String userId,
      ) async {
    try {
      final data = await _client
          .from('bookmarks')
          .select('*, places(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return data.map((json) {
        final bookmark =
        BookmarkDTO.fromSupabase(json).toEntity();

        final placeJson = json['places'];

        if (placeJson is! Map) {
          throw const FormatException(
            'Bookmark is missing its joined place.',
          );
        }

        final place = PlaceDto.fromJson(
          Map<String, dynamic>.from(placeJson),
        ).toEntity();

        return BookmarkWithPlaceDTO(
          bookmark: bookmark,
          place: place,
        );
      }).toList();
    } catch (e) {
      print('❌ Remote fetch failed: $e');
      return [];
    }
  }

  /// Upserts a Place using Google's stable place_id.
  ///
  /// Returns the canonical Supabase Place row.
  ///
  /// The internal Supabase `id` returned here is the value that should be
  /// used by `bookmarks.place_id`.
  Future<Place> upsertPlaceByGoogleId(Place place) async {
    final googlePlaceId = place.placeId.trim();

    if (googlePlaceId.isEmpty) {
      throw const BookmarkPersistenceException(
        'A verified Google Place ID is required to bookmark this place.',
      );
    }

    final existing = await _client
        .from('places')
        .select('id')
        .eq('place_id', googlePlaceId)
        .maybeSingle();

    final internalId = existing?['id']?.toString().trim();

    final placeWithId = place.copyWith(
      id: internalId?.isNotEmpty == true
          ? internalId
          : (place.id.trim().isNotEmpty
          ? place.id.trim()
          : googlePlaceId),
    );

    final row = await _client
        .from('places')
        .upsert(
      PlaceDto.fromEntity(placeWithId).toJsonForRemote(),
      onConflict: 'place_id',
    )
        .select()
        .single();

    return PlaceDto.fromJson(row).toEntity();
  }

  /// Find a bookmark using the internal Supabase Place ID.
  Future<Bookmark?> findPlaceBookmark({
    required String userId,
    required String internalPlaceId,
  }) async {
    final row = await _client
        .from('bookmarks')
        .select()
        .eq('user_id', userId)
        .eq('place_id', internalPlaceId)
        .maybeSingle();

    return row == null
        ? null
        : BookmarkDTO.fromSupabase(row).toEntity();
  }

  /// Find a bookmark using Google's stable place_id.
  Future<Bookmark?> findPlaceBookmarkByGoogleId({
    required String userId,
    required String googlePlaceId,
  }) async {
    final place = await _client
        .from('places')
        .select('id')
        .eq('place_id', googlePlaceId.trim())
        .maybeSingle();

    if (place == null) {
      return null;
    }

    return findPlaceBookmark(
      userId: userId,
      internalPlaceId: place['id'].toString(),
    );
  }

  /// Inserts a bookmark and returns the canonical Supabase row.
  Future<Bookmark> insertBookmark(Bookmark bookmark) async {
    final row = await _client
        .from('bookmarks')
        .insert(
      BookmarkDTO.fromEntity(bookmark).toRemoteMap(),
    )
        .select()
        .single();

    return BookmarkDTO.fromSupabase(row).toEntity();
  }

  /// Add a new bookmark to Supabase.
  ///
  /// Kept for backward compatibility with existing callers.
  Future<void> addBookmark(Bookmark bookmark) async {
    await insertBookmark(bookmark);
  }

  /// Remove a bookmark by its ID.
  Future<void> deleteBookmark(String bookmarkId) async {
    final userId = currentUserId;

    if (userId == null) {
      throw const BookmarkPersistenceException(
        'Login is required.',
      );
    }

    final deletedRows = await _client
        .from('bookmarks')
        .delete()
        .eq('id', bookmarkId)
        .eq('user_id', userId)
        .select('id');

    if (deletedRows.isEmpty) {
      throw const BookmarkPersistenceException(
        'The bookmark could not be found or removed.',
      );
    }
  }
}

/// Exception used for controlled bookmark persistence failures.
class BookmarkPersistenceException implements Exception {
  final String message;

  const BookmarkPersistenceException(this.message);

  @override
  String toString() => message;
}
