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