import 'package:flutter/foundation.dart';
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

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Recommendation> get recommendations =>
      List.unmodifiable(_recommendations);
  List<ARSite> get arSites => List.unmodifiable(_arSites);
  Coordinates? get currentLocation => _currentLocation;
  bool get hasLocationPermission => _hasLocationPermission;
  String? get arSitesErrorMessage => _arSitesErrorMessage;

  Future<void> loadRecommendations({bool forceRefresh = false}) async {
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

      final position = await _locationService.getCurrentPosition();
      _currentLocation = Coordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      _recommendations = await _repository.getNearbyRecommendations(
        latitude: position.latitude,
        longitude: position.longitude,
        forceRefresh: forceRefresh,
      );

      try {
        _arSites = await _arSiteRepository.getNearbySites(
          latitude: position.latitude,
          longitude: position.longitude,
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
      notifyListeners();
    }
  }

  Future<void> refreshRecommendations() =>
      loadRecommendations(forceRefresh: true);
}

class _NearbyLocationException implements Exception {
  final String message;
  const _NearbyLocationException(this.message);
}
