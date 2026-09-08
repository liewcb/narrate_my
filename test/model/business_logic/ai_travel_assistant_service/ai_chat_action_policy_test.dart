import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/business_logic/ai_travel_assistant_service/ai_chat_action_policy.dart';

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
}
