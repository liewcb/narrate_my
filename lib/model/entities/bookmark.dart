class Bookmark {
  final String id;
  final String userId;
  final String itemId;
  final String itemType;
  final DateTime createdAt;
  final String? placeId;

  const Bookmark({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.itemType,
    required this.createdAt,
    this.placeId,
  });
}