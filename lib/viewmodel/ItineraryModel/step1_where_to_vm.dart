import 'package:flutter/material.dart';

import '../../model/business_logic/itinerary_service/destination_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/destination.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/repositories/adapters/destination_repository_adapter.dart';
import '../../model/repositories/interfaces/destination_repository.dart';


class Step1WhereToViewModel extends ChangeNotifier {
  // ============================================================
  // DEPENDENCIES
  // ============================================================

  final DestinationRepository _repository = DestinationRepositoryImpl();
  late final GetAllDestinationsUseCase _getAllUseCase;
  late final GetPopularDestinationsUseCase _popularUseCase;

  Step1WhereToViewModel() {
    _getAllUseCase = GetAllDestinationsUseCase(_repository);
    _popularUseCase = GetPopularDestinationsUseCase(_repository);
  }

  // ============================================================
  // STATE
  // ============================================================

  List<Destination> _allDestinations = [];
  List<Destination> _filteredDestinations = [];
  List<Destination> _selectedDestinations = [];
  List<Destination> _popularDestinations = [];
  bool _isLoading = false;
  String _searchQuery = '';

  // ============================================================
  // GETTERS
  // ============================================================

  List<Destination> get filteredDestinations => _filteredDestinations;
  List<Destination> get selectedDestinations => _selectedDestinations;
  List<Destination> get popularDestinations => _popularDestinations;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  bool isSelected(Destination destination) {
    return _selectedDestinations.any((d) => d.destinationId == destination.destinationId);
  }

  bool get canProceed => _selectedDestinations.isNotEmpty;

  String? get proceedError {
    if (_selectedDestinations.isEmpty) {
      return 'Please select at least one destination.';
    }
    return null;
  }

  int get selectedCount => _selectedDestinations.length;
  bool get canContinue => _selectedDestinations.isNotEmpty;

  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> loadDestinations() async {
    _isLoading = true;
    notifyListeners();

    try {
      _allDestinations = await _getAllUseCase.execute();
      _popularDestinations = await _popularUseCase.execute(limit: 6);
      _filteredDestinations = List.from(_allDestinations);
    } catch (e) {
      debugPrint('Error loading destinations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void searchDestinations(String query) {
    _searchQuery = query;
    if (query.isEmpty) {
      _filteredDestinations = List.from(_allDestinations);
    } else {
      _filteredDestinations = _allDestinations
          .where((d) => d.destinationName
          .toLowerCase()
          .contains(query.toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  void toggleSelection(Destination destination) {
    if (isSelected(destination)) {
      _selectedDestinations
          .removeWhere((d) => d.destinationId == destination.destinationId);
    } else {
      if (_selectedDestinations.length >= 5) return;
      _selectedDestinations.add(destination);
    }
    notifyListeners();
  }

  void removeSelection(String destinationId) {
    _selectedDestinations
        .removeWhere((d) => d.destinationId == destinationId);
    notifyListeners();
  }

  void clearSelections() {
    _selectedDestinations.clear();
    notifyListeners();
  }

  List<String> getSelectedIds() {
    return _selectedDestinations.map((d) => d.destinationId).toList();
  }

  List<String> getSelectedNames() {
    return _selectedDestinations.map((d) => d.destinationName).toList();
  }

  /// Build a [TripDraft] for the next wizard step. Throws a [StateError]
  /// if no destination is selected so the caller can surface the error.
  TripDraft buildTripDraft() {
    if (_selectedDestinations.isEmpty) {
      throw StateError('Please select at least one destination.');
    }
    // Carry the destination coordinates (resolved from the DB) forward
    // so Step 5 can search Google Places without a hardcoded map.
    final coords = <String, Coordinates>{
      for (final d in _selectedDestinations)
        if (d.latitude != null && d.longitude != null)
          d.destinationName:
              Coordinates(latitude: d.latitude!, longitude: d.longitude!),
    };
    return TripDraft(
      destinations: getSelectedNames(),
      destinationCoordinates: coords,
    );
  }

}