import 'package:flutter/cupertino.dart';
import '../../model/dto/bookmark_with_place_dto.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/bookmark_repository_adapter.dart';
import '../../model/repositories/interfaces/bookmark_repository.dart';

class AddFromBookmarksViewModel extends ChangeNotifier {
  final BookmarkRepository _repo = BookmarkRepositoryImpl();
  final String userId;

  List<BookmarkWithPlaceDTO> _bookmarks = [];
  Set<String> _selectedIds = {};

  AddFromBookmarksViewModel({required this.userId});

  Future<void> load() async {
    _bookmarks = await _repo.getBookmarksWithPlaces(userId);
    notifyListeners();
  }

  List<BookmarkWithPlaceDTO> get bookmarks => List.unmodifiable(_bookmarks);

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);

  bool isSelected(String placeId) => _selectedIds.contains(placeId);

  void toggleSelection(String placeId) {
    if (_selectedIds.contains(placeId)) {
      _selectedIds.remove(placeId);
    } else {
      _selectedIds.add(placeId);
    }
    notifyListeners();
  }

  List<Place> getSelectedPlaces() {
    return _bookmarks
        .where((dto) => _selectedIds.contains(dto.place.placeId))
        .map((dto) => dto.place)
        .toList();
  }
}
