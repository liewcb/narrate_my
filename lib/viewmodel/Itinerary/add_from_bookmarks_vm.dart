import 'package:flutter/foundation.dart';
import '../../core/services/database_manager.dart';
import '../../model/dto/bookmark_with_place_dto.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/interfaces/bookmark/bookmark_repository.dart';

class AddFromBookmarksViewModel extends ChangeNotifier {
  final BookmarkRepository _repo;
  final String userId;
  final List<String> destinationNames;
  List<BookmarkWithPlaceDTO> _bookmarks = [];
  final Set<String> _selectedIds = {};
  String _query = '';
  bool isLoading = false;
  String? error;
  bool _disposed = false;

  AddFromBookmarksViewModel({String? userId, this.destinationNames = const [], BookmarkRepository? repository})
      : _repo = repository ?? DatabaseManager().bookmarkRepository,
        userId = userId ?? (repository ?? DatabaseManager().bookmarkRepository).currentUserId ?? '';

  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final all = userId.isEmpty ? <BookmarkWithPlaceDTO>[] : await _repo.getBookmarksWithPlaces(userId);
      if (_disposed) return;
      _bookmarks = all.where((dto) {
        final text = '${dto.place.placeAddress} ${dto.place.placeName}'.toLowerCase();
        return destinationNames.isEmpty || destinationNames.any((name) => text.contains(name.toLowerCase()));
      }).toList();
      _selectedIds.retainAll(_bookmarks.map((dto) => dto.place.placeId));
    } catch (_) {
      if (_disposed) return;
      error = 'Could not load bookmarks. Please try again.';
    } finally {
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setQuery(String query) { _query = query.trim().toLowerCase(); notifyListeners(); }
  List<BookmarkWithPlaceDTO> get bookmarks => List.unmodifiable(_bookmarks.where((dto) =>
      '${dto.place.placeName} ${dto.place.placeAddress}'.toLowerCase().contains(_query)));
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool isSelected(String id) => _selectedIds.contains(id);
  void toggleSelection(String id) {
    if (!_bookmarks.any((dto) => dto.place.placeId == id)) return;
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
    notifyListeners();
  }
  List<Place> getSelectedPlaces() => _bookmarks.where((dto) => _selectedIds.contains(dto.place.placeId)).map((dto) => dto.place).toList();
  @override
  void dispose() { _disposed = true; super.dispose(); }
}
