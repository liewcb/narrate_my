// lib/data/data_sources/local/bookmark_local_source.dart
import 'package:sqflite/sqflite.dart';

import '../../../core/services/database_manager.dart';
import '../../../core/services/local_database_service.dart';
import '../../dto/bookmark_dto.dart';
import '../../dto/bookmark_with_place_dto.dart';
import '../../dto/place_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/place.dart';

/// Local data source for bookmarks (SQLite).
class BookmarkLocalSource {
  final LocalDatabaseService _local;

  BookmarkLocalSource({LocalDatabaseService? local})
    : _local = local ?? DatabaseManager().local;

  /// Fetch bookmarks with associated place details for a user.
  Future<List<BookmarkWithPlaceDTO>> fetchBookmarksWithPlaces(
    String userId,
  ) async {
    final db = await _local.database;
    final result = await db.rawQuery(
      '''
      SELECT
        b.id as bookmark_id,
        b.user_id,
        b.item_id,
        b.item_type,
        b.place_id as bookmark_place_id,
        b.created_at as bookmark_created_at,
        p.id as place_internal_id,
        p.place_id as google_place_id,
        p.name as place_name,
        p.address as place_address,
        p.latitude,
        p.longitude,
        p.rating as place_rating,
        p.types as place_types,
        p.photo_reference,
        p.opening_hours,
        p.price_level,
        p.phone_number,
        p.website,
        p.visit_duration_minutes,
        p.category,
        p.best_time_suggestion
      FROM bookmarks b
      LEFT JOIN places p ON b.place_id = p.id
      WHERE b.user_id = ?
      ORDER BY b.created_at DESC
    ''',
      [userId],
    );

    return result.map((row) {
      final bookmark = Bookmark(
        id: row['bookmark_id'].toString(),
        userId: row['user_id'].toString(),
        itemId: row['item_id']?.toString(),
        itemType: row['item_type'].toString(),
        placeId: row['bookmark_place_id']?.toString(),
        createdAt: row['bookmark_created_at'] != null
            ? DateTime.tryParse(row['bookmark_created_at'].toString())
            : null,
      );

      final place = Place(
        id: row['place_internal_id']?.toString() ?? '',
        placeName: row['place_name']?.toString() ?? '',
        placeAddress: row['place_address']?.toString() ?? '',
        placeLatitude: (row['latitude'] as num?)?.toDouble() ?? 0.0,
        placeLongitude: (row['longitude'] as num?)?.toDouble() ?? 0.0,
        placeRating: (row['place_rating'] as num?)?.toDouble() ?? 0.0,
        placeTypes: row['place_types'] != null
            ? (row['place_types'] as String)
                  .split(',')
                  .map((e) => e.trim())
                  .toList()
            : [],
        placePhotoRef: row['photo_reference'] as String?,
        placeId: row['google_place_id']?.toString() ?? '',
      );

      return BookmarkWithPlaceDTO(bookmark: bookmark, place: place);
    }).toList();
  }

  Future<void> insertBookmark(Bookmark bookmark) async {
    final db = await _local.database;
    await db.insert(
      'bookmarks',
      BookmarkDTO.fromEntity(bookmark).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    final db = await _local.database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [bookmarkId]);
  }

  Future<bool> isBookmarked(String userId, String placeId) async {
    final db = await _local.database;
    final result = await db.query(
      'bookmarks',
      where: 'user_id = ? AND place_id = ?',
      whereArgs: [userId, placeId],
    );
    return result.isNotEmpty;
  }

  Future<void> cacheBookmarksWithPlaces(
    List<BookmarkWithPlaceDTO> combined,
  ) async {
    final db = await _local.database;
    final batch = db.batch();
    for (final item in combined) {
      batch.insert(
        'bookmarks',
        BookmarkDTO.fromEntity(item.bookmark).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.insert(
        'places',
        PlaceDto.fromEntity(item.place).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit();
  }

  /// Cache one confirmed remote result. This is deliberately called only
  /// after Supabase has accepted (or returned) the bookmark.
  Future<void> cacheBookmarkWithPlace(BookmarkWithPlaceDTO combined) async {
    final db = await _local.database;
    await db.transaction((txn) async {
      await txn.insert(
        'places',
        PlaceDto.fromEntity(combined.place).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'bookmarks',
        BookmarkDTO.fromEntity(combined.bookmark).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
