import 'package:flutter/material.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/destination_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/destination.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/repositories/interfaces/destination_repository.dart';

class Step1WhereToViewModel extends ChangeNotifier {
  static const int maxDestinations = 2;

  final DestinationRepository _repository = DatabaseManager().destinationRepository;
  late final GetAllDestinationsUseCase _getAllUseCase;
  late final GetPopularDestinationsUseCase _popularUseCase;

  Step1WhereToViewModel() {
    _getAllUseCase = GetAllDestinationsUseCase(_repository);
    _popularUseCase = GetPopularDestinationsUseCase(_repository);
  }

  TripDraft _draft = TripDraft.empty();
  List<Destination> _allDestinations = [];
  List<Destination> _filteredDestinations = [];
  List<Destination> _selectedDestinations = [];
  List<Destination> _popularDestinations = [];
  bool _isLoading = false;
  String _searchQuery = '';

  List<Destination> get filteredDestinations => _filteredDestinations;
  List<Destination> get selectedDestinations => _selectedDestinations;
  List<Destination> get popularDestinations => _popularDestinations;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  bool isSelected(Destination destination) {
    return _selectedDestinations.any((d) => d.destinationId == destination.destinationId);
  }

  bool get canProceed => _selectedDestinations.isNotEmpty;
  int get selectedCount => _selectedDestinations.length;
  bool get canContinue => _selectedDestinations.isNotEmpty;

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
          .where((d) => d.destinationName.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  bool toggleSelection(Destination destination) {
    if (isSelected(destination)) {
      _selectedDestinations.removeWhere((d) => d.destinationId == destination.destinationId);
    } else {
      if (_selectedDestinations.length >= maxDestinations) return false;
      _selectedDestinations.add(destination);
    }
    _draft = _draft.copyWith(destinations: List.of(_selectedDestinations));
    notifyListeners();
    return true;
  }

  void removeSelection(String destinationId) {
    _selectedDestinations.removeWhere((d) => d.destinationId == destinationId);
    _draft = _draft.copyWith(destinations: List.of(_selectedDestinations));
    notifyListeners();
  }

  void clearSelections() {
    _selectedDestinations.clear();
    _draft = _draft.copyWith(destinations: []);
    notifyListeners();
  }

  List<String> getSelectedIds() {
    return _selectedDestinations.map((d) => d.destinationId).toList();
  }

  List<String> getSelectedNames() {
    return _selectedDestinations.map((d) => d.destinationName).toList();
  }

  TripDraft buildTripDraft() {
    if (_selectedDestinations.isEmpty) {
      throw StateError('Please select at least one destination.');
    }
    final coords = <String, Coordinates>{
      for (final d in _selectedDestinations)
        if (d.latitude != null && d.longitude != null)
          d.destinationName: Coordinates(latitude: d.latitude!, longitude: d.longitude!),
    };
    final draft = _draft.copyWith(
      destinations: List.of(_selectedDestinations),
      destinationCoordinates: coords,
    );
    return draft;
  }
}