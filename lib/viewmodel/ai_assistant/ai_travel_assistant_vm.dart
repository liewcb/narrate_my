import 'package:flutter/foundation.dart';

import '../../core/services/permission_service.dart';
import '../../model/business_logic/ai_travel_assistant_service/ai_bookmark_place_resolver.dart';
import '../../model/business_logic/ai_travel_assistant_service/ai_chat_action_policy.dart';
import '../../model/business_logic/ai_travel_assistant_service/ai_travel_assistant_service.dart';
import '../../model/business_logic/shared_services/location_service.dart';
import '../../model/entities/ai_attraction_context.dart';
import '../../model/entities/ai_chat_message.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/ai_assist/ai_travel_assistant_repository_adapter.dart';
import '../../model/repositories/interfaces/ai_assist/ai_travel_assistant_repository.dart';

/// ChangeNotifier for UC500's chat state and Gemini requests.
class AiTravelAssistantViewModel extends ChangeNotifier {
  AiTravelAssistantViewModel({
    AiTravelAssistantRepository? repository,
    AiBookmarkPlaceQuestionResolver? bookmarkPlaceResolver,
    AiAttractionContext? initialContext,
    Place? initialBookmarkPlace,
    String? initialConversationSummary,
    AiCurrentLocationLoader? currentLocationLoader,
    this.resolveBookmarkPlacesFromQuestions = true,
  }) : _service = AiTravelAssistantService(
         repository ?? SupabaseAiTravelAssistantRepositoryAdapter(),
       ),
       _bookmarkPlaceResolver =
           bookmarkPlaceResolver ?? AiBookmarkPlaceResolver(),
       _attractionContext = initialContext,
       _contextBookmarkPlace = initialBookmarkPlace,
       _currentLocationLoader =
           currentLocationLoader ?? _loadDeviceCurrentLocation,
       _conversationSummary = _cleanSummary(initialConversationSummary) {
    _messages = [_greeting()];
  }

  final AiTravelAssistantService _service;
  final AiBookmarkPlaceQuestionResolver _bookmarkPlaceResolver;
  final AiCurrentLocationLoader _currentLocationLoader;
  final bool resolveBookmarkPlacesFromQuestions;

  late List<AiChatMessage> _messages;
  AiAttractionContext? _attractionContext;
  Place? _contextBookmarkPlace;
  bool _isSending = false;
  bool _isSummarizing = false;
  bool _isResolvingBookmarkPlaces = false;
  String? _errorMessage;
  String? _conversationSummary;
  bool _summaryNeedsRefresh = false;
  String? _summaryErrorMessage;
  List<Place> _bookmarkCandidates = const [];
  int? _actionMessageIndex;
  String? _actionQuestion;

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  AiAttractionContext? get attractionContext => _attractionContext;
  Place? get contextBookmarkPlace => _contextBookmarkPlace;
  bool get isSending => _isSending;
  bool get isSummarizing => _isSummarizing;
  bool get isResolvingBookmarkPlaces => _isResolvingBookmarkPlaces;
  String? get errorMessage => _errorMessage;
  String? get conversationSummary => _conversationSummary;
  bool get summaryNeedsRefresh => _summaryNeedsRefresh;
  String? get summaryErrorMessage => _summaryErrorMessage;
  List<Place> get bookmarkCandidates => List.unmodifiable(_bookmarkCandidates);
  int? get actionMessageIndex => _actionMessageIndex;
  String? get actionQuestion => _actionQuestion;
  bool get canSummarize =>
      _messages.any((message) => message.sender == AiChatMessageSender.tourist);

  Future<void> sendQuestion(String question) async {
    if (_isSending || _isSummarizing) return;

    late final String normalizedQuestion;
    try {
      normalizedQuestion = _service.validateQuestion(question);
    } on AiAssistantValidationException catch (error) {
      _errorMessage = error.message;
      _addSystemMessage(error.message);
      return;
    }

    // Keep only the prior messages as history. The Edge Function receives the
    // new question separately, so it is not sent twice to Gemini.
    final historyBeforeQuestion = List<AiChatMessage>.from(_messages);

    _messages.add(
      AiChatMessage(
        text: normalizedQuestion,
        sender: AiChatMessageSender.tourist,
      ),
    );
    _summaryNeedsRefresh = true;
    _summaryErrorMessage = null;
    _bookmarkCandidates = const [];
    _actionMessageIndex = null;
    _actionQuestion = null;
    _isSending = true;
    _isResolvingBookmarkPlaces = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final nearbyScope = AiChatActionPolicy.nearbyScope(normalizedQuestion);
      Coordinates? nearbyOrigin;
      var requestContext = _attractionContext;

      if (nearbyScope == AiNearbyScope.userCurrentLocation) {
        try {
          nearbyOrigin = await _currentLocationLoader();
        } on AiCurrentLocationException {
          rethrow;
        } catch (_) {
          throw const AiCurrentLocationException(
            'Your current location is unavailable. Please try again.',
          );
        }
        // Never send the selected attraction as the model context for "me".
        requestContext = null;
      } else if (nearbyScope == AiNearbyScope.contextPlace &&
          _hasValidCoordinates(_contextBookmarkPlace)) {
        nearbyOrigin = _contextBookmarkPlace!.coordinates;
      }

      if (resolveBookmarkPlacesFromQuestions &&
          nearbyScope != AiNearbyScope.none) {
        _isResolvingBookmarkPlaces = true;
        notifyListeners();
        try {
          _bookmarkCandidates = await _bookmarkPlaceResolver.resolveQuestion(
            normalizedQuestion,
            nearbyOrigin: nearbyOrigin,
          );
        } catch (error, stackTrace) {
          debugPrint('AI scoped nearby place resolution failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          _bookmarkCandidates = const [];
        } finally {
          _isResolvingBookmarkPlaces = false;
        }
      }

      final answer = await _service.answerQuestion(
        question: normalizedQuestion,
        conversationHistory: historyBeforeQuestion,
        attractionContext: requestContext,
        requestInstruction: nearbyScope == AiNearbyScope.none
            ? null
            : _nearbyRequestInstruction(
                scope: nearbyScope,
                origin: nearbyOrigin,
                places: _bookmarkCandidates,
              ),
      );
      _messages.add(
        AiChatMessage(text: answer, sender: AiChatMessageSender.assistant),
      );
      _actionMessageIndex = _messages.length - 1;
      _actionQuestion = normalizedQuestion;

      if (resolveBookmarkPlacesFromQuestions &&
          nearbyScope == AiNearbyScope.none) {
        _isSending = false;
        _isResolvingBookmarkPlaces = true;
        notifyListeners();

        try {
          _bookmarkCandidates = await _bookmarkPlaceResolver.resolveQuestion(
            normalizedQuestion,
            nearbyOrigin: nearbyOrigin,
          );
          if (nearbyScope == AiNearbyScope.none &&
              _bookmarkCandidates.length == 1) {
            _useResolvedPlaceAsContext(_bookmarkCandidates.single);
          }
        } catch (error, stackTrace) {
          debugPrint('AI bookmark place resolution failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          _bookmarkCandidates = const [];
        }
      }
    } on AiCurrentLocationException catch (error) {
      _clearPendingActions();
      _errorMessage = error.message;
      _addSystemMessage(error.message, shouldNotify: false);
    } on AiAssistantValidationException catch (error) {
      _clearPendingActions();
      _errorMessage = error.message;
      _addSystemMessage(error.message, shouldNotify: false);
    } catch (error, stackTrace) {
      debugPrint('AI answer request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _clearPendingActions();
      const message = 'I’m unable to answer right now. Please try again later.';
      _errorMessage = message;
      _addSystemMessage(message, shouldNotify: false);
    } finally {
      _isSending = false;
      _isResolvingBookmarkPlaces = false;
      notifyListeners();
    }
  }

  /// Generates a read-only recap without adding it to the visible chat. An
  /// existing recap stays visible until its refreshed replacement is ready.
  Future<void> generateSummary() async {
    if (_isSending || _isSummarizing) return;

    if (!canSummarize) {
      if (_conversationSummary != null) {
        _summaryErrorMessage = null;
        notifyListeners();
        return;
      }
      _summaryErrorMessage =
          'Send at least one question before creating a conversation summary.';
      notifyListeners();
      return;
    }

    if (_conversationSummary != null && !_summaryNeedsRefresh) return;

    const summaryQuestion =
        'Update the saved travel summary using newer messages. Return 3 to 5 '
        'concise factual bullet points covering useful details, user preferences '
        'or decisions, and unresolved questions. Do not invent facts.';

    final summaryHistory = <AiChatMessage>[
      if (_conversationSummary != null)
        AiChatMessage(
          text: 'Previous saved conversation summary:\n$_conversationSummary',
          sender: AiChatMessageSender.system,
        ),
      ..._messages,
    ];

    _isSummarizing = true;
    _summaryErrorMessage = null;
    notifyListeners();

    try {
      debugPrint('Summary: starting Edge Function request');

      final refreshedSummary = await _service.answerQuestion(
        question: summaryQuestion,
        conversationHistory: summaryHistory,
        attractionContext: _attractionContext,
      );
      _conversationSummary = refreshedSummary;
      _summaryNeedsRefresh = false;

      debugPrint('Summary: Edge Function response received');
    } on AiAssistantValidationException catch (error, stackTrace) {
      debugPrint('AI summary validation failed: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      _summaryErrorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AI summary request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _summaryErrorMessage =
          'I’m unable to create a summary right now. Please try again later.';
    } finally {
      _isSummarizing = false;
      notifyListeners();
    }
  }

  void resetConversation() {
    _messages = [_greeting()];
    _errorMessage = null;
    _conversationSummary = null;
    _summaryNeedsRefresh = false;
    _summaryErrorMessage = null;
    _bookmarkCandidates = const [];
    _actionMessageIndex = null;
    _actionQuestion = null;
    _isResolvingBookmarkPlaces = false;
    notifyListeners();
  }

  void setAttractionContext(AiAttractionContext? context) {
    _attractionContext = context;
    if (context == null) _contextBookmarkPlace = null;
    notifyListeners();
  }

  void _useResolvedPlaceAsContext(Place place) {
    if (!_isAttractionContextCandidate(place)) return;

    _contextBookmarkPlace = place;
    _attractionContext = AiAttractionContext(
      attractionName: place.placeName,
      placeId: place.placeId,
      source: 'chat_question',
    );
  }

  bool _isAttractionContextCandidate(Place place) {
    final types = place.placeTypes
        .map((type) => type.toLowerCase().replaceAll(' ', '_'))
        .toSet();
    return types.any(_attractionContextTypes.contains);
  }

  bool _hasValidCoordinates(Place? place) =>
      place != null &&
      place.placeLatitude >= -90 &&
      place.placeLatitude <= 90 &&
      place.placeLongitude >= -180 &&
      place.placeLongitude <= 180 &&
      !(place.placeLatitude == 0 && place.placeLongitude == 0);

  String _nearbyRequestInstruction({
    required AiNearbyScope scope,
    required Coordinates? origin,
    required List<Place> places,
  }) {
    final coordinateText = origin == null
        ? 'coordinates are unavailable'
        : '${origin.latitude.toStringAsFixed(5)}, '
              '${origin.longitude.toStringAsFixed(5)}';
    final anchorInstruction = scope == AiNearbyScope.userCurrentLocation
        ? 'Nearby origin: user GPS ($coordinateText). '
              'Ignore any selected attraction.'
        : 'Nearby origin: selected place '
              '"${_attractionContext?.attractionName ?? 'unknown'}" '
              '($coordinateText).';
    final verifiedResults = places.isEmpty
        ? 'No verified results; do not invent places.'
        : 'Verified nearby places only: '
              '${places.map((place) => place.placeName).join('; ')}.';
    return '$anchorInstruction $verifiedResults';
  }

  void _addSystemMessage(String message, {bool shouldNotify = true}) {
    _messages.add(
      AiChatMessage(text: message, sender: AiChatMessageSender.system),
    );
    if (shouldNotify) notifyListeners();
  }

  void _clearPendingActions() {
    _bookmarkCandidates = const [];
    _actionMessageIndex = null;
    _actionQuestion = null;
  }

  AiChatMessage _greeting() => AiChatMessage(
    text: 'Here’s Manja, Your AI Travel Assistant!',
    sender: AiChatMessageSender.assistant,
  );
}

const _attractionContextTypes = <String>{
  'amusement_park',
  'aquarium',
  'art_gallery',
  'hindu_temple',
  'landmark',
  'market',
  'mosque',
  'museum',
  'natural_feature',
  'park',
  'place_of_worship',
  'shopping_mall',
  'stadium',
  'tourist_attraction',
  'zoo',
  'bar',
  'cafe',
  'food',
  'meal_delivery',
  'meal_takeaway',
  'night_club',
  'restaurant',
};

String? _cleanSummary(String? summary) {
  final cleaned = summary?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

typedef AiCurrentLocationLoader = Future<Coordinates> Function();

class AiCurrentLocationException implements Exception {
  const AiCurrentLocationException(this.message);

  final String message;
}

Future<Coordinates> _loadDeviceCurrentLocation() async {
  final locationService = LocationService();
  final permissionService = PermissionService();

  if (!await locationService.isLocationServiceEnabled()) {
    throw const AiCurrentLocationException(
      'Turn on location services to find places near you.',
    );
  }

  var hasPermission = await permissionService.hasLocationPermission();
  if (!hasPermission) {
    await permissionService.requestLocation();
    hasPermission = await permissionService.hasLocationPermission();
  }
  if (!hasPermission) {
    throw const AiCurrentLocationException(
      'Location permission is required to find places near you.',
    );
  }

  try {
    final position = await locationService.getCurrentPosition();
    return Coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } catch (_) {
    throw const AiCurrentLocationException(
      'Your current location is unavailable. Please try again.',
    );
  }
}
