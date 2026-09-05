import 'package:flutter/foundation.dart';

import '../../model/dto/bookmark_with_place_dto.dart';
import '../../model/repositories/adapters/bookmark_repository_adapter.dart';
import '../../model/repositories/interfaces/bookmark_repository.dart';

/// Backs UC402 A22 (View and Delete Bookmarks, REQ_503_21/22).
///
/// NOTE (2 Sep): this is the version that used to live at
/// `viewmodel/profile_viewmodel/bookmarks_vm.dart`, moved here verbatim.
/// The copy that was previously at THIS path was an older, thinner one that
/// returned bare `Bookmark` entities via `ProfileRepository` — it had no
/// place/attraction join, so `bookmarks_screen.dart`'s `entry.bookmark` /
/// `entry.place` didn't compile against it. The `profile_viewmodel/` copy
/// was the maintained one (it goes through `BookmarkRepository` and returns
/// `BookmarkWithPlaceDTO`), so it wins. Import paths are unchanged: both
/// folders sit at the same depth under `lib/viewmodel/`, so every `../../`
/// still resolves the same way.
class BookmarksVm extends ChangeNotifier {
  final BookmarkRepository _bookmarkRepository;

  BookmarksVm({BookmarkRepository? bookmarkRepository})
    : _bookmarkRepository = bookmarkRepository ?? BookmarkRepositoryImpl();

  List<BookmarkWithPlaceDTO> bookmarks = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final userId = _bookmarkRepository.currentUserId;
      if (userId == null) {
        bookmarks = [];
        errorMessage = 'Log in to view your bookmarks.';
        return;
      }
      bookmarks = await _bookmarkRepository.getBookmarksWithPlaces(userId);
    } catch (error) {
      debugPrint('Unable to load bookmarks: $error');
      errorMessage = 'Unable to load bookmarks. Please try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// A22 steps 5–7: remove, then refresh the list.
  Future<void> remove(String bookmarkId) async {
    try {
      await _bookmarkRepository.removeBookmark(bookmarkId);
      bookmarks = bookmarks
          .where((entry) => entry.bookmark.id != bookmarkId)
          .toList();
      notifyListeners();
    } catch (error) {
      debugPrint('Unable to remove bookmark: $error');
      errorMessage = 'Unable to remove this bookmark. Please try again.';
      notifyListeners();
    }
  }
}
