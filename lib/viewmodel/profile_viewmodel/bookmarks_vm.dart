import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/entities/bookmark.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs UC402 A22 (View and Delete Bookmarks, REQ_503_21/22).
class BookmarksVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  BookmarksVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    load();
  }

  List<Bookmark> bookmarks = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      bookmarks = await _profileRepository.fetchBookmarks();
    } on AuthFailure catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// A22 steps 5–7: remove, then refresh the list.
  Future<void> remove(String bookmarkId) async {
    try {
      await _profileRepository.removeBookmark(bookmarkId);
      bookmarks = bookmarks.where((b) => b.id != bookmarkId).toList();
      notifyListeners();
    } on AuthFailure catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }
}
