
import 'package:flutter/foundation.dart';
import '../../core/services/database_manager.dart';
import '../../model/entities/itinerary.dart';
import '../../model/repositories/interfaces/itinerary_repository.dart';
import '../../view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';

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
      : _repository = DatabaseManager().itineraryRepository;

  void _applyFilters() {
    var filtered = List<Itinerary>.from(_allTrips);

    if (_activeFilter != 'All') {
      filtered = filtered.where((itinerary) {
        final resolvedStatus = ItineraryStatusResolver.resolve(
          startDate: itinerary.startDate,
          endDate: itinerary.endDate,
        );

        return resolvedStatus.name.toUpperCase() ==
            _activeFilter.toUpperCase();
      }).toList();
    }

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
      // Local-first read: returns the local cache (which includes any
      // itinerary just saved) and falls back to the remote source when
      // the local cache is empty or unavailable.
      final trips = await _repository.getUserItineraries(userId);

      _allTrips = trips.map((itinerary) {
        final resolvedStatus = ItineraryStatusResolver.resolve(
          startDate: itinerary.startDate,
          endDate: itinerary.endDate,
        );

        return itinerary.copyWith(
          status: resolvedStatus.name.toUpperCase(),
        );
      }).toList();

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