import 'package:flutter/material.dart';

import 'ai_assistant/travel_assistant_screen.dart';


class NearbyRecommendationScreen extends StatelessWidget {
  const NearbyRecommendationScreen({super.key});

  void _openTravelAssistant(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TravelAssistantScreen(
          contextSource: 'recommendation',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby')),
      body: Stack(
        children: [
          const Center(child: Text('Nearby recommendations go here')),
          Positioned( // AI Chat floating button
            left: 20,
            bottom: 20,
            child: SafeArea(
              top: false,
              child: FloatingActionButton(
                heroTag: 'recommendation_ai_chat',
                tooltip: 'Ask Manja, your AI Travel Assistant',
                backgroundColor: const Color(0xFF2E6B67),
                foregroundColor: Colors.white,
                onPressed: () => _openTravelAssistant(context),
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
