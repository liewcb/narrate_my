import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/entities/bookmark.dart';
import 'package:narrate_my/model/entities/place.dart';
import 'package:narrate_my/model/entities/coordinates.dart';
import 'package:narrate_my/model/dto/bookmark_with_place_dto.dart';
import 'package:narrate_my/model/repositories/interfaces/bookmark/bookmark_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/ai_assist/ai_place_repository.dart';
import 'package:narrate_my/model/business_logic/ai_travel_assistant_service/ai_bookmark_place_resolver.dart';
import 'package:narrate_my/viewmodel/Itinerary/add_from_bookmarks_vm.dart';

const museum = Place(placeId:'museum',placeName:'National Museum',placeAddress:'Kuala Lumpur',
    placeLatitude:3.137,placeLongitude:101.687,placeRating:4.5,placeTypes:['museum']);
const cafe = Place(placeId:'cafe',placeName:'Cafe',placeAddress:'Penang',
    placeLatitude:5.41,placeLongitude:100.33,placeRating:4.5,placeTypes:['cafe']);

class FakeBookmarks implements BookmarkRepository {
  @override
  String? currentUserId = 'signed-in-user';
  String? requestedUser;
  bool shouldFail = false;
  @override
  Future<List<BookmarkWithPlaceDTO>> getBookmarksWithPlaces(String userId) async {
    requestedUser = userId;
    if (shouldFail) throw StateError('offline');
    return [for (final place in [museum,cafe]) BookmarkWithPlaceDTO(
      bookmark:Bookmark(id:place.placeId,userId:userId,itemType:'place'),place:place)];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAiPlaces implements AiPlaceRepository {
  bool nearbyCalled = false;
  @override
  Future<List<Place>> fetchBookmarkablePlaces() async => [museum];
  @override
  Future<List<Place>> searchTextPlaces({required String query}) async => [museum];
  @override
  Future<List<Place>> searchNearbyPlaces({required Coordinates origin,
    required List<String> includedTypes,required double radiusKm}) async {
    nearbyCalled = true;
    return [museum];
  }
}

void main() {
  test('bookmarks ViewModel resolves the current user and filters destination',() async {
    final repository=FakeBookmarks();
    final vm=AddFromBookmarksViewModel(repository:repository,destinationNames:['Kuala Lumpur']);
    await vm.load();
    expect(repository.requestedUser,'signed-in-user');
    expect(vm.bookmarks.map((entry)=>entry.place.placeId),['museum']);
    vm.toggleSelection('museum');
    expect(vm.getSelectedPlaces(),[museum]);
    vm.dispose();
  });
  test('bookmark search preserves selections and rejects unknown ids',() async {
    final vm=AddFromBookmarksViewModel(repository:FakeBookmarks());
    await vm.load();
    vm.toggleSelection('museum');
    vm.toggleSelection('unknown');
    vm.setQuery('penang');
    expect(vm.bookmarks.map((entry)=>entry.place.placeId),['cafe']);
    expect(vm.selectedIds,{'museum'});
    vm.dispose();
  });
  test('bookmark load failures have a retryable error',() async {
    final repository=FakeBookmarks()..shouldFail=true;
    final vm=AddFromBookmarksViewModel(repository:repository);
    await vm.load();
    expect(vm.error,isNotNull);
    expect(vm.isLoading,isFalse);
    repository.shouldFail=false;
    await vm.load();
    expect(vm.error,isNull);
    expect(vm.bookmarks.length,2);
    vm.dispose();
  });
  test('guest bookmark view makes no authenticated request',() async {
    final repository=FakeBookmarks()..currentUserId=null;
    final vm=AddFromBookmarksViewModel(repository:repository);
    await vm.load();
    expect(repository.requestedUser,isNull);
    expect(vm.bookmarks,isEmpty);
    vm.dispose();
  });
  test('AI resolver uses the injected repository for nearby discovery',() async {
    final repository=FakeAiPlaces();
    final resolver=AiBookmarkPlaceResolver(repository:repository);
    final result=await resolver.resolveQuestion('museums near me',
      nearbyOrigin:const Coordinates(latitude:3.137,longitude:101.687));
    expect(repository.nearbyCalled,isTrue);
    expect(result,[museum]);
  });
}
