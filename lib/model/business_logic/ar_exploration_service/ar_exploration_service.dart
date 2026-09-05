import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/config/app_config.dart';
import '../../entities/ar_object.dart';
import '../../repositories/interfaces/ar_repository.dart';
import '../shared_services/location_service.dart';
import '../../../core/services/orientation_service.dart';

/// Two-band grouping of nearby markers for the "Nearby Attractions" list
/// UI. This is a plain straight-line distance cut, independent of each
/// marker's own [ARMarker.activationRadiusMeters] — that field only
/// governs the AR camera overlay / notification banner (see
/// [ARSceneState.nearbyMarkers]). Both bands are sorted nearest-first.
class NearbyAttractionsSections {
  /// Attractions with a direct distance under
  /// [ARExplorationService.veryNearRadiusMeters] (currently 80m).
  final List<ARMarker> veryNear;

  /// Attractions with a direct distance at or beyond [veryNear]'s cutoff
  /// but under [ARExplorationService.nearRadiusMeters] (currently 150m).
  final List<ARMarker> near;

  const NearbyAttractionsSections({
    this.veryNear = const [],
    this.near = const [],
  });

  static const empty = NearbyAttractionsSections();
}

/// Immutable snapshot of the AR scene at a point in time — what the View
/// actually renders.
class ARSceneState {
  /// All markers within scan radius AND within their own activation
  /// radius, sorted nearest-first. (BF-4, BF-5 minus the notification UI).
  final List<ARMarker> nearbyMarkers;

  /// The two-band (<80m / <150m) grouping for the Nearby Attractions list
  /// panel, with direct distances already computed on each [ARMarker].
  final NearbyAttractionsSections nearbyAttractions;

  /// The single marker the tourist is currently directly facing, if any
  /// (BF-6, BF-7). Null when no marker is within heading tolerance.
  final ARMarker? primaryMarker;

  final double deviceHeadingDegrees;

  /// Live device pitch in degrees (0 = held level at the horizon, see
  /// [OrientationService]). Used by the overlay to hide markers when the
  /// tourist points the camera at the ground or the sky.
  final double devicePitchDegrees;

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
    this.nearbyAttractions = NearbyAttractionsSections.empty,
    required this.primaryMarker,
    required this.deviceHeadingDegrees,
    this.devicePitchDegrees = 0,
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
/// Permission checking is NOT this class's job (see
/// `core/services/permission_service.dart` + the ViewModel, which gate
/// entry before this service is ever started) — this only runs once the
/// tourist has already granted camera + location.
///
/// Emits [ARSceneState] any time the tourist's position or heading
/// changes meaningfully.
class ARExplorationService {
  final ARRepository _repository;
  final LocationService _locationService;
  final OrientationService _orientationService;

  /// Cutoff (meters) for the "very near" section of the Nearby
  /// Attractions list.
  static const double veryNearRadiusMeters = 80;

  /// Cutoff (meters) for the "near" section of the Nearby Attractions
  /// list. Markers between [veryNearRadiusMeters] and this value fall
  /// into the second section; anything beyond this isn't listed.
  static const double nearRadiusMeters = 150;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<double>? _pitchSub;

  Position? _lastPosition;
  double _lastHeading = 0;
  double _lastPitch = 0;
  List<ARMarker> _lastFetchedMarkers = [];

  final _controller = StreamController<ARSceneState>.broadcast();
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  ARExplorationService({
    required ARRepository repository,
    LocationService? locationService,
    OrientationService? orientationService,
  })  : _repository = repository,
        _locationService = locationService ?? LocationService(),
        _orientationService = orientationService ?? OrientationService();

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

    _pitchSub = _orientationService.pitchStream.listen((pitch) {
      _lastPitch = pitch;
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

    final nearbyAttractions = _buildNearbyAttractionsSections(allWithGeometry);

    // Primary = smallest angular difference to device heading among the
    // markers currently facing (BF-7: "the building the tourist is
    // directly facing"). Skipped entirely while the phone is pitched
    // beyond tolerance (pointing at the sky/ground) — there's nothing
    // to "directly face" in that pose.
    final isLookingForward = _lastPitch.abs() <= AppConfig.pitchToleranceDegrees;
    ARMarker? primary;
    if (isLookingForward) {
      double bestDiff = double.infinity;
      for (final m in computed) {
        if (!m.isFacing || m.bearingFromUser == null) continue;
        final diff = _angularDiff(_lastHeading, m.bearingFromUser!);
        if (diff < bestDiff) {
          bestDiff = diff;
          primary = m;
        }
      }
    }

    _controller.add(ARSceneState(
      nearbyMarkers: computed,
      nearbyAttractions: nearbyAttractions,
      primaryMarker: primary,
      deviceHeadingDegrees: _lastHeading,
      devicePitchDegrees: _lastPitch,
      userLat: pos.latitude,
      userLng: pos.longitude,
      rawFetchedCount: _lastFetchedMarkers.length,
      allComputedMarkers: allWithGeometry,
    ));
  }

  /// Splits every geometry-computed marker into the two Nearby
  /// Attractions list bands by straight-line distance
  /// ([veryNearRadiusMeters] / [nearRadiusMeters]), each sorted
  /// nearest-first. Unlike [nearbyMarkers], this ignores each marker's
  /// own `activationRadiusMeters` — it's a flat distance cut for the
  /// list UI, not the AR overlay eligibility check.
  NearbyAttractionsSections _buildNearbyAttractionsSections(List<ARMarker> allWithGeometry) {
    final withDistance = allWithGeometry.where((m) => m.distanceMeters != null).toList()
      ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));

    // TEMP DEBUG: dumps every fetched marker's name + computed direct
    // (haversine) distance, in meters, every time this recomputes. Compare
    // these numbers against Google Maps' measure-distance tool for the
    // same marker coordinates and your live GPS fix (userLat/userLng in
    // ARSceneState) to see whether a mismatch is a bad marker coordinate,
    // stale GPS, or a real bug. Remove once confirmed.
    debugPrint('[NearbyAttractions] --- recompute ---');
    for (final m in withDistance) {
      debugPrint(
          '[NearbyAttractions] ${m.name} (id=${m.markerId}) '
              'lat=${m.latitude}, lng=${m.longitude} '
              '-> distance=${m.distanceMeters!.toStringAsFixed(1)}m');
    }

    final veryNear = withDistance.where((m) => m.distanceMeters! < veryNearRadiusMeters).toList();

    final near = withDistance
        .where((m) =>
    m.distanceMeters! >= veryNearRadiusMeters && m.distanceMeters! < nearRadiusMeters)
        .toList();

    debugPrint(
        '[NearbyAttractions] veryNear(<${veryNearRadiusMeters}m)=${veryNear.length}, '
            'near(${veryNearRadiusMeters}-${nearRadiusMeters}m)=${near.length}');

    return NearbyAttractionsSections(veryNear: veryNear, near: near);
  }

  double _angularDiff(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    await _compassSub?.cancel();
    await _pitchSub?.cancel();
  }

  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _pitchSub?.cancel();
    _controller.close();
  }
}