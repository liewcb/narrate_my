import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/business_logic/ai_travel_assistant_service/ai_bookmark_place_resolver.dart';
import 'package:narrate_my/model/entities/ai_attraction_context.dart';
import 'package:narrate_my/model/entities/ai_chat_message.dart';
import 'package:narrate_my/model/entities/coordinates.dart';
import 'package:narrate_my/model/entities/place.dart';
import 'package:narrate_my/model/repositories/interfaces/ai_assist/ai_travel_assistant_repository.dart';
import 'package:narrate_my/viewmodel/ai_assistant/ai_travel_assistant_vm.dart';

class _FakeRepository implements AiTravelAssistantRepository {
  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async => 'Here is the answer about $question.';
}

class _SummaryRepository implements AiTravelAssistantRepository {
  int callCount = 0;
  List<AiChatMessage> lastHistory = const [];

  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async {
    callCount += 1;
    lastHistory = List<AiChatMessage>.from(conversationHistory);
    if (question.startsWith('Update the saved travel summary')) {
      return 'Updated conversation summary';
    }
    return 'Here is the answer about $question.';
  }
}

class _FakePlaceResolver implements AiBookmarkPlaceQuestionResolver {
  _FakePlaceResolver(this.result);

  final List<Place> result;
  Coordinates? receivedNearbyOrigin;

  @override
  Future<List<Place>> resolveQuestion(
    String question, {
    Coordinates? nearbyOrigin,
  }) async {
    receivedNearbyOrigin = nearbyOrigin;
    return result;
  }
}

class _ContextRecordingRepository implements AiTravelAssistantRepository {
  AiAttractionContext? receivedContext;
  String? receivedQuestion;

  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async {
    receivedContext = attractionContext;
    receivedQuestion = question;
    return 'Scoped answer';
  }
}

class _FailingRepository implements AiTravelAssistantRepository {
  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) => throw Exception('AI request failed');
}

void main() {
  const batuCaves = Place(
    placeId: 'google-batu-caves',
    placeName: 'Batu Caves',
    placeAddress: 'Gombak',
    placeLatitude: 3.2379,
    placeLongitude: 101.684,
    placeRating: 4.6,
    placeTypes: ['tourist_attraction'],
  );
  const klcc = Place(
    placeId: 'google-klcc',
    placeName: 'Suria KLCC',
    placeAddress: 'Kuala Lumpur City Centre',
    placeLatitude: 3.1579,
    placeLongitude: 101.7123,
    placeRating: 4.6,
    placeTypes: ['shopping_mall', 'tourist_attraction'],
  );
  const restaurant = Place(
    placeId: 'google-restaurant',
    placeName: 'Setapak Garden Restaurant',
    placeAddress: 'Setapak',
    placeLatitude: 3.2,
    placeLongitude: 101.71,
    placeRating: 4.3,
    placeTypes: ['restaurant', 'food'],
  );

  test(
    'a new question resolves actions even when chat has initial context',
    () async {
      final vm = AiTravelAssistantViewModel(
        repository: _FakeRepository(),
        bookmarkPlaceResolver: _FakePlaceResolver(const [klcc]),
        initialContext: const AiAttractionContext(
          attractionName: 'Batu Caves',
          placeId: 'google-batu-caves',
          source: 'recommendation',
        ),
        initialBookmarkPlace: batuCaves,
      );
      addTearDown(vm.dispose);

      await vm.sendQuestion('Tell me about KLCC');

      expect(vm.bookmarkCandidates, const [klcc]);
      expect(vm.attractionContext?.attractionName, 'Suria KLCC');
      expect(vm.contextBookmarkPlace, klcc);
    },
  );

  test('a resolved restaurant can replace the current place context', () async {
    final vm = AiTravelAssistantViewModel(
      repository: _FakeRepository(),
      bookmarkPlaceResolver: _FakePlaceResolver(const [restaurant]),
    );
    addTearDown(vm.dispose);

    await vm.sendQuestion('Tell me about Setapak Garden Restaurant');

    expect(vm.attractionContext?.attractionName, restaurant.placeName);
    expect(vm.attractionContext?.placeId, restaurant.placeId);
    expect(vm.contextBookmarkPlace, restaurant);
  });

  test('nearby me uses GPS instead of the selected place', () async {
    final repository = _ContextRecordingRepository();
    final resolver = _FakePlaceResolver(const [restaurant]);
    const userLocation = Coordinates(latitude: 5.4141, longitude: 100.3288);
    final vm = AiTravelAssistantViewModel(
      repository: repository,
      bookmarkPlaceResolver: resolver,
      initialContext: const AiAttractionContext(
        attractionName: 'Suria KLCC',
        placeId: 'google-klcc',
        source: 'recommendation',
      ),
      initialBookmarkPlace: klcc,
      currentLocationLoader: () async => userLocation,
    );
    addTearDown(vm.dispose);

    await vm.sendQuestion('Show me restaurants nearby me');

    expect(resolver.receivedNearbyOrigin, userLocation);
    expect(repository.receivedContext, isNull);
    expect(repository.receivedQuestion, contains('5.41410'));
    expect(repository.receivedQuestion, contains('Ignore any selected'));
    expect(repository.receivedQuestion, contains(restaurant.placeName));
    expect(vm.attractionContext?.attractionName, 'Suria KLCC');
  });

  test('plain nearby uses the selected place coordinates', () async {
    final repository = _ContextRecordingRepository();
    final resolver = _FakePlaceResolver(const [restaurant]);
    var gpsLoadCount = 0;
    final vm = AiTravelAssistantViewModel(
      repository: repository,
      bookmarkPlaceResolver: resolver,
      initialContext: const AiAttractionContext(
        attractionName: 'Suria KLCC',
        placeId: 'google-klcc',
        source: 'recommendation',
      ),
      initialBookmarkPlace: klcc,
      currentLocationLoader: () async {
        gpsLoadCount += 1;
        return const Coordinates(latitude: 5.4141, longitude: 100.3288);
      },
    );
    addTearDown(vm.dispose);

    await vm.sendQuestion('Show me restaurants nearby here');

    expect(resolver.receivedNearbyOrigin, klcc.coordinates);
    expect(repository.receivedContext?.attractionName, 'Suria KLCC');
    expect(
      repository.receivedQuestion,
      contains('selected place "Suria KLCC"'),
    );
    expect(repository.receivedQuestion, contains(restaurant.placeName));
    expect(gpsLoadCount, 0);
    expect(vm.attractionContext?.attractionName, 'Suria KLCC');
  });

  test('recommended restaurants use verified nearby context results', () async {
    final repository = _ContextRecordingRepository();
    final resolver = _FakePlaceResolver(const [restaurant]);
    final vm = AiTravelAssistantViewModel(
      repository: repository,
      bookmarkPlaceResolver: resolver,
      initialContext: const AiAttractionContext(
        attractionName: 'Suria KLCC',
        placeId: 'google-klcc',
        source: 'recommendation',
      ),
      initialBookmarkPlace: klcc,
    );
    addTearDown(vm.dispose);

    await vm.sendQuestion('Any recommended restaurants?');

    expect(resolver.receivedNearbyOrigin, klcc.coordinates);
    expect(repository.receivedQuestion, contains(restaurant.placeName));
    expect(vm.bookmarkCandidates, const [restaurant]);
  });

  test(
    'failed answer does not attach resolved places to an older reply',
    () async {
      final vm = AiTravelAssistantViewModel(
        repository: _FailingRepository(),
        bookmarkPlaceResolver: _FakePlaceResolver(const [restaurant]),
        initialContext: const AiAttractionContext(
          attractionName: 'A Famosa',
          placeId: 'a-famosa',
          source: 'recommendation',
        ),
        initialBookmarkPlace: batuCaves,
        currentLocationLoader: () async =>
            const Coordinates(latitude: 3.201, longitude: 101.72),
      );
      addTearDown(vm.dispose);

      await vm.sendQuestion('Suggest some restaurants nearby me');

      expect(vm.bookmarkCandidates, isEmpty);
      expect(vm.actionMessageIndex, isNull);
      expect(vm.actionQuestion, isNull);
      expect(vm.messages.last.sender, AiChatMessageSender.system);
    },
  );

  test('saved summary stays until newer chat is summarized', () async {
    final repository = _SummaryRepository();
    final vm = AiTravelAssistantViewModel(
      repository: repository,
      bookmarkPlaceResolver: _FakePlaceResolver(const []),
      initialConversationSummary: 'Previous conversation summary',
      resolveBookmarkPlacesFromQuestions: false,
    );
    addTearDown(vm.dispose);

    await vm.generateSummary();
    expect(repository.callCount, 0);
    expect(vm.conversationSummary, 'Previous conversation summary');

    await vm.sendQuestion('What should I visit next?');
    expect(vm.conversationSummary, 'Previous conversation summary');
    expect(vm.summaryNeedsRefresh, isTrue);

    await vm.generateSummary();
    expect(vm.conversationSummary, 'Updated conversation summary');
    expect(vm.summaryNeedsRefresh, isFalse);
    expect(
      repository.lastHistory.any(
        (message) =>
            message.sender == AiChatMessageSender.system &&
            message.text.contains('Previous conversation summary'),
      ),
      isTrue,
    );
  });

  test(
    'reset clears messages but keeps the latest attraction context',
    () async {
      final vm = AiTravelAssistantViewModel(
        repository: _FakeRepository(),
        bookmarkPlaceResolver: _FakePlaceResolver(const [klcc]),
        initialContext: const AiAttractionContext(
          attractionName: 'Batu Caves',
          placeId: 'google-batu-caves',
          source: 'recommendation',
        ),
        initialBookmarkPlace: batuCaves,
      );
      addTearDown(vm.dispose);

      await vm.sendQuestion('Tell me about KLCC');
      vm.resetConversation();

      expect(vm.attractionContext?.attractionName, 'Suria KLCC');
      expect(vm.contextBookmarkPlace, klcc);
      expect(vm.bookmarkCandidates, isEmpty);
      expect(vm.conversationSummary, isNull);
      expect(
        vm.messages.where(
          (message) => message.sender == AiChatMessageSender.tourist,
        ),
        isEmpty,
      );
    },
  );
}
