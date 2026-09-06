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

  test('restaurant selection becomes the latest place context', () {
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

    expect(
      controller.attractionContext?.attractionName,
      'Restaurant at Setapak',
    );
    expect(controller.attractionContext?.placeId, 'restaurant-1');
    expect(controller.attractionContext?.source, 'recommendation');
    expect(controller.bookmarkPlace?.placeId, 'restaurant-1');
  });

  test('viewing a recommendation does not replace committed chat context', () {
    final controller = GlobalAiAssistantController();
    addTearDown(controller.dispose);
    final aFamosa = attraction('A1', 'A Famosa');
    final petrosains = attraction('A2', 'Petrosains');
    controller.selectPlace(aFamosa, source: 'recommendation');

    final previewToken = controller.previewPlace(
      petrosains,
      source: 'recommendation',
    );

    expect(controller.attractionContext?.attractionName, 'A Famosa');
    expect(controller.bookmarkPlace, aFamosa);

    controller.endAttractionPreview(previewToken);
    expect(controller.attractionContext?.attractionName, 'A Famosa');
  });

  test('AI button commits the attraction currently being previewed', () {
    final controller = GlobalAiAssistantController();
    addTearDown(controller.dispose);
    controller.selectPlace(
      attraction('A1', 'A Famosa'),
      source: 'recommendation',
    );
    final petrosains = attraction('A2', 'Petrosains');
    final previewToken = controller.previewPlace(
      petrosains,
      source: 'recommendation',
    );

    controller.commitActiveAttractionPreview();
    controller.endAttractionPreview(previewToken);

    expect(controller.attractionContext?.attractionName, 'Petrosains');
    expect(controller.bookmarkPlace, petrosains);
  });

  test('conversation summary remains available until replaced or cleared', () {
    final controller = GlobalAiAssistantController();
    addTearDown(controller.dispose);

    controller.saveConversationSummary('First summary');
    expect(controller.conversationSummary, 'First summary');

    controller.saveConversationSummary('Updated summary');
    expect(controller.conversationSummary, 'Updated summary');

    controller.clearConversationSummary();
    expect(controller.conversationSummary, isNull);
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

  testWidgets('global AI button is hidden while Profile is active', (
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
          home: const Scaffold(body: Text('Profile page')),
        ),
      ),
    );

    controller.setProfileActive(true);
    await tester.pump();
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

    controller.setProfileActive(false);
    await tester.pump();
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
  });
}
