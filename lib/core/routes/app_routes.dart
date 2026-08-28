import 'package:flutter/material.dart';

import '../../view/Itinerary/my_itineraries_screen.dart';
import '../../view/ai_assistant/travel_assistant_screen.dart';
import '../../view/ar_screen.dart';
import '../../view/recommendation/nearby_recommendation_screen.dart';
import '../../view/profile_screen.dart';
import '../widgets/app_bottom_navigation.dart';

/// The main routing shell for the four persistent application tabs.
///
/// The AI chat button is intentionally in this shell, rather than inside a
/// single page, so it stays over the content when the tourist changes among
/// AR, Itinerary, and Nearby. It is hidden on Profile because UC500 is not
/// specified as a Profile entry point.
class AppRoutes extends StatefulWidget {
  const AppRoutes({super.key});

  @override
  State<AppRoutes> createState() => _AppRoutesState();
}

class _AppRoutesState extends State<AppRoutes> {
  int _index = 0;

  static const _screens = [
    ARScreen(),
    MyItinerariesScreen(),
    NearbyRecommendationScreen(),
    ProfileScreen(),
  ];

  static const _items = [
    BottomNavItem(
      icon: Icons.camera_alt_outlined,
      selectedIcon: Icons.camera_alt,
      label: 'AR',
    ),
    BottomNavItem(
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      label: 'Itinerary',
    ),
    BottomNavItem(
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on,
      label: 'Nearby',
    ),
    BottomNavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  void _openTravelAssistant() {
    final contextSource = switch (_index) {
      0 => 'ar_marker',
      1 => 'itinerary',
      2 => 'recommendation',
      _ => 'none',
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TravelAssistantScreen(contextSource: contextSource),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showAiAssistant = _index != 3;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(index: _index, children: _screens),
          ),
          if (showAiAssistant)
            Positioned(
              left: 20,
              bottom: 20,
              child: SafeArea(
                top: false,
                child: FloatingActionButton(
                  heroTag: 'global_ai_chat',
                  tooltip: 'Ask Manja, your AI Travel Assistant',
                  backgroundColor: const Color(0xFF2E6B67),
                  foregroundColor: Colors.white,
                  onPressed: _openTravelAssistant,
                  child: const Icon(Icons.chat_bubble_outline),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        items: _items,
        currentIndex: _index,
        onTap: (index) => setState(() => _index = index),
      ),
    );
  }
}
