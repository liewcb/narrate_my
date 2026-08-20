import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/config/app_config.dart';
import '../../entities/ar_object.dart';
import '../../repositories/interfaces/ar_repository.dart';
import '../shared_services/location_service.dart';

/// Immutable snapshot of the AR scene at a point in time — what the View
/// actually renders.
class ARSceneState {
  /// All markers within scan radius AND within their own activation
  /// radius, sorted nearest-first. (BF-4, BF-5 minus the notification UI).
  final List<ARMarker> nearbyMarkers;

  /// The single marker the tourist is currently directly facing, if any
  /// (BF-6, BF-7). Null when no marker is within heading tolerance.
  final ARMarker? primaryMarker;

  final double deviceHeadingDegrees;

  // --- Diagnostics (not used for rendering logic, only for the debug HUD) ---
  final double? userLat;
  final double? userLng;

  /// Count returned by the DB query BEFORE the activation_radius filter
  /// is applied — lets you tell "query returned nothing" apart from
  /// "query returned rows but they got filtered out".
  final int rawFetchedCount;

  /// ALL fetched markers with geometry computed, regardless of
  /// activation_radius or heading — i.e. the pre-filter debug view.
  /// [nearbyMarkers] above is the post-filter list actually eligible to
  /// render.
  final List<ARMarker> allComputedMarkers;

  const ARSceneState({
    required this.nearbyMarkers,
    required this.primaryMarker,
    required this.deviceHeadingDegrees,
    this.userLat,
    this.userLng,
    this.rawFetchedCount = 0,
    this.allComputedMarkers = const [],
  });

  static const empty = ARSceneState(nearbyMarkers: [], primaryMarker: null, deviceHeadingDegrees: 0);
}

/// Orchestrates UC100 BF-3 through BF-7:
///   GPS fix -> query nearby markers -> live compass matching -> primary
///   marker selection.
///
/// Emits [ARSceneState] any time the tourist's position or heading
/// changes meaningfully.
class ARExplorationService {
  final ARRepository _repository;
  final LocationService _locationService;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;

  Position? _lastPosition;
  double _lastHeading = 0;
  List<ARMarker> _lastFetchedMarkers = [];

  final _controller = StreamController<ARSceneState>.broadcast();
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  ARExplorationService({
    required ARRepository repository,
    LocationService? locationService,
  })  : _repository = repository,
        _locationService = locationService ?? LocationService();

  Stream<ARSceneState> get sceneStream => _controller.stream;

  /// Starts the GPS + compass streams and the initial marker query.
  /// [REQ_101_2] [REQ_101_3] [REQ_101_5] [REQ_101_6]
  Future<void> start() async {
    final initialPosition = await _locationService.getCurrentPosition();
    _lastPosition = initialPosition;
    await _refetchMarkers();

    _positionSub = _locationService.watchPosition().listen((position) async {
      _lastPosition = position;
      await _refetchMarkers();
      _emitScene();
    });

    _compassSub = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) return;
      _lastHeading = heading;
      _throttledEmit();
    });

    _emitScene();
  }

  Future<void> _refetchMarkers() async {
    final pos = _lastPosition;
    if (pos == null) return;
    _lastFetchedMarkers = await _repository.getNearbyMarkers(
      latitude: pos.latitude,
      longitude: pos.longitude,
      radiusMeters: AppConfig.defaultScanRadiusMeters,
    );
  }

  void _throttledEmit() {
    final now = DateTime.now();
    if (now.difference(_lastEmit) < AppConfig.recomputeThrottle) return;
    _lastEmit = now;
    _emitScene();
  }

  /// [REQ_101_5] [REQ_101_6] Recomputes distance/bearing/isFacing for
  /// every fetched marker against the latest GPS fix + compass heading,
  /// filters to activation radius, and picks the primary (most directly
  /// faced) marker.
  void _emitScene() {
    final pos = _lastPosition;
    if (pos == null) {
      _controller.add(ARSceneState.empty);
      return;
    }

    final allWithGeometry = _lastFetchedMarkers
        .map((m) => m.withComputedGeometry(
      userLat: pos.latitude,
      userLng: pos.longitude,
      deviceHeadingDegrees: _lastHeading,
      headingToleranceDegrees: AppConfig.headingToleranceDegrees,
    ))
        .toList();

    final computed = allWithGeometry.where((m) => m.isWithinActivationRadius).toList()
      ..sort((a, b) => (a.distanceMeters ?? double.infinity)
          .compareTo(b.distanceMeters ?? double.infinity));

    // Primary = smallest angular difference to device heading among the
    // markers currently facing (BF-7: "the building the tourist is
    // directly facing").
    ARMarker? primary;
    double bestDiff = double.infinity;
    for (final m in computed) {
      if (!m.isFacing || m.bearingFromUser == null) continue;
      final diff = _angularDiff(_lastHeading, m.bearingFromUser!);
      if (diff < bestDiff) {
        bestDiff = diff;
        primary = m;
      }
    }

    _controller.add(ARSceneState(
      nearbyMarkers: computed,
      primaryMarker: primary,
      deviceHeadingDegrees: _lastHeading,
      userLat: pos.latitude,
      userLng: pos.longitude,
      rawFetchedCount: _lastFetchedMarkers.length,
      allComputedMarkers: allWithGeometry,
    ));
  }

  double _angularDiff(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    await _compassSub?.cancel();
  }

  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _controller.close();
  }
}