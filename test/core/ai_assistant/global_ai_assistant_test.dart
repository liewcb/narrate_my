import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/ai_assistant/global_ai_assistant.dart';
import 'package:narrate_my/model/entities/place.dart';
import 'package:provider/provider.dart';

void main() {
  Place attraction(String id, String name) => Place(
    id: id,
    placeId: 'google-$id',
    placeName: name,
    placeAddress: 'Kuala Lumpur',
    placeLatitude: 3.1,
    placeLongitude: 101.7,
    placeRating: 4.5,
    placeTypes: const ['tourist_attraction'],
    category: 'landmark',
  );

  test('latest attraction replaces the previous AI context', () {
    final controller = GlobalAiAssistantController();
    addTearDown(controller.dispose);

    controller.selectPlace(attraction('A1', 'Batu Caves'), source: 'itinerary');
    controller.selectPlace(
      attraction('A2', 'Central Market'),
      source: 'recommendation',
    );

    expect(controller.attractionContext?.attractionId, isNull);
    expect(controller.attractionContext?.placeId, 'google-A2');
    expect(controller.attractionContext?.attractionName, 'Central Market');
    expect(controller.attractionContext?.source, 'recommendation');
    expect(controller.bookmarkPlace?.placeId, 'google-A2');
  });

  test('restaurant selection clears stale attraction context', () {
    final controller = GlobalAiAssistantController();
    addTearDown(controller.dispose);
    controller.selectPlace(attraction('A1', 'Batu Caves'), source: 'itinerary');

    controller.selectPlace(
      const Place(
        placeId: 'restaurant-1',
        placeName: 'Restaurant at Setapak',
        placeAddress: 'Setapak',
        placeLatitude: 3.2,
        placeLongitude: 101.7,
        placeRating: 4,
        placeTypes: ['restaurant', 'food'],
        category: 'restaurant',
      ),
      source: 'recommendation',
    );

    expect(controller.attractionContext, isNull);
    expect(controller.bookmarkPlace, isNull);
  });

  testWidgets('global AI button follows storytelling visibility', (
    tester,
  ) async {
    final controller = GlobalAiAssistantController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => GlobalAiAssistantHost(child: child!),
          home: const Scaffold(body: Text('Page content')),
        ),
      ),
    );

    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);

    controller.setStorytellingActive(true);
    await tester.pump();
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

    controller.setStorytellingActive(false);
    await tester.pump();
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
  });
}
