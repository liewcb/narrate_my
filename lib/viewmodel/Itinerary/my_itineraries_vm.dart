import 'package:flutter/foundation.dart';
import '../../core/services/database_manager.dart';
import '../../model/entities/itinerary.dart';
import '../../model/repositories/interfaces/itinerary/itinerary_repository.dart';
import '../../view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';

/// Sorting options available to the traveler.
enum ItinerarySortOption {
  currentDay,
  latestCreated,
}

class MyItinerariesVM extends ChangeNotifier {
  final ItineraryRepository _repository;
  final String userId;

  List<Itinerary> _allTrips = [];
  List<Itinerary> _filteredTrips = [];
  String _searchQuery = '';
  String _activeFilter = 'All';
  bool _isLoading = false;
  String? _error;

  // Default sorting.
  ItinerarySortOption _sortOption = ItinerarySortOption.currentDay;

  List<Itinerary> get filteredTrips => _filteredTrips;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get activeFilter => _activeFilter;
  ItinerarySortOption get sortOption => _sortOption;

  MyItinerariesVM({required this.userId})
      : _repository = DatabaseManager().itineraryRepository;

  // ============================================================
  // FILTER + SORT
  // ============================================================

  void _applyFilters() {
    var filtered = List<Itinerary>.from(_allTrips);

    // ------------------------------------------------------------
    // 1. STATUS FILTER
    // ------------------------------------------------------------
    if (_activeFilter != 'All') {
      filtered = filtered.where((itinerary) {
        final resolvedStatus = ItineraryStatusResolver.resolve(
          startDate: itinerary.startDate,
          endDate: itinerary.endDate,
        );
        return resolvedStatus.name.toUpperCase() == _activeFilter.toUpperCase();
      }).toList();
    }

    // ------------------------------------------------------------
    // 2. SEARCH FILTER
    // ------------------------------------------------------------
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered
          .where(
            (itinerary) => itinerary.title.toLowerCase().contains(q),
      )
          .toList();
    }

    // ------------------------------------------------------------
    // 3. SORT
    // ------------------------------------------------------------
    switch (_sortOption) {
      case ItinerarySortOption.currentDay:
        _sortByCurrentDay(filtered);
        break;
      case ItinerarySortOption.latestCreated:
        _sortByLatestCreated(filtered);
        break;
    }

    _filteredTrips = filtered;
  }

  // ============================================================
  // CURRENT DAY SORTING
  // ============================================================

  void _sortByCurrentDay(List<Itinerary> trips) {
    trips.sort((a, b) {
      final priorityA = _getStatusPriority(a);
      final priorityB = _getStatusPriority(b);

      // Ongoing → Upcoming → Past
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }

      final status = ItineraryStatusResolver.resolve(
        startDate: a.startDate,
        endDate: a.endDate,
      ).name.toUpperCase();

      // ----------------------------------------------------------
      // ONGOING
      // ----------------------------------------------------------
      // For ongoing itineraries, the one whose start date is
      // closest to today is shown first.
      // ----------------------------------------------------------
      if (status == 'ONGOING') {
        return a.startDate.compareTo(b.startDate);
      }

      // ----------------------------------------------------------
      // UPCOMING
      // ----------------------------------------------------------
      // Earliest upcoming trip first.
      // ----------------------------------------------------------
      if (status == 'UPCOMING') {
        return a.startDate.compareTo(b.startDate);
      }

      // ----------------------------------------------------------
      // PAST
      // ----------------------------------------------------------
      // Most recently completed trip first.
      return b.endDate.compareTo(a.endDate);
    });
  }

  // ============================================================
  // LATEST CREATED SORTING
  // ============================================================

  void _sortByLatestCreated(List<Itinerary> trips) {
    /*
     * IMPORTANT:
     *
     * Replace `createdAt` below with the actual creation/generated
     * timestamp field from your Itinerary model.
     *
     * Example:
     *
     * return b.createdAt.compareTo(a.createdAt);
     *
     * If your model uses `generatedAt`, use:
     *
     * return b.generatedAt.compareTo(a.generatedAt);
     *
     * Do NOT use startDate/endDate here because those represent
     * the travel period, not when the itinerary was generated.
     */
    trips.sort((a, b) {
      // TEMPORARY FALLBACK:
      //
      // Until the actual Itinerary creation timestamp is confirmed,
      // use itinerary start date as the fallback.
      //
      // Once the real createdAt/generatedAt field is confirmed,
      // replace this with that field.
      return b.startDate.compareTo(a.startDate);
    });
  }

  // ============================================================
  // STATUS PRIORITY
  // ============================================================

  int _getStatusPriority(Itinerary itinerary) {
    final resolvedStatus = ItineraryStatusResolver.resolve(
      startDate: itinerary.startDate,
      endDate: itinerary.endDate,
    );
    final status = resolvedStatus.name.toUpperCase();

    switch (status) {
      case 'ONGOING':
        return 0;
      case 'UPCOMING':
        return 1;
      case 'PAST':
        return 2;
      default:
        return 3;
    }
  }

  // ============================================================
  // CHANGE SORT OPTION
  // ============================================================

  void setSortOption(ItinerarySortOption option) {
    if (_sortOption == option) {
      return;
    }
    _sortOption = option;
    // Reapply current search/filter using the new sorting.
    _applyFilters();
    notifyListeners();
  }

  // ============================================================
  // SEARCH
  // ============================================================

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  // ============================================================
  // STATUS FILTER
  // ============================================================

  void setFilter(String filter) {
    _activeFilter = filter;
    _applyFilters();
    notifyListeners();
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final trips = await _repository.getUserItineraries(userId);

      // Recalculate itinerary status.
      final synced = <Itinerary>[];
      for (final trip in trips) {
        synced.add(
          await _repository.refreshItineraryStatus(trip),
        );
      }

      _allTrips = synced;
      // Apply the currently selected sorting option.
      _applyFilters();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Force a pull from the remote source.
  Future<void> refresh() => load();
}