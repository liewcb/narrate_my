import '../../../core/services/google_maps_service.dart';
import '../../data_sources/remote/ai_nearby_place_remote_data_source.dart';
import '../../data_sources/remote/ai_bookmark_place_remote_data_source.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import 'ai_chat_action_policy.dart';

/// Resolves a general AI-chat question to canonical bookmark candidates.
///
/// Gemini remains responsible only for the conversational answer. Places
/// already stored in Supabase are preferred, with Google Places as an optional
/// fallback when its Dart API key is available.
abstract interface class AiBookmarkPlaceQuestionResolver {
  Future<List<Place>> resolveQuestion(
    String question, {
    Coordinates? nearbyOrigin,
  });
}

typedef AiNearbyPlaceLoader =
    Future<List<Place>> Function({
      required Coordinates origin,
      required List<String> includedTypes,
      required double radiusKm,
    });

class AiBookmarkPlaceResolver implements AiBookmarkPlaceQuestionResolver {
  AiBookmarkPlaceResolver({
    GoogleMapsService? mapsService,
    AiBookmarkPlaceRemoteDataSource? knownPlacesSource,
    AiNearbyPlaceRemoteDataSource? nearbyPlaceSource,
    Future<List<Place>> Function()? knownPlacesLoader,
    AiNearbyPlaceLoader? nearbyPlaceLoader,
  }) : _mapsService = mapsService ?? GoogleMapsService(),
       _loadNearbyPlaces =
           nearbyPlaceLoader ??
           (nearbyPlaceSource ?? AiNearbyPlaceRemoteDataSource())
               .searchNearbyPlaces,
       _loadKnownPlaces =
           knownPlacesLoader ??
           (knownPlacesSource ?? AiBookmarkPlaceRemoteDataSource())
               .fetchBookmarkablePlaces;

  final GoogleMapsService _mapsService;
  final AiNearbyPlaceLoader _loadNearbyPlaces;
  final Future<List<Place>> Function() _loadKnownPlaces;
  List<Place>? _cachedKnownPlaces;

  static const _maximumCandidates = 3;
  static const _nearbyRadiusKm = 10.0;

  @override
  Future<List<Place>> resolveQuestion(
    String question, {
    Coordinates? nearbyOrigin,
  }) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) return const [];
    final nearbyScope = AiChatActionPolicy.nearbyScope(trimmedQuestion);
    if (nearbyScope != AiNearbyScope.none && nearbyOrigin == null) {
      return const [];
    }

    if (nearbyOrigin != null && nearbyScope != AiNearbyScope.none) {
      return _resolveNearbyQuestion(trimmedQuestion, nearbyOrigin);
    }

    // Prefer canonical rows that the rest of the app already uses. Besides
    // avoiding an unnecessary API request, this path works without requiring
    // Android Studio to pass a Dart API key at launch.
    try {
      final knownPlaces = _cachedKnownPlaces ??= await _loadKnownPlaces();
      final knownMatches = _rankKnownPlaces(trimmedQuestion, knownPlaces);
      if (knownMatches.isNotEmpty) return List.unmodifiable(knownMatches);
    } catch (_) {
      // Supabase being temporarily unavailable should not prevent the
      // optional Google fallback below.
    }

    // A direct place name such as "aquaria klcc" may not contain words like
    // "place" or "visit", so the database match above intentionally happens
    // before this broader intent check.
    if (!_looksPlaceRelated(trimmedQuestion)) return const [];

    // The native Android Maps key does not automatically become available to
    // Dart. Skip the REST call when this launch has no --dart-define key.
    if (_mapsService.googleMapsApiKey.trim().isEmpty) return const [];

    final query = _containsMalaysia(trimmedQuestion)
        ? trimmedQuestion
        : '$trimmedQuestion Malaysia';
    final results = await _mapsService.searchTextPlaces(query: query);
    final broadDiscovery = _isBroadDiscoveryQuestion(trimmedQuestion);
    final questionWords = _meaningfulWords(trimmedQuestion);
    final requestedLocationWords = _requestedLocationWords(trimmedQuestion);
    final seenGoogleIds = <String>{};
    final candidates = <Place>[];

    for (final place in results) {
      final googlePlaceId = place.placeId.trim();
      if (googlePlaceId.isEmpty ||
          !seenGoogleIds.add(googlePlaceId) ||
          !_isBookmarkable(place)) {
        continue;
      }

      final searchableText = _normalize(
        '${place.placeName} ${place.placeAddress} '
        '${place.category ?? ''} ${place.placeTypes.join(' ')}',
      );
      if (!_matchesRequestedLocation(
        requestedLocationWords,
        searchableText,
        _meaningfulWords(searchableText),
      )) {
        continue;
      }

      if (!broadDiscovery &&
          !_matchesSpecificPlaceName(
            trimmedQuestion,
            questionWords,
            requestedLocationWords,
            place.placeName,
          )) {
        continue;
      }

      candidates.add(place);
      if (candidates.length == _maximumCandidates) break;
    }

    return List.unmodifiable(candidates);
  }

  Future<List<Place>> _resolveNearbyQuestion(
    String question,
    Coordinates origin,
  ) async {
    // Nearby Search (New) is authoritative for location-scoped discovery.
    // It runs server-side so the Places Web Service key is never shipped in
    // the Flutter application.
    try {
      final googlePlaces = await _loadNearbyPlaces(
        origin: origin,
        includedTypes: _nearbyIncludedTypes(question),
        radiusKm: _nearbyRadiusKm,
      );
      return List.unmodifiable(
        _rankNearbyPlaces(question, googlePlaces, origin),
      );
    } catch (error) {
      // The strict coordinate/type filters below remain in force for every
      // fallback, so a transient Edge Function problem cannot produce random
      // places from another state.
    }

    if (_mapsService.googleMapsApiKey.trim().isNotEmpty) {
      try {
        final results = await _mapsService.searchTextPlaces(
          query: _nearbySearchQuery(question),
          latitude: origin.latitude,
          longitude: origin.longitude,
          radius: _nearbyRadiusKm * 1000,
        );
        final matches = _rankNearbyPlaces(question, results, origin);
        if (matches.isNotEmpty) return List.unmodifiable(matches);
      } catch (_) {
        // Continue to the strictly filtered Supabase fallback.
      }
    }

    try {
      final knownPlaces = _cachedKnownPlaces ??= await _loadKnownPlaces();
      return List.unmodifiable(
        _rankNearbyPlaces(question, knownPlaces, origin),
      );
    } catch (_) {
      return const [];
    }
  }

  List<Place> _rankNearbyPlaces(
    String question,
    List<Place> places,
    Coordinates origin,
  ) {
    final normalizedQuestion = question.toLowerCase();
    final ranked = <({Place place, double distanceKm})>[];

    for (final place in places) {
      if (!_isBookmarkable(place) ||
          !_matchesRequestedKind(normalizedQuestion, place) ||
          !_hasValidCoordinates(place)) {
        continue;
      }
      final distanceKm = origin.distanceTo(place.coordinates);
      if (distanceKm > _nearbyRadiusKm) continue;
      ranked.add((place: place, distanceKm: distanceKm));
    }

    ranked.sort((left, right) {
      final distanceComparison = left.distanceKm.compareTo(right.distanceKm);
      if (distanceComparison != 0) return distanceComparison;
      return right.place.placeRating.compareTo(left.place.placeRating);
    });

    final seenPlaceIds = <String>{};
    return ranked
        .map((item) => item.place)
        .where((place) => seenPlaceIds.add(place.placeId.trim()))
        .take(_maximumCandidates)
        .toList(growable: false);
  }

  bool _hasValidCoordinates(Place place) =>
      place.placeLatitude >= -90 &&
      place.placeLatitude <= 90 &&
      place.placeLongitude >= -180 &&
      place.placeLongitude <= 180 &&
      !(place.placeLatitude == 0 && place.placeLongitude == 0);

  String _nearbySearchQuery(String question) {
    final normalized = question.toLowerCase();
    if (normalized.contains('restaurant') || normalized.contains('food')) {
      return 'restaurant';
    }
    if (normalized.contains('cafe') || normalized.contains('coffee')) {
      return 'cafe';
    }
    if (normalized.contains('drink') || normalized.contains('bar')) {
      return 'cafe or bar';
    }
    if (normalized.contains('museum')) return 'museum';
    if (normalized.contains('park')) return 'park';
    if (normalized.contains('shopping') || normalized.contains('mall')) {
      return 'shopping mall';
    }
    return 'tourist attraction';
  }

  List<String> _nearbyIncludedTypes(String question) {
    final normalized = question.toLowerCase();
    if (normalized.contains('restaurant') || normalized.contains('food')) {
      return const ['restaurant'];
    }
    if (normalized.contains('cafe') || normalized.contains('coffee')) {
      return const ['cafe'];
    }
    if (normalized.contains('drink') || normalized.contains('bar')) {
      return const ['cafe', 'bar'];
    }
    if (normalized.contains('museum')) return const ['museum'];
    if (normalized.contains('park')) return const ['park'];
    if (normalized.contains('shopping') || normalized.contains('mall')) {
      return const ['shopping_mall'];
    }
    return const ['tourist_attraction'];
  }

  List<Place> _rankKnownPlaces(String question, List<Place> places) {
    final normalizedQuestion = question.toLowerCase();
    final questionWords = _meaningfulWords(question);
    final broadDiscovery = _isBroadDiscoveryQuestion(question);
    final requestedLocationWords = _requestedLocationWords(question);
    final ranked = <({Place place, int score})>[];

    for (final place in places) {
      if (!_isBookmarkable(place) ||
          !_matchesRequestedKind(normalizedQuestion, place)) {
        continue;
      }

      final normalizedName = _normalize(place.placeName);
      final nameWords = _meaningfulWords(place.placeName);
      final nameOverlap = questionWords.intersection(nameWords).length;
      final searchableText = _normalize(
        '${place.placeName} ${place.placeAddress} '
        '${place.category ?? ''} ${place.placeTypes.join(' ')}',
      );
      final searchableWords = _meaningfulWords(searchableText);

      if (!_matchesRequestedLocation(
        requestedLocationWords,
        searchableText,
        searchableWords,
      )) {
        continue;
      }

      if (!broadDiscovery) {
        // A partial match is unsafe for a specific request: "Suria KLCC"
        // must not resolve to Aquaria KLCC merely because both contain KLCC.
        if (!_matchesSpecificPlaceName(
          question,
          questionWords,
          requestedLocationWords,
          place.placeName,
        )) {
          continue;
        }
      }

      final searchOverlap = questionWords.intersection(searchableWords).length;
      final exactNameBonus = _normalize(question).contains(normalizedName)
          ? 500
          : 0;
      final locationBonus = requestedLocationWords.length * 150;
      final score =
          exactNameBonus +
          locationBonus +
          (nameOverlap * 100) +
          (searchOverlap * 10);
      ranked.add((place: place, score: score));
    }

    ranked.sort((left, right) {
      final scoreComparison = right.score.compareTo(left.score);
      if (scoreComparison != 0) return scoreComparison;
      return right.place.placeRating.compareTo(left.place.placeRating);
    });

    final seenPlaceIds = <String>{};
    return ranked
        .map((item) => item.place)
        .where((place) => seenPlaceIds.add(place.placeId.trim()))
        .take(_maximumCandidates)
        .toList(growable: false);
  }

  bool _matchesSpecificPlaceName(
    String question,
    Set<String> questionWords,
    Set<String> requestedLocationWords,
    String placeName,
  ) {
    final normalizedName = _normalize(placeName);
    final requestedNameWords = questionWords
        .difference(_genericPlaceQueryWords)
        .difference(requestedLocationWords)
        .difference(_placeQuestionQualifierWords);
    final nameWords = _meaningfulWords(placeName);
    final fullNameInQuestion =
        normalizedName.isNotEmpty &&
        _normalize(question).contains(normalizedName);
    final allNameWordsMatch =
        requestedNameWords.isNotEmpty &&
        nameWords.containsAll(requestedNameWords);
    return fullNameInQuestion || allNameWordsMatch;
  }

  Set<String> _requestedLocationWords(String question) {
    final match = RegExp(
      r'\b(?:at|near\s*by|nearby|near|around|in)\s+([^?!.;,]+)',
      caseSensitive: false,
    ).firstMatch(question);
    if (match == null) return const {};

    return _meaningfulWords(
      match.group(1) ?? '',
    ).difference(_genericPlaceQueryWords);
  }

  bool _matchesRequestedLocation(
    Set<String> requestedWords,
    String searchableText,
    Set<String> searchableWords,
  ) {
    if (requestedWords.isEmpty) return true;

    return requestedWords.every((word) {
      if (searchableWords.contains(word)) return true;
      if (word == 'klcc') {
        return searchableText.contains('kuala lumpur city centre') ||
            searchableText.contains('kuala lumpur convention centre');
      }
      if (word == 'malacca') return searchableWords.contains('melaka');
      if (word == 'melaka') return searchableWords.contains('malacca');
      return false;
    });
  }

  bool _matchesRequestedKind(String question, Place place) {
    final searchable = <String>{
      ...place.placeTypes.map((type) => type.toLowerCase()),
      if (place.category != null) place.category!.toLowerCase(),
    }.join(' ');

    if (question.contains('restaurant')) {
      return searchable.contains('restaurant');
    }
    if (question.contains('food')) {
      return searchable.contains('restaurant') || searchable.contains('food');
    }
    if (question.contains('drink') || question.contains('bar')) {
      return searchable.contains('cafe') || searchable.contains('bar');
    }
    if (question.contains('cafe')) return searchable.contains('cafe');
    if (question.contains('museum')) return searchable.contains('museum');
    if (question.contains('aquarium')) return searchable.contains('aquarium');
    if (question.contains('park')) return searchable.contains('park');
    return true;
  }

  bool _isBookmarkable(Place place) {
    if (place.businessStatus != null &&
        place.businessStatus!.toUpperCase() != 'OPERATIONAL') {
      return false;
    }

    final types = place.placeTypes.map((type) => type.toLowerCase()).toSet();
    return types.any(_bookmarkableGoogleTypes.contains);
  }

  bool _containsMalaysia(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('malaysia') ||
        normalized.contains('kuala lumpur') ||
        normalized.contains('melaka') ||
        normalized.contains('malacca') ||
        normalized.contains('penang') ||
        normalized.contains('selangor');
  }

  bool _looksPlaceRelated(String question) {
    final normalized = question.toLowerCase();
    if (_placeIntentTerms.any(normalized.contains)) return true;

    final words = RegExp(
      r"[A-Za-z][A-Za-z'-]*",
    ).allMatches(question).map((match) => match.group(0)!).toList();
    return words
        .skip(1)
        .any(
          (word) =>
              word.length > 2 &&
              word[0] == word[0].toUpperCase() &&
              !_capitalizedStopWords.contains(word.toLowerCase()),
        );
  }

  bool _isBroadDiscoveryQuestion(String question) {
    final normalized = question.toLowerCase();
    return _broadDiscoveryTerms.any(normalized.contains);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Set<String> _meaningfulWords(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2 && !_searchStopWords.contains(word))
        .toSet();
  }
}

const _bookmarkableGoogleTypes = <String>{
  'adventure',
  'amusement_park',
  'aquarium',
  'art_gallery',
  'bar',
  'cafe',
  'church',
  'culture & history',
  'food',
  'hindu_temple',
  'landmark',
  'market',
  'mosque',
  'museum',
  'nature & outdoor',
  'natural_feature',
  'night_club',
  'park',
  'place_of_worship',
  'restaurant',
  'shopping_mall',
  'shopping',
  'stadium',
  'tourist_attraction',
  'zoo',
};

const _placeIntentTerms = <String>{
  'about ',
  'attraction',
  'cafe',
  'food',
  'landmark',
  'museum',
  'near ',
  'park',
  'place',
  'recommend',
  'restaurant',
  'things to do',
  'visit',
  'where',
};

const _broadDiscoveryTerms = <String>{
  'attractions',
  'best ',
  'cafe',
  'food',
  'near ',
  'places',
  'recommend',
  'restaurant',
  'restaurants',
  'suggest',
  'things to do',
  'what can i do',
  'where should',
};

const _capitalizedStopWords = <String>{
  'can',
  'could',
  'do',
  'how',
  'i',
  'please',
  'tell',
  'what',
  'when',
  'where',
  'would',
};

const _searchStopWords = <String>{
  'about',
  'and',
  'are',
  'can',
  'could',
  'for',
  'from',
  'give',
  'how',
  'know',
  'located',
  'location',
  'malaysia',
  'near',
  'please',
  'recommend',
  'show',
  'tell',
  'the',
  'this',
  'visit',
  'what',
  'when',
  'where',
  'with',
  'would',
  'you',
};

const _genericPlaceQueryWords = <String>{
  'attraction',
  'attractions',
  'cafe',
  'food',
  'landmark',
  'mall',
  'museum',
  'park',
  'place',
  'places',
  'restaurant',
  'restaurants',
  'things',
};

const _placeQuestionQualifierWords = <String>{
  'beautiful',
  'famous',
  'good',
  'history',
  'information',
  'introduce',
  'interesting',
  'nice',
  'open',
  'popular',
  'worth',
};
