import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/business_logic/shared_services/place_bookmark_service.dart';
import 'package:narrate_my/model/dto/bookmark_with_place_dto.dart';
import 'package:narrate_my/model/entities/bookmark.dart';
import 'package:narrate_my/model/entities/place.dart';
import 'package:narrate_my/model/repositories/interfaces/bookmark_repository.dart';
import 'package:narrate_my/viewmodel/bookmark_vm.dart';

class _FakeBookmarkRepository implements BookmarkRepository {
  @override
  String? currentUserId;

  bool bookmarked = false;
  bool addCreatesRow = true;
  Object? error;
  int addCalls = 0;
  int removeCalls = 0;

  _FakeBookmarkRepository({this.currentUserId});

  @override
  Future<bool> addPlaceBookmark(Place place, {required String itemType}) async {
    addCalls += 1;
    if (error case final error?) throw error;
    bookmarked = true;
    return addCreatesRow;
  }

  @override
  Future<bool> isBookmarked(String userId, String googlePlaceId) async {
    if (error case final error?) throw error;
    return bookmarked;
  }

  @override
  Future<Bookmark?> getPlaceBookmark(
    String userId,
    String googlePlaceId,
  ) async {
    if (error case final error?) throw error;
    if (!bookmarked) return null;
    return Bookmark(
      id: 'bookmark-1',
      userId: userId,
      itemType: 'attraction',
      placeId: 'place-internal-1',
    );
  }

  @override
  Future<void> addBookmark(Bookmark bookmark) async {}

  @override
  Future<List<BookmarkWithPlaceDTO>> getBookmarksWithPlaces(
    String userId,
  ) async {
    return [];
  }

  @override
  Future<void> removeBookmark(String bookmarkId) async {
    removeCalls += 1;
    if (error case final error?) throw error;
    bookmarked = false;
  }
}

const _place = Place(
  placeId: 'ChIJ-test-place',
  placeName: 'Test Attraction',
  placeAddress: 'Kuala Lumpur',
  placeLatitude: 3.139,
  placeLongitude: 101.6869,
  placeRating: 4.5,
  placeTypes: ['museum'],
  category: 'Museum',
);

BookmarkVm _viewModel(_FakeBookmarkRepository repository) {
  return BookmarkVm(service: PlaceBookmarkService(repository: repository));
}

void main() {
  group('BookmarkVm', () {
    test('keeps a pending bookmark when login is required', () async {
      final repository = _FakeBookmarkRepository();
      final viewModel = _viewModel(repository);

      final result = await viewModel.bookmark(_place, itemType: 'attraction');

      expect(result, BookmarkResult.loginRequired);
      expect(viewModel.hasPendingBookmark, isTrue);
      expect(repository.addCalls, 0);
    });

    test('retries the pending bookmark after successful login', () async {
      final repository = _FakeBookmarkRepository();
      final viewModel = _viewModel(repository);
      await viewModel.bookmark(_place, itemType: 'attraction');

      repository.currentUserId = 'user-1';
      final result = await viewModel.retryPendingBookmark();

      expect(result, BookmarkResult.added);
      expect(viewModel.hasPendingBookmark, isFalse);
      expect(viewModel.isBookmarked, isTrue);
      expect(repository.addCalls, 1);
    });

    test('loads an existing bookmark from the shared repository', () async {
      final repository = _FakeBookmarkRepository(currentUserId: 'user-1')
        ..bookmarked = true;
      final viewModel = _viewModel(repository);

      await viewModel.load(_place.placeId);

      expect(viewModel.isBookmarked, isTrue);
      expect(viewModel.isChecking, isFalse);
    });

    test('tapping a bookmarked place removes it', () async {
      final repository = _FakeBookmarkRepository(currentUserId: 'user-1')
        ..bookmarked = true;
      final viewModel = _viewModel(repository);
      await viewModel.load(_place.placeId);

      final result = await viewModel.toggleBookmark(
        _place,
        itemType: 'attraction',
      );

      expect(result, BookmarkResult.removed);
      expect(viewModel.isBookmarked, isFalse);
      expect(viewModel.statusMessage, 'Bookmark removed.');
      expect(repository.removeCalls, 1);
    });

    test('treats a database duplicate as already bookmarked', () async {
      final repository = _FakeBookmarkRepository(currentUserId: 'user-1')
        ..addCreatesRow = false;
      final viewModel = _viewModel(repository);

      final result = await viewModel.bookmark(_place, itemType: 'attraction');

      expect(result, BookmarkResult.alreadyBookmarked);
      expect(viewModel.isBookmarked, isTrue);
    });

    test('reports a friendly message when the remote write fails', () async {
      final repository = _FakeBookmarkRepository(currentUserId: 'user-1')
        ..error = Exception('database unavailable');
      final viewModel = _viewModel(repository);

      final result = await viewModel.bookmark(_place, itemType: 'attraction');

      expect(result, BookmarkResult.failed);
      expect(viewModel.isBookmarked, isFalse);
      expect(viewModel.errorMessage, contains('Unable to bookmark'));
    });
  });
}
