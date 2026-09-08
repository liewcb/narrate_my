import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/localization/app_localizations.dart';
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
  String? lastQuestion;

  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async {
    callCount += 1;
    lastQuestion = question;
    lastHistory = List<AiChatMessage>.from(conversationHistory);
    if (question.startsWith('Summarize this conversation')) {
      return 'Updated conversation summary';
    }
    return 'Here is the answer about $question.';
  }
}

class _FakePlaceResolver implements AiBookmarkPlaceQuestionResolver {
  _FakePlaceResolver(this.result);

  final List<Place> result;
  Coordinates? receivedNearbyOrigin;
  int callCount = 0;

  @override
  Future<List<Place>> resolveQuestion(
    String question, {
    Coordinates? nearbyOrigin,
  }) async {
    callCount += 1;
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

class _CompleterRepository implements AiTravelAssistantRepository {
  _CompleterRepository(this.completer);

  final Completer<String> completer;

  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) => completer.future;
}

void main() {
  setUp(() => AppLocalizations.currentCode = 'en');
  tearDown(() => AppLocalizations.currentCode = 'en');

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
      Place? savedContextPlace;
      final vm = AiTravelAssistantViewModel(
        repository: _FakeRepository(),
        bookmarkPlaceResolver: _FakePlaceResolver(const [klcc]),
        initialContext: const AiAttractionContext(
          attractionName: 'Batu Caves',
          placeId: 'google-batu-caves',
          source: 'recommendation',
        ),
        initialBookmarkPlace: batuCaves,
        onContextPlaceResolved: (place) => savedContextPlace = place,
      );
      addTearDown(vm.dispose);

      await vm.sendQuestion('Tell me about KLCC');

      expect(vm.bookmarkCandidates, const [klcc]);
      expect(vm.attractionContext?.attractionName, 'Suria KLCC');
      expect(vm.contextBookmarkPlace, klcc);
      expect(savedContextPlace, klcc);
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

  test('dinner recommendation uses AR context coordinates', () async {
    final repository = _ContextRecordingRepository();
    final resolver = _FakePlaceResolver(const [restaurant]);
    const markerCoordinates = Coordinates(
      latitude: 3.2151,
      longitude: 101.7264,
    );
    final vm = AiTravelAssistantViewModel(
      repository: repository,
      bookmarkPlaceResolver: resolver,
      initialContext: const AiAttractionContext(
        attractionName: 'TAR UMT Block B',
        markerId: 'MK-TARUMT',
        latitude: 3.2151,
        longitude: 101.7264,
        source: 'ar_marker',
      ),
    );
    addTearDown(vm.dispose);

    await vm.sendQuestion(
      'Any suggestions on restaurant for me for my dinner tonight',
    );

    expect(resolver.receivedNearbyOrigin, markerCoordinates);
    expect(repository.receivedQuestion, contains(restaurant.placeName));
    expect(vm.bookmarkCandidates, const [restaurant]);
  });

  test(
    'bookmark and map actions remain attached to previous answers',
    () async {
      final vm = AiTravelAssistantViewModel(
        repository: _FakeRepository(),
        bookmarkPlaceResolver: _FakePlaceResolver(const [klcc]),
      );
      addTearDown(vm.dispose);

      await vm.sendQuestion('Where is KLCC?');
      final firstResponseIndex = vm.actionMessageIndex!;
      final firstActions = vm.actionsForMessage(firstResponseIndex);
      expect(firstActions?.bookmarkPlaces, const [klcc]);
      expect(firstActions?.mapDestination, 'KLCC');
      expect(firstActions?.mapPlace, klcc);

      await vm.sendQuestion('Tell me its history');

      final preservedActions = vm.actionsForMessage(firstResponseIndex);
      expect(preservedActions?.bookmarkPlaces, const [klcc]);
      expect(preservedActions?.mapDestination, 'KLCC');
      expect(preservedActions?.mapPlace, klcc);
    },
  );

  test(
    'an unrelated resolved candidate cannot override a map destination',
    () async {
      const unrelatedPlace = Place(
        placeId: 'ChIJ-unrelated-kiosk',
        placeName: 'KIOSK LEPAK SINI',
        placeAddress: 'Gombak',
        placeLatitude: 3.214,
        placeLongitude: 101.742,
        placeRating: 4.0,
        placeTypes: ['point_of_interest'],
      );
      final vm = AiTravelAssistantViewModel(
        repository: _FakeRepository(),
        bookmarkPlaceResolver: _FakePlaceResolver(const [unrelatedPlace]),
      );
      addTearDown(vm.dispose);

      await vm.sendQuestion('Where is Suria KLCC?');

      final actions = vm.actionsForMessage(vm.actionMessageIndex!);
      expect(actions?.mapDestination, 'Suria KLCC');
      expect(actions?.mapPlace, isNull);
    },
  );

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
      initialConversationSummaryLanguageCode: 'en',
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

  test('selected profile language controls greeting and AI response', () async {
    AppLocalizations.currentCode = 'zh';
    final repository = _ContextRecordingRepository();
    final vm = AiTravelAssistantViewModel(
      repository: repository,
      bookmarkPlaceResolver: _FakePlaceResolver(const []),
    );
    addTearDown(vm.dispose);

    expect(vm.messages.single.text, '我是 Manja，您的 AI 旅行助手！');

    await vm.sendQuestion('Tell me about Suria KLCC');

    expect(
      repository.receivedQuestion,
      startsWith('Reply in Mandarin Chinese.'),
    );
  });

  test(
    'mixed Mandarin wording saves the verified English place context',
    () async {
      Place? savedContext;
      final vm = AiTravelAssistantViewModel(
        repository: _FakeRepository(),
        bookmarkPlaceResolver: _FakePlaceResolver(const [klcc]),
        onContextPlaceResolved: (place) => savedContext = place,
      );
      addTearDown(vm.dispose);

      await vm.sendQuestion('我想去suria klcc');

      expect(vm.attractionContext?.attractionName, 'Suria KLCC');
      expect(vm.attractionContext?.placeId, 'google-klcc');
      expect(savedContext, klcc);
      expect(
        vm.actionsForMessage(vm.messages.length - 1)?.mapDestination,
        'suria klcc',
      );
    },
  );

  test('Mandarin this-place question shows the context bookmark', () async {
    final resolver = _FakePlaceResolver(const []);
    final vm = AiTravelAssistantViewModel(
      repository: _FakeRepository(),
      bookmarkPlaceResolver: resolver,
      initialContext: const AiAttractionContext(
        attractionName: 'Batu Caves',
        placeId: 'google-batu-caves',
        source: 'recommendation',
      ),
      initialBookmarkPlace: batuCaves,
    );
    addTearDown(vm.dispose);

    await vm.sendQuestion('这地方好玩吗');

    expect(resolver.callCount, 0);
    expect(vm.actionsForMessage(vm.messages.length - 1)?.bookmarkPlaces, const [
      batuCaves,
    ]);
  });

  test('food information questions never resolve bookmark cards', () async {
    for (final question in [
      'What food is available here?',
      'Any food I can eat?',
      '有什么食物',
      'Ada makanan apa?',
      '¿Qué comida hay?',
      'क्या खाना उपलब्ध है?',
    ]) {
      final resolver = _FakePlaceResolver(const [restaurant]);
      final vm = AiTravelAssistantViewModel(
        repository: _FakeRepository(),
        bookmarkPlaceResolver: resolver,
        initialContext: const AiAttractionContext(
          attractionName: 'Batu Caves',
          placeId: 'google-batu-caves',
          source: 'recommendation',
        ),
        initialBookmarkPlace: batuCaves,
      );

      await vm.sendQuestion(question);

      expect(resolver.callCount, 0, reason: question);
      expect(vm.bookmarkCandidates, isEmpty, reason: question);
      expect(
        vm.actionsForMessage(vm.messages.length - 1),
        isNull,
        reason: question,
      );
      vm.dispose();
    }
  });

  test(
    'logout clear removes local state and ignores a pending answer',
    () async {
      final answer = Completer<String>();
      final vm = AiTravelAssistantViewModel(
        repository: _CompleterRepository(answer),
        bookmarkPlaceResolver: _FakePlaceResolver(const []),
        initialContext: const AiAttractionContext(
          attractionName: 'Royal Selangor Visitor Centre',
          placeId: 'royal-selangor',
          source: 'recommendation',
        ),
        initialBookmarkPlace: batuCaves,
        initialConversationSummary: 'Old account summary',
        initialConversationSummaryLanguageCode: 'en',
        resolveBookmarkPlacesFromQuestions: false,
      );
      addTearDown(vm.dispose);

      final pendingRequest = vm.sendQuestion('How do I get there?');
      expect(vm.isSending, isTrue);
      vm.clearSessionState();
      answer.complete('Stale answer from the old session');
      await pendingRequest;

      expect(vm.attractionContext, isNull);
      expect(vm.contextBookmarkPlace, isNull);
      expect(vm.conversationSummary, isNull);
      expect(vm.messages, hasLength(1));
      expect(vm.isSending, isFalse);
    },
  );

  test('logout clear ignores a pending summary response', () async {
    final summary = Completer<String>();
    final vm = AiTravelAssistantViewModel(
      repository: _CompleterRepository(summary),
      bookmarkPlaceResolver: _FakePlaceResolver(const []),
      initialContext: const AiAttractionContext(
        attractionName: 'Royal Selangor Visitor Centre',
        source: 'recommendation',
      ),
      initialConversationSummary: 'Old account summary',
      initialConversationSummaryLanguageCode: 'zh',
      resolveBookmarkPlacesFromQuestions: false,
    );
    addTearDown(vm.dispose);

    final pendingSummary = vm.generateSummary();
    expect(vm.isSummarizing, isTrue);
    vm.clearSessionState();
    summary.complete('Stale refreshed summary');
    await pendingSummary;

    expect(vm.attractionContext, isNull);
    expect(vm.conversationSummary, isNull);
    expect(vm.messages, hasLength(1));
    expect(vm.isSummarizing, isFalse);
  });

  test('saved summary refreshes in the newly selected language', () async {
    AppLocalizations.currentCode = 'ms';
    final repository = _SummaryRepository();
    final vm = AiTravelAssistantViewModel(
      repository: repository,
      bookmarkPlaceResolver: _FakePlaceResolver(const []),
      initialConversationSummary: 'An English summary',
      initialConversationSummaryLanguageCode: 'en',
      resolveBookmarkPlacesFromQuestions: false,
    );
    addTearDown(vm.dispose);

    await vm.generateSummary();

    expect(repository.callCount, 1);
    expect(repository.lastQuestion, contains('Write in Malay'));
    expect(vm.conversationSummaryLanguageCode, 'ms');
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
