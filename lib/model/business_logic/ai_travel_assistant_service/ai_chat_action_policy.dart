import '../../entities/ai_attraction_context.dart';

enum AiNearbyScope { none, contextPlace, userCurrentLocation }

/// Keeps map and bookmark-card intent consistent across equivalent questions.
class AiChatActionPolicy {
  const AiChatActionPolicy._();

  static String? mapDestinationFromQuestion(String? question) {
    if (question == null) return null;
    final normalized = question.trim().toLowerCase();
    final isMapRequest = RegExp(
      r"\bwhere\s*(?:'s|is)\b|\bdirections?\b|\bnavigate\b|"
      r'\broute\s+to\b|\bhow\s+(?:do|can)\s+i\s+get\s+to\b',
    ).hasMatch(normalized);
    if (!isMapRequest) return null;

    var destination = question.trim();
    final prefixes = <RegExp>[
      RegExp(r"^where\s*(?:'s|is)\s+(?:the\s+)?", caseSensitive: false),
      RegExp(r'^how\s+(?:do|can)\s+i\s+get\s+to\s+', caseSensitive: false),
      RegExp(
        r'^(?:can\s+you\s+)?(?:show|give)\s+(?:me\s+)?directions?\s+to\s+',
        caseSensitive: false,
      ),
      RegExp(r'^(?:navigate|route)\s+(?:me\s+)?to\s+', caseSensitive: false),
    ];
    for (final prefix in prefixes) {
      destination = destination.replaceFirst(prefix, '');
    }
    destination = destination.replaceAll(RegExp(r'[?!.]+$'), '').trim();
    return destination.isEmpty ? question.trim() : destination;
  }

  static bool questionRefersToContext(
    String? question,
    AiAttractionContext? attractionContext,
  ) {
    if (question == null || attractionContext == null) return false;

    final lowerQuestion = question.toLowerCase();
    final attractionName = attractionContext.attractionName?.trim();
    if (attractionName != null &&
        attractionName.isNotEmpty &&
        lowerQuestion.contains(attractionName.toLowerCase())) {
      return true;
    }

    final normalizedQuestion = _normalizeEnglishReference(question);
    return RegExp(
      r'\b(?:this|that)\s+(?:place|attraction|location|landmark)\b|'
      r'\b(?:it|its|here|there)\b',
    ).hasMatch(normalizedQuestion);
  }

  static bool isContextReference(String? destination) {
    if (destination == null) return false;
    final normalized = _normalizeEnglishReference(destination);
    return RegExp(
      r'^(?:the\s+)?(?:this|that)\s+(?:place|attraction|location|landmark)$|'
      r'^(?:it|here|there)$',
    ).hasMatch(normalized);
  }

  /// A relative request cannot be ranked safely until the chat is given an
  /// actual city or device coordinates. Suppress unrelated database cards.
  static bool requiresCurrentLocation(String question) {
    final normalized = question
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return RegExp(
      r'\b(?:near\s*by|nearby|near|around|close\s+to)\s+(?:to\s+)?(?:me|my\s+(?:current\s+)?location|current\s+location)\b|'
      r'\bfrom\s+my\s+(?:current\s+)?location\b',
    ).hasMatch(normalized);
  }

  /// Resolves otherwise ambiguous nearby wording before either Gemini or the
  /// place-card resolver receives the question.
  static AiNearbyScope nearbyScope(String question) {
    final normalized = _normalizeEnglishReference(question);
    if (requiresCurrentLocation(normalized)) {
      return AiNearbyScope.userCurrentLocation;
    }

    if (RegExp(
      r'\b(?:near\s*by|nearby|near|around|close\s+to)\s+'
      r'(?:here|this\s+(?:place|location|attraction|area))\b',
    ).hasMatch(normalized)) {
      return AiNearbyScope.contextPlace;
    }

    final asksForRecommendation = RegExp(
      r'\b(?:recommend(?:ed|ation|ations)?|suggest(?:ed|ion|ions)?|best|popular)\b',
    ).hasMatch(normalized);
    final asksForNearbyPlaceKind = RegExp(
      r'\b(?:restaurant|restaurants|food|cafe|cafes|coffee|drink|drinks|bar|bars)\b',
    ).hasMatch(normalized);
    if (asksForRecommendation && asksForNearbyPlaceKind) {
      return AiNearbyScope.contextPlace;
    }

    final nearbyMatch = RegExp(
      r'\b(?:near\s*by|nearby)\b(?:\s+([a-z0-9]+))?',
    ).firstMatch(normalized);
    if (nearbyMatch == null) return AiNearbyScope.none;

    final nextWord = nearbyMatch.group(1);
    if (nextWord == null || _contextNearbyFollowerWords.contains(nextWord)) {
      return AiNearbyScope.contextPlace;
    }

    // "Nearby KLCC" contains its own explicit anchor and must not silently
    // inherit a previously selected place.
    return AiNearbyScope.none;
  }

  static String _normalizeEnglishReference(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

const _contextNearbyFollowerWords = <String>{
  'attraction',
  'attractions',
  'bar',
  'bars',
  'cafe',
  'cafes',
  'coffee',
  'drink',
  'drinks',
  'food',
  'here',
  'mall',
  'malls',
  'museum',
  'museums',
  'park',
  'parks',
  'place',
  'places',
  'please',
  'restaurant',
  'restaurants',
  'shopping',
};
