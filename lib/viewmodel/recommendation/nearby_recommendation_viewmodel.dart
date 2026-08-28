import 'package:flutter/foundation.dart';

import '../../Model/entities/recommendation.dart';
import '../../Model/repositories/interfaces/recommendation_repository.dart';

class NearbyRecommendationViewModel extends ChangeNotifier {
  final RecommendationRepository _repository;

  NearbyRecommendationViewModel(this._repository);

  bool _isLoading = false;
  String? _errorMessage;
  List<Recommendation> _recommendations = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Recommendation> get recommendations => _recommendations;

  Future<void> loadRecommendations({
    required double latitude,
    required double longitude,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _recommendations =
      await _repository.getNearbyRecommendations(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      _errorMessage = e.toString();
      _recommendations = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshRecommendations({
    required double latitude,
    required double longitude,
  }) async {
    await loadRecommendations(
      latitude: latitude,
      longitude: longitude,
    );
  }
}