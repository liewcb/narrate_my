/// Domain entity for UC402 A22 (View and Delete Bookmarks, REQ_503_21/22).
/// The bookmarked *entity* itself (attraction/restaurant details) is owned
/// by the Recommendation Engine module's own tables — [itemId] is a plain
/// FK reference, not resolved/joined here.
class Bookmark {
  final String id;
  final String itemId;
  final String itemType; // e.g. 'attraction' | 'restaurant'
  final DateTime? createdAt;

  const Bookmark({
    required this.id,
    required this.itemId,
    required this.itemType,
    this.createdAt,
  });
}
