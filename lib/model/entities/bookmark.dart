/// Domain entity for a user's bookmark.
///
/// [itemId] identifies the bookmarked entity (e.g., a place ID from Google).
/// [itemType] identifies the type (e.g., 'place', 'attraction', 'restaurant').
/// [placeId] is optional and may reference the local `places` table.
class Bookmark {
  final String id;
  final String userId;
  final String itemId;
  final String itemType;
  final String? placeId;
  final DateTime? createdAt;

  const Bookmark({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.itemType,
    this.placeId,
    this.createdAt,
  });
}