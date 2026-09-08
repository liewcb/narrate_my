import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/localization/app_localizations.dart';
import 'package:narrate_my/model/business_logic/shared_services/place_bookmark_service.dart';
import 'package:narrate_my/model/dto/bookmark_with_place_dto.dart';
import 'package:narrate_my/model/entities/bookmark.dart';
import 'package:narrate_my/model/entities/place.dart';
import 'package:narrate_my/model/repositories/interfaces/bookmark/bookmark_repository.dart';
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
    test(
      'localizes bookmark add and remove messages in every supported language',
      () async {
        final originalLanguage = AppLocalizations.currentCode;
        addTearDown(() => AppLocalizations.currentCode = originalLanguage);
        const expectedMessages = <String, List<String>>{
          'en': ['Attraction added to bookmarks.', 'Bookmark removed.'],
          'zh': ['景点已添加到收藏夹。', '已从收藏夹移除。'],
          'ms': [
            'Tarikan telah ditambahkan pada penanda buku.',
            'Penanda buku telah dialih keluar.',
          ],
          'es': ['Atracción añadida a marcadores.', 'Marcador eliminado.'],
          'hi': [
            'आकर्षण को बुकमार्क में जोड़ दिया गया है।',
            'बुकमार्क हटा दिया गया है।',
          ],
        };

        for (final entry in expectedMessages.entries) {
          AppLocalizations.currentCode = entry.key;
          final repository = _FakeBookmarkRepository(currentUserId: 'user-1');
          final viewModel = _viewModel(repository);

          final result = await viewModel.bookmark(
            _place,
            itemType: 'attraction',
          );

          expect(result, BookmarkResult.added, reason: entry.key);
          expect(viewModel.statusMessage, entry.value[0], reason: entry.key);

          final removeResult = await viewModel.toggleBookmark(
            _place,
            itemType: 'attraction',
          );

          expect(removeResult, BookmarkResult.removed, reason: entry.key);
          expect(viewModel.statusMessage, entry.value[1], reason: entry.key);
        }
      },
    );

    test('localizes every bookmark status in Malay', () async {
      final originalLanguage = AppLocalizations.currentCode;
      AppLocalizations.currentCode = 'ms';
      addTearDown(() => AppLocalizations.currentCode = originalLanguage);

      final duplicateRepository = _FakeBookmarkRepository(
        currentUserId: 'user-1',
      )..addCreatesRow = false;
      final duplicateViewModel = _viewModel(duplicateRepository);
      await duplicateViewModel.bookmark(_place, itemType: 'attraction');
      expect(duplicateViewModel.statusMessage, 'Tarikan ini sudah ditandai.');

      final addFailureRepository = _FakeBookmarkRepository(
        currentUserId: 'user-1',
      )..error = Exception('database unavailable');
      final addFailureViewModel = _viewModel(addFailureRepository);
      await addFailureViewModel.bookmark(_place, itemType: 'attraction');
      expect(
        addFailureViewModel.statusMessage,
        'Tidak dapat menandai tempat ini. Sila cuba lagi.',
      );

      final checkFailureViewModel = _viewModel(addFailureRepository);
      await checkFailureViewModel.load(_place.placeId);
      expect(
        checkFailureViewModel.errorMessage,
        'Tidak dapat menyemak status penanda buku.',
      );

      final removeFailureRepository = _FakeBookmarkRepository(
        currentUserId: 'user-1',
      )..bookmarked = true;
      final removeFailureViewModel = _viewModel(removeFailureRepository);
      await removeFailureViewModel.load(_place.placeId);
      removeFailureRepository.error = Exception('database unavailable');
      await removeFailureViewModel.toggleBookmark(
        _place,
        itemType: 'attraction',
      );
      expect(
        removeFailureViewModel.statusMessage,
        'Tidak dapat mengalih keluar penanda buku ini. Sila cuba lagi.',
      );
    });

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
