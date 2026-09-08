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
  bool _profileActive = false;
  bool _arPlacementActive = false;
  AiAttractionContext? _attractionContext;
  Place? _bookmarkPlace;
  String? _conversationSummary;
  String? _conversationSummaryLanguageCode;
  final Map<int, _AiAttractionSelection> _attractionPreviews = {};
  int _nextPreviewToken = 0;

  bool get shouldShowButton =>
      !_assistantOpen && !_storytellingActive && !_profileActive;
  double get assistantBottomOffset => _arPlacementActive ? 200 : 84;
  AiAttractionContext? get attractionContext => _attractionContext;
  Place? get bookmarkPlace => _bookmarkPlace;
  String? get conversationSummary => _conversationSummary;
  String? get conversationSummaryLanguageCode =>
      _conversationSummaryLanguageCode;

  /// Replaces the previous selection. Only the latest attraction is carried
  /// into a newly opened chat.
  void selectAttraction({
    String? attractionId,
    required String attractionName,
    String? markerId,
    String? placeId,
    double? latitude,
    double? longitude,
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
      latitude: latitude,
      longitude: longitude,
      source: source,
    );
    _bookmarkPlace = bookmarkPlace;
    notifyListeners();
  }

  /// Itinerary and Google recommendation rows are not guaranteed to have a
  /// curated Attraction FK, so their stable Google Place ID is used instead.
  void selectPlace(Place place, {required String source}) {
    selectAttraction(
      attractionName: place.placeName,
      placeId: place.placeId,
      latitude: place.placeLatitude,
      longitude: place.placeLongitude,
      source: source,
      bookmarkPlace: place,
    );
  }

  /// Makes a place available to the AI button only while its detail surface
  /// is open. Merely viewing a recommendation must not replace the last
  /// context that was actually used to enter AI chat.
  int previewPlace(Place place, {required String source}) {
    final token = ++_nextPreviewToken;
    _attractionPreviews[token] = _AiAttractionSelection(
      context: AiAttractionContext(
        attractionName: place.placeName.trim(),
        placeId: _clean(place.placeId),
        latitude: place.placeLatitude,
        longitude: place.placeLongitude,
        source: source,
      ),
      bookmarkPlace: place,
    );
    return token;
  }

  void endAttractionPreview(int token) {
    _attractionPreviews.remove(token);
  }

  /// Called only by the AI button. This is the point where the attraction
  /// visible on the current page becomes the persistent chat context.
  void commitActiveAttractionPreview() {
    if (_attractionPreviews.isEmpty) return;
    final selection = _attractionPreviews.values.last;
    _attractionContext = selection.context;
    _bookmarkPlace = selection.bookmarkPlace;
    notifyListeners();
  }

  void selectArMarker(ARMarker marker) {
    selectAttraction(
      attractionId: marker.attractionId,
      attractionName: marker.name,
      markerId: marker.markerId,
      latitude: marker.latitude,
      longitude: marker.longitude,
      source: 'ar_marker',
    );
  }

  void selectArRecommendation(ARRecommendation recommendation) {
    final place = recommendation.toBookmarkPlace();
    selectAttraction(
      attractionId: recommendation.attractionId,
      attractionName: recommendation.name,
      markerId: recommendation.markerId,
      placeId: recommendation.placeId,
      latitude: place.placeLatitude,
      longitude: place.placeLongitude,
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
      latitude: experience.latitude,
      longitude: experience.longitude,
      source: 'nearby_ar_site',
    );
  }

  void clearAttractionContext() {
    if (_attractionContext == null && _bookmarkPlace == null) return;
    _attractionContext = null;
    _bookmarkPlace = null;
    notifyListeners();
  }

  /// Keeps the most recent recap available while the user navigates away from
  /// and back to chat. This is session state, not permanent account storage.
  void saveConversationSummary(String? summary, {String? languageCode}) {
    final cleaned = _clean(summary);
    final cleanedLanguageCode = cleaned == null ? null : _clean(languageCode);
    if (_conversationSummary == cleaned &&
        _conversationSummaryLanguageCode == cleanedLanguageCode) {
      return;
    }
    _conversationSummary = cleaned;
    _conversationSummaryLanguageCode = cleanedLanguageCode;
    notifyListeners();
  }

  void clearConversationSummary() => saveConversationSummary(null);

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
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

  void setProfileActive(bool value) {
    if (_profileActive == value) return;
    _profileActive = value;
    notifyListeners();
  }

  void setArPlacementActive(bool value) {
    if (_arPlacementActive == value) return;
    _arPlacementActive = value;
    notifyListeners();
  }
}

/// Places one AI entry point above the root Navigator so pushed itinerary,
/// recommendation, AR, authentication, and profile pages cannot cover it.
class GlobalAiAssistantHost extends StatefulWidget {
  const GlobalAiAssistantHost({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalAiAssistantHost> createState() => _GlobalAiAssistantHostState();
}

class _GlobalAiAssistantHostState extends State<GlobalAiAssistantHost> {
  static const double _buttonSize = 56;
  static const double _edgeMargin = 12;
  Offset? _dragPosition;

  Future<void> _openAssistant(BuildContext context) async {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    final controller = context.read<GlobalAiAssistantController>();
    controller.commitActiveAttractionPreview();
    final attractionContext = controller.attractionContext;
    final bookmarkPlace = controller.bookmarkPlace;
    final conversationSummary = controller.conversationSummary;
    final conversationSummaryLanguageCode =
        controller.conversationSummaryLanguageCode;
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
            contextLatitude: attractionContext?.latitude,
            contextLongitude: attractionContext?.longitude,
            contextSource: attractionContext?.source ?? 'none',
            bookmarkPlace: bookmarkPlace,
            initialConversationSummary: conversationSummary,
            initialConversationSummaryLanguageCode:
                conversationSummaryLanguageCode,
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
    final bottomOffset = context.select<GlobalAiAssistantController, double>(
      (controller) => controller.assistantBottomOffset,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaPadding = MediaQuery.paddingOf(context);
        final minimumX = mediaPadding.left + _edgeMargin;
        final maximumX =
            (constraints.maxWidth -
                    mediaPadding.right -
                    _edgeMargin -
                    _buttonSize)
                .clamp(minimumX, double.infinity)
                .toDouble();
        final minimumY = mediaPadding.top + _edgeMargin;
        final maximumY =
            (constraints.maxHeight -
                    mediaPadding.bottom -
                    bottomOffset -
                    _buttonSize)
                .clamp(minimumY, double.infinity)
                .toDouble();
        final defaultPosition = Offset(minimumX + 8, maximumY);
        final position = _clampPosition(
          _dragPosition ?? defaultPosition,
          minimumX: minimumX,
          maximumX: maximumX,
          minimumY: minimumY,
          maximumY: maximumY,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (showButton)
              Positioned(
                key: const ValueKey('global-ai-assistant-position'),
                left: position.dx,
                top: position.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _dragPosition = _clampPosition(
                        position + details.delta,
                        minimumX: minimumX,
                        maximumX: maximumX,
                        minimumY: minimumY,
                        maximumY: maximumY,
                      );
                    });
                  },
                  onPanEnd: (_) {
                    final current = _dragPosition ?? position;
                    final midpoint = (minimumX + maximumX) / 2;
                    setState(() {
                      _dragPosition = Offset(
                        current.dx <= midpoint ? minimumX : maximumX,
                        current.dy.clamp(minimumY, maximumY).toDouble(),
                      );
                    });
                  },
                  child: Semantics(
                    button: true,
                    label: 'Ask Manja, your AI Travel Assistant',
                    hint: 'Tap to open or drag to move',
                    child: FloatingActionButton(
                      key: const ValueKey('global-ai-assistant-button'),
                      // The button is above the root Navigator, so it must not
                      // use Hero or Tooltip features that need its Overlay.
                      heroTag: null,
                      elevation: 8,
                      highlightElevation: 10,
                      backgroundColor: const Color(0xFF2E6B67),
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(
                        side: BorderSide(color: Color(0x66FFFFFF)),
                      ),
                      onPressed: () => _openAssistant(context),
                      child: const Icon(Icons.chat_bubble_outline, size: 24),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Offset _clampPosition(
    Offset position, {
    required double minimumX,
    required double maximumX,
    required double minimumY,
    required double maximumY,
  }) {
    return Offset(
      position.dx.clamp(minimumX, maximumX).toDouble(),
      position.dy.clamp(minimumY, maximumY).toDouble(),
    );
  }
}

class _AiAttractionSelection {
  const _AiAttractionSelection({
    required this.context,
    required this.bookmarkPlace,
  });

  final AiAttractionContext context;
  final Place? bookmarkPlace;
}
