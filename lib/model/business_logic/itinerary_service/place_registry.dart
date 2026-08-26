// lib/model/business_logic/itinerary_service/place_registry.dart
import 'dart:collection';
import '../../entities/place.dart';

/// Central lookup for every [Place] retrieved from Google Places.
///
/// The Google `placeId` is the permanent identity of a place for the
/// entire pipeline.  Later stages (scoring, clustering, AI route
/// planning, schedule construction) refer to places by `placeId` and
/// always reconstruct the complete original [Place] from this registry —
/// AI is never allowed to invent or modify place facts.
///
/// The registry is append-only during a single generation run:
/// [addAll] and [add] never overwrite an existing entry, so the original
/// collection is preserved for localised regeneration.
class PlaceRegistry {
  final Map<String, Place> _byId = {};

  /// Number of registered places.
  int get length => _byId.length;

  /// All places, insertion order preserved.
  List<Place> get all => List.unmodifiable(_byId.values);

  /// True when [placeId] is already registered.
  bool contains(String placeId) => _byId.containsKey(placeId);

  /// Look up the complete original place by its Google Place ID.
  /// Returns null when the id is unknown.
  Place? byId(String placeId) => _byId[placeId];

  /// Register a single place. Never overwrites an existing entry.
  void add(Place place) {
    _byId.putIfAbsent(place.placeId, () => place);
  }

  /// Register many places, preserving first-seen order.
  void addAll(Iterable<Place> places) {
    for (final place in places) {
      add(place);
    }
  }

  /// Reconstruct a list of places from an ordered list of place IDs.
  /// Unknown IDs are skipped so the caller can detect incomplete routes.
  List<Place> resolveByIds(Iterable<String> placeIds) {
    return placeIds
        .map(byId)
        .whereType<Place>()
        .toList(growable: false);
  }

  /// An unmodifiable view of the underlying map (for tracing/debugging).
  Map<String, Place> get snapshot => UnmodifiableMapView(_byId);
}
