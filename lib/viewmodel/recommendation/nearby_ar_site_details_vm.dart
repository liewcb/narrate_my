import 'package:flutter/foundation.dart';

import '../../model/entities/ar_site.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/interfaces/ar_exploration/ar_site_place_repository.dart';

class NearbyArSiteDetailsVm extends ChangeNotifier {
  final ARSitePlaceRepository _repository;

  NearbyArSiteDetailsVm(this._repository);

  Place? _place;
  bool _isLoading = true;
  bool _hasStarted = false;
  String? _errorMessage;
  bool _isDisposed = false;

  Place? get place => _place;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load(ARSite site) async {
    if (_hasStarted) return;
    _hasStarted = true;
    _errorMessage = null;

    try {
      _place = await _repository.resolvePlace(site);
    } catch (error) {
      debugPrint('Unable to resolve Nearby AR site place: $error');
      _place = null;
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      _notifyIfActive();
    }
  }

  void _notifyIfActive() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
