/// Domain entity for UC402 A22 (View and Delete Bookmarks, REQ_503_21/22).
/// The bookmarked *entity* itself (attraction/restaurant details) is owned
/// by the Recommendation Engine module's own tables — [itemId] is a plain
/// FK reference, not resolved/joined here.
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