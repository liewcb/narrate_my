import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config/app_config.dart';
import '../../core/services/permission_service.dart';
import '../../model/business_logic/shared_services/location_service.dart';
import '../../model/entities/ar_site.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/recommendation.dart';
import '../../model/repositories/adapters/ar_site_repository_adapter.dart';
import '../../model/repositories/interfaces/ar_site_repository.dart';
import '../../model/repositories/interfaces/recommendation_repository.dart';

class NearbyRecommendationVm extends ChangeNotifier {
  /// REQ_401_9: moving farther than this from the location used for the
  /// current recommendation set triggers a fresh remote recommendation.
  static const double automaticRefreshDistanceKm = 0.5;

  final RecommendationRepository _repository;
  final ARSiteRepository _arSiteRepository;
  final LocationService _locationService;
  final PermissionService _permissionService;

  NearbyRecommendationVm(
    this._repository, {
    ARSiteRepository? arSiteRepository,
    LocationService? locationService,
    PermissionService? permissionService,
  }) : _arSiteRepository =
           arSiteRepository ?? SupabaseARSiteRepositoryAdapter(),
       _locationService = locationService ?? LocationService(),
       _permissionService = permissionService ?? PermissionService();

  bool _isLoading = false;
  String? _errorMessage;
  List<Recommendation> _recommendations = [];
  List<ARSite> _arSites = [];
  Coordinates? _currentLocation;
  bool _hasLocationPermission = false;
  String? _arSitesErrorMessage;
  Coordinates? _recommendationsLocation;
  Coordinates? _queuedMovedLocation;
  StreamSubscription<Position>? _positionSubscription;
  bool _isDisposed = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Recommendation> get recommendations =>
      List.unmodifiable(_recommendations);
  List<ARSite> get arSites => List.unmodifiable(_arSites);
  Coordinates? get currentLocation => _currentLocation;
  bool get hasLocationPermission => _hasLocationPermission;
  String? get arSitesErrorMessage => _arSitesErrorMessage;

  Future<void> loadRecommendations({bool forceRefresh = false}) {
    return _loadRecommendations(forceRefresh: forceRefresh);
  }

  Future<void> _loadRecommendations({
    required bool forceRefresh,
    Coordinates? locationOverride,
  }) async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    _arSitesErrorMessage = null;
    notifyListeners();

    try {
      if (!await _locationService.isLocationServiceEnabled()) {
        throw const _NearbyLocationException(
          'Turn on location services to discover nearby attractions.',
        );
      }

      _hasLocationPermission = await _permissionService.hasLocationPermission();
      if (!_hasLocationPermission) {
        final status = await _permissionService.requestLocation();
        _hasLocationPermission = status.isGranted;
      }
      if (!_hasLocationPermission) {
        throw const _NearbyLocationException(
          'Location permission is required to find nearby attractions.',
        );
      }

      final Coordinates location;
      if (locationOverride != null) {
        location = locationOverride;
      } else {
        final position = await _locationService.getCurrentPosition();
        location = Coordinates(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
      _currentLocation = location;
      _startLocationMonitoring();

      _recommendations = await _repository.getNearbyRecommendations(
        latitude: location.latitude,
        longitude: location.longitude,
        forceRefresh: forceRefresh,
      );
      // The movement threshold is always measured from the position that
      // produced the latest successful recommendation list.
      _recommendationsLocation = location;

      try {
        _arSites = await _arSiteRepository.getNearbySites(
          latitude: location.latitude,
          longitude: location.longitude,
          radiusMeters: AppConfig.nearbyArSiteRadiusMeters,
        );
      } catch (error) {
        // AR discovery is an optional layer. A missing table, temporary
        // network problem, or RLS setup issue must never hide the user's
        // otherwise valid Nearby recommendations.
        debugPrint('Unable to load AR map sites: $error');
        _arSites = [];
        _arSitesErrorMessage = 'AR locations are temporarily unavailable.';
      }
    } catch (e) {
      _errorMessage = e is _NearbyLocationException
          ? e.message
          : e is RecommendationResolutionException
          ? e.message
          : e is RecommendationUnavailableException
          ? e.message
          : 'Unable to load nearby attractions. Please try again.';
    } finally {
      _isLoading = false;
      _notifyIfActive();

      final queuedLocation = _queuedMovedLocation;
      _queuedMovedLocation = null;
      final baseline = _recommendationsLocation;
      if (!_isDisposed &&
          queuedLocation != null &&
          baseline != null &&
          movedBeyondRefreshThreshold(baseline, queuedLocation)) {
        unawaited(
          _loadRecommendations(
            forceRefresh: true,
            locationOverride: queuedLocation,
          ),
        );
      }
    }
  }

  Future<void> refreshRecommendations() =>
      loadRecommendations(forceRefresh: true);

  void _startLocationMonitoring() {
    if (_positionSubscription != null || _isDisposed) return;
    _positionSubscription = _locationService
        .watchPosition(distanceFilterMeters: 100)
        .listen(_handlePositionUpdate, onError: _handlePositionStreamError);
  }

  void _handlePositionUpdate(Position position) {
    if (_isDisposed) return;
    final nextLocation = Coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _currentLocation = nextLocation;
    _notifyIfActive();

    final baseline = _recommendationsLocation;
    if (baseline == null ||
        !movedBeyondRefreshThreshold(baseline, nextLocation)) {
      return;
    }

    if (_isLoading) {
      _queuedMovedLocation = nextLocation;
      return;
    }

    unawaited(
      _loadRecommendations(forceRefresh: true, locationOverride: nextLocation),
    );
  }

  void _handlePositionStreamError(Object error, StackTrace stackTrace) {
    // A temporary live-location failure should not hide recommendations that
    // were already loaded. Manual refresh remains available.
    debugPrint('Unable to monitor recommendation location changes: $error');
  }

  @visibleForTesting
  static bool movedBeyondRefreshThreshold(
    Coordinates previous,
    Coordinates current,
  ) {
    return previous.distanceTo(current) > automaticRefreshDistanceKm;
  }

  void _notifyIfActive() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    super.dispose();
  }
}

class _NearbyLocationException implements Exception {
  final String message;
  const _NearbyLocationException(this.message);
}
