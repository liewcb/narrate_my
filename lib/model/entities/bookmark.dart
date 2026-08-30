/// Domain entity for UC402 A22 (View and Delete Bookmarks, REQ_503_21/22).
/// The bookmarked *entity* itself (attraction/restaurant details) is owned
/// by another module's own tables. [itemId] is optional because a bookmark
/// may instead be backed directly by [placeId] (for example Nearby, AR, or
/// AI Chat results resolved through Google Places).
class Bookmark {
  final String id;
  final String userId;
  final String? itemId;
  final String itemType;
  final String? placeId;
  final DateTime? createdAt;

  const Bookmark({
    required this.id,
    required this.userId,
    this.itemId,
    required this.itemType,
    this.placeId,
    this.createdAt,
  });
}
