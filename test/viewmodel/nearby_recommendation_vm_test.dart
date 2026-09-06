import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:narrate_my/model/entities/coordinates.dart';
import 'package:narrate_my/model/entities/ar_site.dart';
import 'package:narrate_my/model/entities/recommendation.dart';
import 'package:narrate_my/model/business_logic/shared_services/location_service.dart';
import 'package:narrate_my/core/services/permission_service.dart';
import 'package:narrate_my/model/repositories/interfaces/ar_site_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/recommendation_repository.dart';
import 'package:narrate_my/viewmodel/recommendation/nearby_recommendation_vm.dart';
import 'package:permission_handler/permission_handler.dart';

class _FakeRecommendationRepository implements RecommendationRepository {
  final List<bool> forceRefreshCalls = [];

  @override
  Future<List<Recommendation>> getNearbyRecommendations({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    forceRefreshCalls.add(forceRefresh);
    return const [];
  }
}

class _FakeArSiteRepository implements ARSiteRepository {
  @override
  Future<List<ARSite>> getNearbySites({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    return const [];
  }
}

class _FakeLocationService extends LocationService {
  final _positions = StreamController<Position>.broadcast();
  Position current = _position(3.1390, 101.6869);

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<Position> getCurrentPosition() async => current;

  @override
  Stream<Position> watchPosition({int distanceFilterMeters = 5}) =>
      _positions.stream;

  void emit(double latitude, double longitude) {
    current = _position(latitude, longitude);
    _positions.add(current);
  }

  Future<void> close() => _positions.close();
}

class _GrantedPermissionService extends PermissionService {
  @override
  Future<bool> hasLocationPermission() async => true;

  @override
  Future<PermissionStatus> requestLocation() async => PermissionStatus.granted;
}

Position _position(double latitude, double longitude) => Position(
  longitude: longitude,
  latitude: latitude,
  timestamp: DateTime(2026, 9, 6),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 0,
  speedAccuracy: 1,
  isMocked: true,
);

void main() {
  group('REQ_401_9 movement threshold', () {
    const origin = Coordinates(latitude: 3.1390, longitude: 101.6869);

    test('does not refresh below 500 metres', () {
      const nearby = Coordinates(latitude: 3.1430, longitude: 101.6869);

      expect(
        NearbyRecommendationVm.movedBeyondRefreshThreshold(origin, nearby),
        isFalse,
      );
    });

    test('refreshes after moving more than 500 metres', () {
      const moved = Coordinates(latitude: 3.1450, longitude: 101.6869);

      expect(
        NearbyRecommendationVm.movedBeyondRefreshThreshold(origin, moved),
        isTrue,
      );
    });

    test(
      'automatically forces a refresh only after crossing 500 metres',
      () async {
        final repository = _FakeRecommendationRepository();
        final location = _FakeLocationService();
        final viewModel = NearbyRecommendationVm(
          repository,
          arSiteRepository: _FakeArSiteRepository(),
          locationService: location,
          permissionService: _GrantedPermissionService(),
        );

        await viewModel.loadRecommendations();
        expect(repository.forceRefreshCalls, [false]);

        location.emit(3.1430, 101.6869);
        await Future<void>.delayed(Duration.zero);
        expect(repository.forceRefreshCalls, [false]);

        location.emit(3.1450, 101.6869);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(repository.forceRefreshCalls, [false, true]);

        viewModel.dispose();
        await location.close();
      },
    );
  });
}
