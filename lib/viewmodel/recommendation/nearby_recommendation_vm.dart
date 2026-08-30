import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/permission_service.dart';
import '../../model/business_logic/shared_services/location_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/recommendation.dart';
import '../../model/repositories/interfaces/recommendation_repository.dart';

class NearbyRecommendationVm extends ChangeNotifier {
  final RecommendationRepository _repository;
  final LocationService _locationService;
  final PermissionService _permissionService;

  NearbyRecommendationVm(
    this._repository, {
    LocationService? locationService,
    PermissionService? permissionService,
  }) : _locationService = locationService ?? LocationService(),
       _permissionService = permissionService ?? PermissionService();

  bool _isLoading = false;
  String? _errorMessage;
  List<Recommendation> _recommendations = [];
  Coordinates? _currentLocation;
  bool _hasLocationPermission = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Recommendation> get recommendations =>
      List.unmodifiable(_recommendations);
  Coordinates? get currentLocation => _currentLocation;
  bool get hasLocationPermission => _hasLocationPermission;

  Future<void> loadRecommendations({bool forceRefresh = false}) async {
    _isLoading = true;
    _errorMessage = null;
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
