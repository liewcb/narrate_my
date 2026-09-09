import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../view/Itinerary/my_itineraries_screen.dart';
import '../../view/ar/ar_exploration/ar_exploration_view.dart';
import '../../view/recommendation/nearby_recommendation_screen.dart';
import '../../view/profile/profile_home_screen.dart';
import '../ai_assistant/global_ai_assistant.dart';
import '../localization/app_localizations.dart';
import '../localization/locale_vm.dart';
import '../widgets/app_bottom_navigation.dart';

/// The main routing shell for the four persistent application tabs.
///
/// The app-wide AI chat entry point is hosted above the root Navigator in
/// the root AI assistant host, allowing it to remain visible on pushed routes.
class AppRoutes extends StatefulWidget {
  final int initialIndex;
  const AppRoutes({super.key, this.initialIndex = 0});

  @override
  State<AppRoutes> createState() => _AppRoutesState();
}

class _AppRoutesState extends State<AppRoutes> {
  late int _index;
  late final Set<int> _visitedTabs;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _visitedTabs = {0, widget.initialIndex};
  }

  Widget _buildTabScreen(int tabIndex) {
    if (!_visitedTabs.contains(tabIndex)) {
      return const SizedBox.shrink();
    }
    return switch (tabIndex) {
      0 => ARExplorationView(isActive: _index == 0),
      1 => const MyItinerariesScreen(),
      2 => NearbyRecommendationScreen(onOpenAr: () => _selectTab(0)),
      3 => const ProfileHomeScreen(),
      _ => const SizedBox.shrink(),
    };
  }

  List<Widget> _screens() => [
    _buildTabScreen(0),
    _buildTabScreen(1),
    _buildTabScreen(2),
    _buildTabScreen(3),
  ];

  List<BottomNavItem> _items() => [
    BottomNavItem(
      icon: Icons.camera_alt_outlined,
      selectedIcon: Icons.camera_alt,
      label: AppLocalizations.t('nav.ar'),
    ),
    BottomNavItem(
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      label: AppLocalizations.t('nav.itinerary'),
    ),
    BottomNavItem(
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on,
      label: AppLocalizations.t('nav.nearby'),
    ),
    BottomNavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: AppLocalizations.t('nav.profile'),
    ),
  ];

  void _selectTab(int index) {
    context.read<GlobalAiAssistantController>().setProfileActive(index == 3);
    setState(() {
      _visitedTabs.add(index);
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens()),
      bottomNavigationBar: AppBottomNavBar(
        items: _items(),
        currentIndex: _index,
        onTap: _selectTab,
      ),
    );
  }
}
