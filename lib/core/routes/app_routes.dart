import 'package:flutter/material.dart';
import '../../view/ar_screen.dart';
import '../../view/nearby_recommendation_screen.dart';
import '../../view/profile_screen.dart';
import '../../view/Itinerary/my_itineraries_screen.dart';
import '../widgets/app_bottom_navigation.dart';

/// The main routing shell of the application that manages the bottom navigation
/// and swaps between the AR, Itinerary, Nearby, and Profile tabs.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNavBar(
        items: _items,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }

  
}
