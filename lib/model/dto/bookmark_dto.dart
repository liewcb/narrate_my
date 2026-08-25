import '../entities/bookmark.dart';

class BookmarkDto {
  final String id;
  final String itemId;
  final String itemType;
  final String? createdAt;

  BookmarkDto({
    required this.id,
    required this.itemId,
    required this.itemType,
    this.createdAt,
  });

  factory BookmarkDto.fromJson(Map<String, dynamic> json) {
    return BookmarkDto(
      id: json['id'] as String,
      itemId: json['item_id'] as String,
      itemType: json['item_type'] as String? ?? 'attraction',
      createdAt: json['created_at'] as String?,
    );
  }

  Bookmark toEntity() => Bookmark(
        id: id,
        itemId: itemId,
        itemType: itemType,
        createdAt: createdAt == null ? null : DateTime.tryParse(createdAt!),
      );
}
