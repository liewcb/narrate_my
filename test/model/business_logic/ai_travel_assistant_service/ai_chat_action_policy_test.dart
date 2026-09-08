import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/business_logic/ai_travel_assistant_service/ai_chat_action_policy.dart';
import 'package:narrate_my/model/entities/ai_attraction_context.dart';

void main() {
  test('where contractions and full wording produce the same map target', () {
    expect(
      AiChatActionPolicy.mapDestinationFromQuestion("Where's KLCC?"),
      'KLCC',
    );
    expect(
      AiChatActionPolicy.mapDestinationFromQuestion('Where is KLCC?'),
      'KLCC',
    );
  });

  test('relative nearby requests require a real current location', () {
    expect(
      AiChatActionPolicy.requiresCurrentLocation('Any drinks near by me?'),
      isTrue,
    );
    expect(
      AiChatActionPolicy.requiresCurrentLocation('Any drinks near Setapak?'),
      isFalse,
    );
  });

  test('nearby scope distinguishes context, user, and named locations', () {
    expect(
      AiChatActionPolicy.nearbyScope('Show restaurants nearby'),
      AiNearbyScope.contextPlace,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Show nearby restaurants'),
      AiNearbyScope.contextPlace,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Show restaurants nearby here'),
      AiNearbyScope.contextPlace,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Any restaurants nearby this place?'),
      AiNearbyScope.contextPlace,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Show restaurants near by me'),
      AiNearbyScope.userCurrentLocation,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Show restaurants nearby my location'),
      AiNearbyScope.userCurrentLocation,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Show restaurants nearby KLCC'),
      AiNearbyScope.none,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Any recommended restaurants?'),
      AiNearbyScope.contextPlace,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Suggest some popular cafes'),
      AiNearbyScope.contextPlace,
    );
    expect(
      AiChatActionPolicy.nearbyScope(
        'Any suggestions on restaurant for me for my dinner tonight',
      ),
      AiNearbyScope.contextPlace,
    );
  });

  test('Malay place, map, and nearby wording uses the action policy', () {
    expect(
      AiChatActionPolicy.mapDestinationFromQuestion('Di mana Suria KLCC?'),
      'Suria KLCC',
    );
    expect(
      AiChatActionPolicy.nearbyScope('Cadangkan restoran berdekatan saya'),
      AiNearbyScope.userCurrentLocation,
    );
    expect(
      AiChatActionPolicy.nearbyScope('Cadangkan restoran berdekatan sini'),
      AiNearbyScope.contextPlace,
    );
  });

  test('Mandarin place, map, and nearby wording uses the action policy', () {
    expect(
      AiChatActionPolicy.mapDestinationFromQuestion('Suria KLCC在哪里？'),
      'Suria KLCC',
    );
    expect(
      AiChatActionPolicy.nearbyScope('推荐我附近的餐厅'),
      AiNearbyScope.userCurrentLocation,
    );
    expect(
      AiChatActionPolicy.nearbyScope('推荐这附近的餐厅'),
      AiNearbyScope.contextPlace,
    );
  });

  test('go, Mandarin 去, and Malay pergi produce map destinations', () {
    expect(
      AiChatActionPolicy.mapDestinationFromQuestion(
        'I want to go to Suria KLCC',
      ),
      'Suria KLCC',
    );
    expect(
      AiChatActionPolicy.mapDestinationFromQuestion('我想去Suria KLCC'),
      'Suria KLCC',
    );
    expect(
      AiChatActionPolicy.mapDestinationFromQuestion(
        'Saya mahu pergi ke Suria KLCC',
      ),
      'Suria KLCC',
    );
  });

  test('short Mandarin this-place wording refers to active context', () {
    expect(
      AiChatActionPolicy.questionRefersToContext(
        '这地方好玩吗',
        const AiAttractionContext(
          attractionName: 'Sala Kuala Lumpur',
          placeId: 'sala-kl',
          source: 'recommendation',
        ),
      ),
      isTrue,
    );
  });

  test('menu and general food questions are information-only', () {
    for (final question in [
      'What food is available here?',
      'Any food I can eat?',
      '有什么食物',
      'Ada makanan apa?',
      '¿Qué comida hay?',
      'क्या खाना उपलब्ध है?',
    ]) {
      expect(
        AiChatActionPolicy.isFoodInformationOnly(question),
        isTrue,
        reason: question,
      );
    }

    expect(
      AiChatActionPolicy.isFoodInformationOnly('Recommend food nearby'),
      isFalse,
    );
  });
}
