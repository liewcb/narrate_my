// lib/data/data_sources/remote/bookmark_remote_data_source.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dto/bookmark_dto.dart';
import '../../dto/bookmark_with_place_dto.dart';
import '../../dto/place_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/place.dart';

/// Remote data source for bookmarks (Supabase).
class BookmarkRemoteSource {
  final SupabaseClient _client;

  BookmarkRemoteSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Fetch bookmarks with associated place details for a user.
  Future<List<BookmarkWithPlaceDTO>> fetchBookmarksWithPlaces(String userId) async {
    try {
      final response = await _client
          .from('bookmarks')
          .select('*, places(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List;
      return data.map((json) {
        final bookmark = BookmarkDTO.fromSupabase(json).toEntity();
        final place = PlaceDto.fromJson(json['places'] as Map<String, dynamic>).toEntity();
        return BookmarkWithPlaceDTO(bookmark: bookmark, place: place);
      }).toList();
    } catch (e) {
      print('Remote fetch bookmarks failed: $e');
      return [];
    }
  }

  /// Add a new bookmark to Supabase.
  Future<void> addBookmark(Bookmark bookmark) async {
    final dto = BookmarkDTO.fromEntity(bookmark);
    await _client.from('bookmarks').insert(dto.toMap());
  }

  /// Remove a bookmark by its ID.
  Future<void> deleteBookmark(String bookmarkId) async {
    await _client.from('bookmarks').delete().eq('id', bookmarkId);
  }
}