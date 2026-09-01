import '../entities/bookmark.dart';

/// Data Transfer Object for [Bookmark].
///
/// Handles serialization between:
/// - Supabase
/// - Local SQLite database
/// - Domain [Bookmark] entity
///
/// This DTO only contains bookmark fields.
/// Place data is handled separately by [BookmarkWithPlaceDTO].
class BookmarkDTO {
  final String id;
  final String userId;
  final String? itemId;
  final String itemType;
  final String? placeId;
  final DateTime? createdAt;

  const BookmarkDTO({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.itemType,
    this.placeId,
    this.createdAt,
  });

  // ============================================================
  // FROM SUPABASE
  // ============================================================

  factory BookmarkDTO.fromSupabase(Map<String, dynamic> json) {
    return BookmarkDTO(
      id: json['id'].toString(),

      userId: json['user_id'].toString(),

      itemId: json['item_id'].toString(),

      itemType: json['item_type'].toString(),

      placeId: json['place_id'] != null ? json['place_id'].toString() : null,

      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  // ============================================================
  // FROM JSON
  // ============================================================

  factory BookmarkDTO.fromJson(Map<String, dynamic> json) {
    return BookmarkDTO.fromSupabase(json);
  }

  /// Supabase insert/update payload. Database-generated values are omitted
  /// when empty so their defaults can run.
  Map<String, dynamic> toRemoteMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'user_id': userId,
      if (itemId != null) 'item_id': itemId,
      'item_type': itemType,
      if (placeId != null) 'place_id': placeId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  // ============================================================
  // FROM LOCAL SQLITE
  // ============================================================

  factory BookmarkDTO.fromMap(Map<String, dynamic> map) {
    return BookmarkDTO(
      id: map['id'].toString(),

      userId: map['user_id'].toString(),

      itemId: map['item_id'].toString(),

      itemType: map['item_type'].toString(),

      placeId: map['place_id'] != null ? map['place_id'].toString() : null,

      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  // ============================================================
  // TO SUPABASE
  // ============================================================

  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'user_id': userId,
      'item_id': itemId,
      'item_type': itemType,
      'place_id': placeId,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  // ============================================================
  // TO LOCAL SQLITE
  // ============================================================

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'item_id': itemId,
      'item_type': itemType,
      'place_id': placeId,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  // ============================================================
  // FROM DOMAIN ENTITY
  // ============================================================

  factory BookmarkDTO.fromEntity(Bookmark entity) {
    return BookmarkDTO(
      id: entity.id,
      userId: entity.userId,
      itemId: entity.itemId,
      itemType: entity.itemType,
      placeId: entity.placeId,
      createdAt: entity.createdAt,
    );
  }

  // ============================================================
  // TO DOMAIN ENTITY
  // ============================================================

  Bookmark toEntity() {
    return Bookmark(
      id: id,
      userId: userId,
      itemId: itemId,
      itemType: itemType,
      placeId: placeId,
      createdAt: createdAt ?? DateTime.now(),
    );
  }
}
