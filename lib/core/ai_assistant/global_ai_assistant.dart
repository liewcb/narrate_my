import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/entities/ai_attraction_context.dart';
import '../../model/entities/ar_object.dart';
import '../../model/entities/ar_recommendation.dart';
import '../../model/entities/ar_site.dart';
import '../../model/entities/place.dart';
import '../../view/ai_assistant/travel_assistant_screen.dart';

/// Root navigator used by the app-wide AI entry point.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Coordinates visibility of the app-wide AI assistant button.
class GlobalAiAssistantController extends ChangeNotifier {
  bool _assistantOpen = false;
  bool _storytellingActive = false;
  AiAttractionContext? _attractionContext;
  Place? _bookmarkPlace;

  bool get shouldShowButton => !_assistantOpen && !_storytellingActive;
  AiAttractionContext? get attractionContext => _attractionContext;
  Place? get bookmarkPlace => _bookmarkPlace;

  /// Replaces the previous selection. Only the latest attraction is carried
  /// into a newly opened chat.
  void selectAttraction({
    String? attractionId,
    required String attractionName,
    String? markerId,
    String? placeId,
    required String source,
    Place? bookmarkPlace,
  }) {
    final cleanName = attractionName.trim();
    if (cleanName.isEmpty) {
      clearAttractionContext();
      return;
    }
    _attractionContext = AiAttractionContext(
      attractionId: _clean(attractionId),
      attractionName: cleanName,
      markerId: _clean(markerId),
      placeId: _clean(placeId),
      source: source,
    );
    _bookmarkPlace = bookmarkPlace;
    notifyListeners();
  }

  /// Itinerary and Google recommendation rows are not guaranteed to have a
  /// curated Attraction FK, so their stable Google Place ID is used instead.
  void selectPlace(Place place, {required String source}) {
    if (_isRestaurant(place)) {
      clearAttractionContext();
      return;
    }
    selectAttraction(
      attractionName: place.placeName,
      placeId: place.placeId,
      source: source,
      bookmarkPlace: place,
    );
  }

  void selectArMarker(ARMarker marker) {
    selectAttraction(
      attractionId: marker.attractionId,
      attractionName: marker.name,
      markerId: marker.markerId,
      source: 'ar_marker',
    );
  }

  void selectArRecommendation(ARRecommendation recommendation) {
    final place = recommendation.toBookmarkPlace();
    if (_isRestaurant(place)) {
      clearAttractionContext();
      return;
    }
    selectAttraction(
      attractionId: recommendation.attractionId,
      attractionName: recommendation.name,
      markerId: recommendation.markerId,
      placeId: recommendation.placeId,
      source: 'ar_recommendation',
      bookmarkPlace: place,
    );
  }

  void selectArSite(
    ARSite site, {
    required double latitude,
    required double longitude,
  }) {
    final experience = site.nearestExperienceTo(latitude, longitude);
    if (experience == null) {
      clearAttractionContext();
      return;
    }
    selectAttraction(
      attractionId: experience.attractionId,
      attractionName: experience.name,
      markerId: experience.markerId,
      source: 'nearby_ar_site',
    );
  }

  void clearAttractionContext() {
    if (_attractionContext == null && _bookmarkPlace == null) return;
    _attractionContext = null;
    _bookmarkPlace = null;
    notifyListeners();
  }

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static bool _isRestaurant(Place place) {
    final tokens = <String>[
      ...place.placeTypes,
      if (place.category != null) place.category!,
    ].map((value) => value.toLowerCase().replaceAll(' ', '_'));
    return tokens.any(
      (value) =>
          value.contains('restaurant') ||
          value == 'cafe' ||
          value == 'food' ||
          value == 'bar' ||
          value == 'night_club' ||
          value.startsWith('meal_'),
    );
  }

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
    final attractionContext = controller.attractionContext;
    final bookmarkPlace = controller.bookmarkPlace;
    controller.setAssistantOpen(true);
    try {
      await navigator.push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'travel_assistant'),
          builder: (_) => TravelAssistantScreen(
            attractionId: attractionContext?.attractionId,
            attractionName: attractionContext?.attractionName,
            markerId: attractionContext?.markerId,
            placeId: attractionContext?.placeId,
            contextSource: attractionContext?.source ?? 'none',
            bookmarkPlace: bookmarkPlace,
          ),
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
