import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/services/map_marker_layout.dart';
import 'package:narrate_my/model/entities/coordinates.dart';

void main() {
  test('leaves isolated map markers at their real coordinates', () {
    const original = Coordinates(latitude: 3.1579, longitude: 101.7116);

    final displayed = spreadOverlappingMapCoordinates({'one': original});

    expect(displayed['one'], original);
  });

  test('spreads markers that would otherwise be stacked', () {
    const original = Coordinates(latitude: 3.1579, longitude: 101.7116);

    final displayed = spreadOverlappingMapCoordinates({
      'observation-deck': original,
      'visitor-tower': original,
    });

    expect(displayed['observation-deck'], isNot(original));
    expect(displayed['visitor-tower'], isNot(original));
    expect(
      displayed['observation-deck']!.distanceTo(displayed['visitor-tower']!) *
          1000,
      greaterThan(45),
    );
  });

  test('does not move markers that are already visibly separated', () {
    const first = Coordinates(latitude: 3.1579, longitude: 101.7116);
    const second = Coordinates(latitude: 3.1589, longitude: 101.7116);

    final displayed = spreadOverlappingMapCoordinates({
      'first': first,
      'second': second,
    });

    expect(displayed['first'], first);
    expect(displayed['second'], second);
  });
}
