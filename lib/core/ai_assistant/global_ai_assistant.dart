import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../view/ai_assistant/travel_assistant_screen.dart';

/// Root navigator used by the app-wide AI entry point.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Coordinates visibility of the app-wide AI assistant button.
class GlobalAiAssistantController extends ChangeNotifier {
  bool _assistantOpen = false;
  bool _storytellingActive = false;

  bool get shouldShowButton => !_assistantOpen && !_storytellingActive;

  void setAssistantOpen(bool value) {
    if (_assistantOpen == value) return;
    _assistantOpen = value;
    notifyListeners();
  }

  void setStorytellingActive(bool value) {
    if (_storytellingActive == value) return;
    _storytellingActive = value;
    notifyListeners();
  }
}

/// Places one AI entry point above the root Navigator so pushed itinerary,
/// recommendation, AR, authentication, and profile pages cannot cover it.
class GlobalAiAssistantHost extends StatelessWidget {
  const GlobalAiAssistantHost({super.key, required this.child});

  final Widget child;

  Future<void> _openAssistant(BuildContext context) async {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    final controller = context.read<GlobalAiAssistantController>();
    controller.setAssistantOpen(true);
    try {
      await navigator.push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'travel_assistant'),
          builder: (_) => const TravelAssistantScreen(contextSource: 'none'),
        ),
      );
    } finally {
      controller.setAssistantOpen(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showButton = context.select<GlobalAiAssistantController, bool>(
      (controller) => controller.shouldShowButton,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (showButton)
          Positioned(
            left: 20,
            bottom: 84,
            child: SafeArea(
              top: false,
              child: Semantics(
                button: true,
                label: 'Ask Manja, your AI Travel Assistant',
                child: FloatingActionButton(
                  // The button is above the root Navigator, so it must not use
                  // Hero or Tooltip features that look for a Navigator Overlay
                  // ancestor. Semantics preserves its accessible label.
                  heroTag: null,
                  backgroundColor: const Color(0xFF2E6B67),
                  foregroundColor: Colors.white,
                  onPressed: () => _openAssistant(context),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
