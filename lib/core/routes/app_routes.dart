import 'package:flutter/material.dart';

import '../../view/Itinerary/my_itineraries_screen.dart';
import '../../view/ar/ar_exploration/ar_exploration_view.dart';
import '../../view/recommendation/nearby_recommendation_screen.dart';
import '../../view/profile_screen.dart';
import '../widgets/app_bottom_navigation.dart';

/// The main routing shell for the four persistent application tabs.
///
/// The app-wide AI chat entry point is hosted above the root Navigator in
/// the root AI assistant host, allowing it to remain visible on pushed routes.
class AppRoutes extends StatefulWidget {
  const AppRoutes({super.key});

  @override
  State<AppRoutes> createState() => _AppRoutesState();
}

class _AppRoutesState extends State<AppRoutes> {
  int _index = 0;
  final Set<int> _visitedTabs = {0};

  Widget _buildTabScreen(int tabIndex) {
    if (!_visitedTabs.contains(tabIndex)) {
      return const SizedBox.shrink();
    }
    return switch (tabIndex) {
      0 => ARExplorationView(isActive: _index == 0),
      1 => const MyItinerariesScreen(),
      2 => NearbyRecommendationScreen(
        onOpenAr: () => setState(() => _index = 0),
      ),
      3 => const ProfileScreen(),
      _ => const SizedBox.shrink(),
    };
  }

  List<Widget> _screens() => [
    _buildTabScreen(0),
    _buildTabScreen(1),
    _buildTabScreen(2),
    _buildTabScreen(3),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens()),
      bottomNavigationBar: AppBottomNavBar(
        items: _items,
        currentIndex: _index,
        onTap: (index) => setState(() {
          _visitedTabs.add(index);
          _index = index;
        }),
      ),
    );
  }
}
