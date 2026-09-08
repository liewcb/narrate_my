import '../../entities/ai_attraction_context.dart';

enum AiNearbyScope { none, contextPlace, userCurrentLocation }

/// Keeps map and bookmark-card intent consistent across equivalent questions.
class AiChatActionPolicy {
  const AiChatActionPolicy._();

  /// Converts supported non-English intent phrases into the same
  /// internal English vocabulary used by the deterministic action rules.
  /// Place names remain in the original question used for Google search.
  static String normalizeForIntent(String value) {
    var normalized = value.toLowerCase();

    for (final replacement in _mandarinIntentReplacements.entries) {
      normalized = normalized.replaceAll(replacement.key, replacement.value);
    }
    for (final replacement in _malayIntentReplacements.entries) {
      normalized = normalized.replaceAll(
        RegExp(replacement.key, caseSensitive: false),
        replacement.value,
      );
    }
    for (final replacement in _spanishIntentReplacements.entries) {
      normalized = normalized.replaceAll(
        RegExp(replacement.key, caseSensitive: false),
        replacement.value,
      );
    }
    for (final replacement in _hindiIntentReplacements.entries) {
      normalized = normalized.replaceAll(replacement.key, replacement.value);
    }

    return normalized
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? mapDestinationFromQuestion(String? question) {
    if (question == null) return null;
    final original = question.trim();
    final mandarinDestination = RegExp(
      r'^(.+?)(?:在哪里|在哪裡|在哪儿|在哪兒|在哪)\s*[?？]?$',
    ).firstMatch(original);
    if (mandarinDestination != null) {
      final destination = mandarinDestination.group(1)?.trim();
      if (destination != null && destination.isNotEmpty) return destination;
    }

    final normalized = normalizeForIntent(original);
    final isTravelRequest = RegExp(
      r'^(?:i\s+)?(?:(?:want|would\s+like)\s+to\s+)?'
      r'(?:go|visit)(?:\s+to)?\b',
    ).hasMatch(normalized);
    final isMapRequest =
        RegExp(
          r"\bwhere\s*(?:s|is)\b|\bdirections?\b|\bnavigate\b|"
          r'\broute\s+to\b|\bhow\s+(?:do|can)\s+i\s+get\s+to\b',
        ).hasMatch(normalized) ||
        isTravelRequest;
    if (!isMapRequest) return null;

    var destination = original;
    final prefixes = <RegExp>[
      RegExp(r'^(?:我想|我要|想|请|請)?(?:去|前往)\s*'),
      RegExp(r'^(?:请|請)?(?:带我去|帶我去)\s*'),
      RegExp(
        r'^(?:saya\s+)?(?:(?:mahu|nak|ingin)\s+)?pergi\s+(?:ke\s+)?',
        caseSensitive: false,
      ),
      RegExp(
        r'^(?:i\s+)?(?:(?:want|would\s+like)\s+to\s+)?'
        r'(?:go|visit)\s+(?:to\s+)?',
        caseSensitive: false,
      ),
      RegExp(r"^where\s*(?:'s|is)\s+(?:the\s+)?", caseSensitive: false),
      RegExp(r'^(?:di|kat)\s+mana\s+', caseSensitive: false),
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
    return destination.isEmpty ? null : destination;
  }

  /// Menu, dish, and general "what can I eat" questions are informational.
  /// They should use the active context for the answer without launching a
  /// broad place search or showing unrelated bookmark cards.
  static bool isFoodInformationOnly(String question) {
    final normalized = normalizeForIntent(question);
    final mentionsFood = RegExp(
      r'\b(?:food|menu|dish|dishes|eat|meal|meals|cuisine)\b',
    ).hasMatch(normalized);
    if (!mentionsFood) return false;

    final requestsPlaces = RegExp(
      r'\b(?:near|nearby|recommend|suggest|best|popular|find|where|'
      r'directions?|navigate|route|go|visit|bookmark)\b',
    ).hasMatch(normalized);
    return !requestsPlaces;
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

    final normalizedQuestion = normalizeForIntent(question);
    return RegExp(
      r'\b(?:this|that)\s+(?:place|attraction|location|landmark)\b|'
      r'\b(?:it|its|here|there)\b',
    ).hasMatch(normalizedQuestion);
  }

  static bool isContextReference(String? destination) {
    if (destination == null) return false;
    final normalized = normalizeForIntent(destination);
    return RegExp(
      r'^(?:the\s+)?(?:this|that)\s+(?:place|attraction|location|landmark)$|'
      r'^(?:it|here|there)$',
    ).hasMatch(normalized);
  }

  /// A relative request cannot be ranked safely until the chat is given an
  /// actual city or device coordinates. Suppress unrelated database cards.
  static bool requiresCurrentLocation(String question) {
    final normalized = normalizeForIntent(question);
    return RegExp(
      r'\b(?:near\s*by|nearby|near|around|close\s+to)\s+(?:to\s+)?(?:me|my\s+(?:current\s+)?location|current\s+location)\b|'
      r'\bfrom\s+my\s+(?:current\s+)?location\b',
    ).hasMatch(normalized);
  }

  /// Resolves otherwise ambiguous nearby wording before either Gemini or the
  /// place-card resolver receives the question.
  static AiNearbyScope nearbyScope(String question) {
    final normalized = normalizeForIntent(question);
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
}

const _mandarinIntentReplacements = <String, String>{
  '我想去': ' i want to visit ',
  '我要去': ' i want to visit ',
  '想去': ' want to visit ',
  '带我去': ' navigate to ',
  '帶我去': ' navigate to ',
  '介绍': ' tell me about ',
  '介紹': ' tell me about ',
  '我当前位置附近': ' nearby me ',
  '我目前位置附近': ' nearby me ',
  '在我附近': ' nearby me ',
  '我附近': ' nearby me ',
  '离我很近': ' nearby me ',
  '離我很近': ' nearby me ',
  '离我近': ' nearby me ',
  '離我近': ' nearby me ',
  '这个地方附近': ' nearby here ',
  '這個地方附近': ' nearby here ',
  '这地方附近': ' nearby here ',
  '這地方附近': ' nearby here ',
  '这里附近': ' nearby here ',
  '這裡附近': ' nearby here ',
  '这附近': ' nearby here ',
  '這附近': ' nearby here ',
  '咖啡馆': ' cafe ',
  '咖啡館': ' cafe ',
  '餐厅': ' restaurant ',
  '餐廳': ' restaurant ',
  '餐馆': ' restaurant ',
  '餐館': ' restaurant ',
  '饭店': ' restaurant ',
  '飯店': ' restaurant ',
  '在哪里': ' where is ',
  '在哪裡': ' where is ',
  '在哪儿': ' where is ',
  '在哪兒': ' where is ',
  '怎么去': ' directions to ',
  '怎麼去': ' directions to ',
  '这个地方': ' this place ',
  '這個地方': ' this place ',
  '这地方': ' this place ',
  '這地方': ' this place ',
  '这里': ' here ',
  '這裡': ' here ',
  '附近': ' nearby ',
  '推荐': ' recommend ',
  '推薦': ' recommend ',
  '建议': ' suggest ',
  '建議': ' suggest ',
  '热门': ' popular ',
  '熱門': ' popular ',
  '最好': ' best ',
  '美食': ' food ',
  '食物': ' food ',
  '菜单': ' menu ',
  '菜單': ' menu ',
  '餐点': ' meal ',
  '餐點': ' meal ',
  '吃': ' eat ',
  '咖啡': ' coffee ',
  '饮料': ' drinks ',
  '飲料': ' drinks ',
  '酒吧': ' bar ',
  '大桥': ' bridge ',
  '大橋': ' bridge ',
  '它': ' it ',
  '去': ' visit ',
};

const _malayIntentReplacements = <String, String>{
  r'\b(?:saya\s+)?(?:mahu|nak|ingin)\s+pergi\s+(?:ke\s+)?': ' visit ',
  r'\b(?:berdekatan|berhampiran|dekat)(?:\s+dengan)?\s+(?:lokasi\s+)?saya\b':
      ' nearby me ',
  r'\bsekitar\s+(?:lokasi\s+)?saya\b': ' nearby me ',
  r'\b(?:berdekatan|berhampiran|dekat)(?:\s+dengan)?\s+(?:tempat\s+ini|di\s+sini|sini)\b':
      ' nearby here ',
  r'\bsekitar\s+(?:tempat\s+ini|di\s+sini|sini)\b': ' nearby here ',
  r'\b(?:cadangkan|syorkan|disyorkan|sarankan|saran)\b': ' recommend ',
  r'\brestoran\b': ' restaurant ',
  r'\bmakanan\b': ' food ',
  r'\bmenu\b': ' menu ',
  r'\bhidangan\b': ' dish ',
  r'\bmakan\b': ' eat ',
  r'\bkafe\b': ' cafe ',
  r'\bkopi\b': ' coffee ',
  r'\bminuman\b': ' drinks ',
  r'\btempat\s+ini\b': ' this place ',
  r'\bdi\s+sini\b': ' here ',
  r'\bkat\s+sini\b': ' here ',
  r'\b(?:di|kat)\s+mana\b': ' where is ',
  r'\bpergi\s+(?:ke\s+)?': ' visit ',
};

const _spanishIntentReplacements = <String, String>{
  r'\bcomida\b': ' food ',
  r'\bcomer\b': ' eat ',
  r'\bmen[uú]\b': ' menu ',
  r'\bplatos?\b': ' dish ',
  r'\bcocina\b': ' cuisine ',
};

const _hindiIntentReplacements = <String, String>{
  'खाना': ' food ',
  'भोजन': ' food ',
  'मेनू': ' menu ',
  'व्यंजन': ' dish ',
  'खाऊँ': ' eat ',
  'खाना चाहता': ' eat ',
};

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
