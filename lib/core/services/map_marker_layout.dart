import 'dart:math' as math;

import '../../model/entities/coordinates.dart';

/// Moves map pins that would otherwise be drawn directly on top of each other.
///
/// This only changes the visual pin positions. The attraction's real
/// coordinates remain unchanged for distance, details, navigation, and AR
/// activation checks.
Map<String, Coordinates> spreadOverlappingMapCoordinates(
  Map<String, Coordinates> coordinates, {
  double collisionDistanceMeters = 10,
  double spreadRadiusMeters = 26,
}) {
  if (coordinates.length < 2) return Map.unmodifiable(coordinates);

  final remaining = coordinates.entries.toList();
  final groups = <List<MapEntry<String, Coordinates>>>[];

  while (remaining.isNotEmpty) {
    final group = <MapEntry<String, Coordinates>>[remaining.removeAt(0)];
    var addedMember = true;
    while (addedMember) {
      addedMember = false;
      for (var index = remaining.length - 1; index >= 0; index--) {
        final candidate = remaining[index];
        final collides = group.any(
          (member) =>
              member.value.distanceTo(candidate.value) * 1000 <=
              collisionDistanceMeters,
        );
        if (collides) {
          group.add(remaining.removeAt(index));
          addedMember = true;
        }
      }
    }
    groups.add(group);
  }

  final result = <String, Coordinates>{};
  for (final group in groups) {
    if (group.length == 1) {
      result[group.single.key] = group.single.value;
      continue;
    }

    final centerLatitude =
        group.map((entry) => entry.value.latitude).reduce((a, b) => a + b) /
        group.length;
    final centerLongitude =
        group.map((entry) => entry.value.longitude).reduce((a, b) => a + b) /
        group.length;
    final latitudeDegreesPerMeter = 1 / 111320.0;
    final longitudeDegreesPerMeter =
        1 /
        (111320.0 *
            math.max(0.01, math.cos(centerLatitude * math.pi / 180).abs()));

    for (var index = 0; index < group.length; index++) {
      final angle = -math.pi / 2 + (2 * math.pi * index / group.length);
      result[group[index].key] = Coordinates(
        latitude:
            centerLatitude +
            math.sin(angle) * spreadRadiusMeters * latitudeDegreesPerMeter,
        longitude:
            centerLongitude +
            math.cos(angle) * spreadRadiusMeters * longitudeDegreesPerMeter,
      );
    }
  }

  return Map.unmodifiable(result);
}
