import 'package:flutter/foundation.dart';

import '../../core/localization/app_localizations.dart';
import '../../model/business_logic/shared_services/location_service.dart';
import '../../model/entities/ar_object.dart';
import '../../model/entities/ar_recommendation.dart';
import '../../model/repositories/interfaces/recommendation/ar_recommendation_repository.dart';

class ARRecommendationVm extends ChangeNotifier {
  final ARRecommendationRepository _repository;
  final LocationService _locationService;
  final List<String> _cameraMarkerIds;

  ARRecommendationVm(
    this._repository, {
    LocationService? locationService,
    List<String> cameraMarkerIds = const [],
  }) : _locationService = locationService ?? LocationService(),
       _cameraMarkerIds = List.unmodifiable(cameraMarkerIds);

  bool _isVisible = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _expandedAttractionId;
  ARMarker? _currentMarker;
  List<ARRecommendation> _recommendations = const [];

  bool get isVisible => _isVisible;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get expandedAttractionId => _expandedAttractionId;
  List<ARRecommendation> get recommendations =>
      List.unmodifiable(_recommendations);

  Future<void> open(ARMarker marker) async {
    _currentMarker = marker;
    _isVisible = true;
    _errorMessage = null;
    notifyListeners();
    if (_recommendations.isEmpty) await _load(marker);
  }

  void close() {
    _isVisible = false;
    _expandedAttractionId = null;
    notifyListeners();
  }

  void toggleExpanded(String attractionId) {
    _expandedAttractionId = _expandedAttractionId == attractionId
        ? null
        : attractionId;
    notifyListeners();
  }

  Future<void> retry() async {
    final marker = _currentMarker;
    if (marker != null) await _load(marker);
  }

  Future<void> _load(ARMarker marker) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    var latitude = marker.latitude;
    var longitude = marker.longitude;
    try {
      final position = await _locationService.getCurrentPosition().timeout(
        const Duration(seconds: 20),
      );
      latitude = position.latitude;
      longitude = position.longitude;
    } catch (_) {
      // The selected AR marker is a safe location fallback when GPS briefly
      // becomes unavailable while the native AR surface owns the camera.
    }

    try {
      final exclusions = {..._cameraMarkerIds, marker.markerId}.toList();
      _recommendations = await _repository.recommend(
        currentMarkerId: marker.markerId,
        currentAttractionName: marker.name,
        latitude: latitude,
        longitude: longitude,
        excludedMarkerIds: exclusions,
      );
      if (_recommendations.isEmpty) {
        _errorMessage = AppLocalizations.t('ar.noFollowUpAttractions');
      }
    } catch (error) {
      debugPrint('Unable to load AR recommendations: $error');
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
