// lib/viewmodel/Itinerary/view_place_detail_vm.dart
import 'package:flutter/foundation.dart';

import '../../core/services/database_manager.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';

/// Loads and exposes the [Place] shown by the View Place Detail screen.
///
/// If an already-joined [initialPlace] is supplied (e.g. the stop's cached
/// `Place`), it is shown immediately and the repository refresh happens in
/// the background. Otherwise the place is resolved via [PlaceRepositoryAdapter]
/// using the unique `placeId`.
class ViewPlaceDetailViewModel extends ChangeNotifier {
  final String _placeId;
  final PlaceRepositoryAdapter _placeRepo;
  final ValueChanged<bool>? _onStatusChanged; // new

  Place? _place;
  bool _isLoading = false;
  String? _error;
  bool _isStopped = false; // new

  ViewPlaceDetailViewModel({
    required String placeId,
    Place? initialPlace,
    PlaceRepositoryAdapter? placeRepo,
    ValueChanged<bool>? onStatusChanged, // new
  })  : _placeId = placeId,
        _placeRepo = placeRepo ?? DatabaseManager().placeRepository,
        _place = initialPlace,
        _onStatusChanged = onStatusChanged;

  // ─── Getters ────────────────────────────────────────────────

  Place? get place => _place;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isStopped => _isStopped; // new

  // ─── Load ───────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = _place == null;
    _error = null;
    notifyListeners();

    try {
      final place = await _placeRepo.getPlace(_placeId);
      if (place != null) {
        _place = place;
        _error = null;
      } else if (_place == null) {
        _error = 'Place information is unavailable.';
      }
    } catch (e) {
      debugPrint('[ViewPlaceDetailVM] Failed to load place: $e');
      if (_place == null) {
        _error = 'Unable to load place information. Please try again.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  // ─── Toggle status ──────────────────────────────────────────

  void toggleStopped() {
    _isStopped = !_isStopped;
    _onStatusChanged?.call(_isStopped);
    notifyListeners();
  }
}