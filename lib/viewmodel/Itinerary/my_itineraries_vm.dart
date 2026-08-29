// lib/viewmodel/ItineraryModel/my_itineraries_vm.dart
import 'package:flutter/foundation.dart';
import '../../model/entities/itinerary.dart';
import '../../model/repositories/adapters/itinerary_repository_adapter.dart';
import '../../model/repositories/interfaces/itinerary_repository.dart';

class MyItinerariesVM extends ChangeNotifier {
  final ItineraryRepository _repository;
  final String userId;

  List<Itinerary> _allTrips = [];
  List<Itinerary> _filteredTrips = [];
  String _searchQuery = '';
  String _activeFilter = 'All';
  bool _isLoading = false;
  String? _error;

  List<Itinerary> get filteredTrips => _filteredTrips;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get activeFilter => _activeFilter;

  MyItinerariesVM({required this.userId})
      : _repository = ItineraryRepositoryImpl();

  void _applyFilters() {
    var filtered = List<Itinerary>.from(_allTrips);

    // Filter by status
    if (_activeFilter != 'All') {
      filtered = filtered.where((t) => t.status == _activeFilter.toUpperCase()).toList();
    }

    // Filter by search query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered
          .where((t) => t.title.toLowerCase().contains(q))
          .toList();
    }

    _filteredTrips = filtered;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void setFilter(String filter) {
    _activeFilter = filter;
    _applyFilters();
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Remote-first: pull from Supabase, then cache locally (best-effort).
      _allTrips = await _repository.fetchUserItinerariesFromRemote(userId);
      _applyFilters();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Force a pull from the remote source (pull-to-refresh).
  Future<void> refresh() => load();
}