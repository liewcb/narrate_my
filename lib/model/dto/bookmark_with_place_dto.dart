

import '../entities/bookmark.dart';
import '../entities/place.dart';

class BookmarkWithPlaceDTO {
  final Bookmark bookmark;
  final Place place;

  const BookmarkWithPlaceDTO({required this.bookmark, required this.place});
}