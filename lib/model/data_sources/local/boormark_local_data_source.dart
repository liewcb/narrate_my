// lib/data/data_sources/local/bookmark_local_source.dart

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/services/local_database_service.dart';
import '../../dto/bookmark_dto.dart';
import '../../dto/bookmark_with_place_dto.dart';
import '../../dto/place_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/openning_hours.dart';
import '../../entities/place.dart';

/// Local data source for bookmarks (SQLite).
class BookmarkLocalSource {
  final LocalDatabaseService _local;

  BookmarkLocalSource({
    LocalDatabaseService? local,
  }) : _local = local ?? LocalDatabaseService();

  // ============================================================
  // FETCH BOOKMARKS WITH PLACE DETAILS
  // ============================================================

  Future<List<BookmarkWithPlaceDTO>>
  fetchBookmarksWithPlaces(
      String userId,
      ) async {
    final db = await _local.database;

    final result = await db.rawQuery(
      '''
      SELECT
        b.id AS bookmark_id,
        b.user_id,
        b.item_id,
        b.item_type,
        b.place_id AS bookmark_place_id,
        b.created_at AS bookmark_created_at,

        p.id AS place_database_id,
        p.place_id AS google_place_id,
        p.name AS place_name,
        p.address AS place_address,
        p.latitude AS place_latitude,
        p.longitude AS place_longitude,
        p.rating AS place_rating,
        p.types AS place_types,
        p.category AS place_category,
        p.visit_duration_minutes,
        p.best_time_suggestion,
        p.price_level,
        p.phone_number,
        p.website,
        p.photo_reference,
        p.opening_hours,
        p.created_at AS place_created_at

      FROM bookmarks b

      LEFT JOIN places p
        ON b.place_id = p.id

      WHERE b.user_id = ?

      ORDER BY b.created_at DESC
      ''',
      [userId],
    );

    return result.map((row) {
      // ========================================================
      // BOOKMARK
      // ========================================================

      final bookmark = Bookmark(
        id: row['bookmark_id'].toString(),

        userId: row['user_id'].toString(),

        itemId: row['item_id'].toString(),

        itemType: row['item_type'].toString(),

        placeId:
        row['bookmark_place_id']?.toString(),

        createdAt:
        row['bookmark_created_at'] != null
            ? DateTime.tryParse(
          row['bookmark_created_at']
              .toString(),
        ) ??
            DateTime.now()
            : DateTime.now(),
      );

      // ========================================================
      // PLACE
      // ========================================================

      final place = Place(
        id:
        row['place_database_id']?.toString() ??
            '',

        placeId:
        row['google_place_id']?.toString() ??
            '',

        placeName:
        row['place_name']?.toString() ??
            '',

        placeAddress:
        row['place_address']?.toString() ??
            '',

        placeLatitude:
        (row['place_latitude'] as num?)
            ?.toDouble() ??
            0.0,

        placeLongitude:
        (row['place_longitude'] as num?)
            ?.toDouble() ??
            0.0,

        placeRating:
        (row['place_rating'] as num?)
            ?.toDouble() ??
            0.0,

        placeTypes:
        row['place_types'] != null
            ? (row['place_types'] as String)
            .split(',')
            .map(
              (e) => e.trim(),
        )
            .where(
              (e) => e.isNotEmpty,
        )
            .toList()
            : [],

        category:
        row['place_category']?.toString(),

        visitDurationMinutes:
        row['visit_duration_minutes']
        as int?,

        bestTimeSuggestion:
        row['best_time_suggestion']
            ?.toString(),

        placePriceLevel:
        row['price_level'] as int?,

        placePhone:
        row['phone_number']?.toString(),

        placeWebsite:
        row['website']?.toString(),

        placePhotoRef:
        row['photo_reference']?.toString(),

        placeRegularOpeningHours:
        row['opening_hours'] != null
            ? OpeningHours.fromJson(
          (row['opening_hours'] is Map
              ? Map<String, dynamic>.from(
            row['opening_hours'] as Map,
          )
              : jsonDecode(
            row['opening_hours'] as String,
          )
          as Map<String, dynamic>),
        )
            : null,
      );

      // ========================================================
      // COMBINE BOOKMARK + PLACE
      // ========================================================

      return BookmarkWithPlaceDTO(
        bookmark: bookmark,
        place: place,
      );
    }).toList();
  }

  // ============================================================
  // INSERT BOOKMARK
  // ============================================================

  Future<void> insertBookmark(
      Bookmark bookmark,
      ) async {
    final db = await _local.database;

    await db.insert(
      'bookmarks',
      BookmarkDTO
          .fromEntity(bookmark)
          .toMap(),
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // DELETE BOOKMARK
  // ============================================================

  Future<void> deleteBookmark(
      String bookmarkId,
      ) async {
    final db = await _local.database;

    await db.delete(
      'bookmarks',
      where: 'id = ?',
      whereArgs: [bookmarkId],
    );
  }

  // ============================================================
  // CHECK BOOKMARK
  // ============================================================

  Future<bool> isBookmarked(
      String userId,
      String placeId,
      ) async {
    final db = await _local.database;

    final result = await db.query(
      'bookmarks',
      where:
      'user_id = ? AND place_id = ?',
      whereArgs: [
        userId,
        placeId,
      ],
    );

    return result.isNotEmpty;
  }

  // ============================================================
  // CACHE BOOKMARKS WITH PLACES
  // ============================================================

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