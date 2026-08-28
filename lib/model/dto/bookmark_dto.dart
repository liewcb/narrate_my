import '../entities/bookmark.dart';

/// Data Transfer Object for [Bookmark].
///
/// Handles serialization for Supabase and local database. The joined
/// [Place] lives in [BookmarkWithPlaceDTO] — this DTO only carries the
/// bookmark's own columns.
class BookmarkDTO {
  final String id;
  final String userId;
  final String itemId;
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

  // ─── From Supabase ──────────────────────────────────────────────
  factory BookmarkDTO.fromSupabase(Map<String, dynamic> json) {
    return BookmarkDTO(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      itemId: json['item_id'].toString(),
      itemType: json['item_type'].toString(),
      placeId: json['place_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  // ─── From JSON (alias for fromSupabase) ────────────────────────
  factory BookmarkDTO.fromJson(Map<String, dynamic> json) {
    return BookmarkDTO.fromSupabase(json);
  }

  // ─── From Local Database (SQLite) ──────────────────────────────
  factory BookmarkDTO.fromMap(Map<String, dynamic> map) {
    return BookmarkDTO(
      id: map['id'].toString(),
      userId: map['user_id'].toString(),
      itemId: map['item_id'].toString(),
      itemType: map['item_type'].toString(),
      placeId: map['place_id']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  // ─── To Local Database Map ─────────────────────────────────────
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

  // ─── From Domain Entity ────────────────────────────────────────
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

  // ─── To Domain Entity ──────────────────────────────────────────
  Bookmark toEntity() {
    return Bookmark(
      id: id,
      userId: userId,
      itemId: itemId,
      itemType: itemType,
      placeId: placeId,
      createdAt: createdAt,
    );
  }
}