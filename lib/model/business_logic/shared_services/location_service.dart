import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationService {
  static const Duration _highAccuracyTimeout = Duration(seconds: 8);
  static const Duration _networkAssistedTimeout = Duration(seconds: 8);
  static const Duration _maximumFallbackAge = Duration(minutes: 10);

  /// [REQ_101_2] One-shot fetch of GPS latitude/longitude/altitude.
  ///
  /// A fresh high-accuracy fix can take a while indoors. If it times out, use
  /// a recent position already supplied by Android's fused/network provider
  /// instead of blocking the Nearby screen even though a usable position is
  /// available.
  Future<Position> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _highAccuracyTimeout,
        ),
      );
    } on TimeoutException {
      try {
        // A balanced request lets Android satisfy the request from its fused
        // Wi-Fi/cell provider when a satellite fix is unavailable indoors.
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: _networkAssistedTimeout,
          ),
        );
      } on TimeoutException {
        final lastKnownPosition = await _recentLastKnownPosition();
        if (lastKnownPosition != null) return lastKnownPosition;
        rethrow;
      }
    }
  }

  Future<Position?> _recentLastKnownPosition() async {
    final lastKnownPosition = await Geolocator.getLastKnownPosition();
    if (lastKnownPosition == null) return null;

    final age = DateTime.now().difference(lastKnownPosition.timestamp);
    if (age > _maximumFallbackAge) return null;

    return lastKnownPosition;
  }

  /// Continuous position stream, used to keep re-evaluating nearby
  /// markers/attractions as the tourist moves around.
  Stream<Position> watchPosition({int distanceFilterMeters = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    );
  }

  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();
}
