import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/ai_assistant/global_ai_assistant.dart';
import 'package:provider/provider.dart';

void main() {
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
