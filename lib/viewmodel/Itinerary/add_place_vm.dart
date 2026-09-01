import 'package:flutter/foundation.dart';
import '../../core/services/database_manager.dart';
import '../../core/config/itinerary_constants.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/interfaces/itinerary_stop_repository.dart';

/// A candidate place the user can add to a day of a generated itinerary.
class AddPlaceOption {
  final String placeId;
  final String name;
  final String category;
  final String? imageUrl;
  final int durationMinutes;

  const AddPlaceOption({
    required this.placeId,
    required this.name,
    required this.category,
    this.imageUrl,
    required this.durationMinutes,
  });
}

/// Result of trying to add places to a day.
class AddPlaceResult {
  final bool success;
  final String? message;
  final List<ItineraryStop> addedStops;

  const AddPlaceResult({
    required this.success,
    this.message,
    this.addedStops = const [],
  });
}

/// ViewModel for "Add a Place" after the itinerary has been generated.
///
/// Flow: View → VM → [ItineraryStopRepository] → local + remote database.
///
/// It loads the stops already scheduled for the chosen day, computes how
/// much free time remains inside the exploration window, lets the user
/// pick candidates, and on save creates new [ItineraryStop] rows with
/// conflict detection against the existing schedule.
class AddPlaceVM extends ChangeNotifier {
  final String itineraryId;
  final int dayIndex;
  final String explorationTime;
  final ItineraryStopRepository _stopRepository;

  AddPlaceVM({
    required this.itineraryId,
    required this.dayIndex,
    required this.explorationTime,
    ItineraryStopRepository? stopRepository,
  }) : _stopRepository =
            stopRepository ?? DatabaseManager().itineraryStopRepository;

  // ─── Existing schedule ──────────────────────────────────────
  List<ItineraryStop> _existingStops = [];
  bool isLoadingStops = false;
  String? loadError;

  List<ItineraryStop> get existingStops => List.unmodifiable(_existingStops);

  // ─── Candidates & selection ─────────────────────────────────
  final List<AddPlaceOption> candidates = [
    AddPlaceOption(
      placeId: 'central_market',
      name: 'Central Market',
      category: 'Cultural center & shopping',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBgHNdDNXIpGiyneP5zyPFZwuYYaJr6nYVeovUv6YncvycE5pQOqP6ehaGrg2D9xiXEWDxkHAY9dI8Uf4VWN3JYNpAJ4uB6xtvX--FB-AlzakmfqFT6I3jCMPHS9eyWsoGRlt0yzc786tC5p4Adksg6fFfRJ6vDzKF6hq_0iq3V4xqqD9UmIMsY3EhWipclV3i8BX3za2vLLVxfCqhkXVT2C2fwNfrQUy4fu59qLqw8Ke8aJviENCQ4',
      durationMinutes: 60,
    ),
    AddPlaceOption(
      placeId: 'kl_tower',
      name: 'KL Tower',
      category: 'Observation deck views',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuB50EZNAZuVKk0R6JQrKjreuxRZNi9eOUV3exePGJtnCPExi2mCgTyjnds5T8hj3usMqgRUgy1xzhZ35lMFxQqaHQjUPLWarCSDj2Z4QlAQyNu5sHn1a-AzpiAxdfsxTxBZ3bBP0PPxn9g6YbJothsvIqwyswkFWPmLKE8IxOe7J9StbAGRf3l7SmKGn5P8thy_VVhioxrnC1UTe6f9AKfBY6HrgcYl_W14YmKCqQ-zf2k4jMrTfxId',
      durationMinutes: 90,
    ),
    AddPlaceOption(
      placeId: 'islamic_arts_museum',
      name: 'Islamic Arts Museum',
      category: 'Extensive art collection',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuCnOtY7sYmHJLJNxYA0CLPxNoFXPTr1QkWPVkvx_cmT5i2KJr7-E6XoYTzGHr6HBwmrcrRb9kC0haOFTbfJGKuni_1OUDfu1XxDBYadlW_BTbfOrP1h0gVf7_9n2bigKO9DcO_0xL-egxZSFz7Vp30sXtMoojVqkK6OLUKT67EUQEf0rRjXc2hqQbFjXUxEndts9xeowSaR3Ql04tRr6GgCsGJCdgeqJDYPES3Tx1kMeo4ifSG4-MCM',
      durationMinutes: 120,
    ),
  ];

  final Set<String> _selectedPlaceIds = {};
  Set<String> get selectedPlaceIds => Set.unmodifiable(_selectedPlaceIds);

  bool isSelected(String placeId) => _selectedPlaceIds.contains(placeId);

  void toggleSelection(String placeId) {
    if (_selectedPlaceIds.contains(placeId)) {
      _selectedPlaceIds.remove(placeId);
    } else {
      _selectedPlaceIds.add(placeId);
    }
    notifyListeners();
  }

  // ─── Derived schedule info ──────────────────────────────────
  bool isSaving = false;
  String? saveError;

  /// Total free minutes left in the day's exploration window.
  int get availableMinutes {
    final window = _window;
    if (_existingStops.isEmpty) return window.totalMinutes;

    final lastEnd = _existingStops
        .map((s) => _minutesOfDay(s.endTime))
        .reduce((a, b) => a > b ? a : b);
    return (window.endHour * 60 + window.endMinute) - lastEnd;
  }

  ExplorationWindow get _window =>
      ItineraryConstants.explorationWindows[explorationTime] ??
      ItineraryConstants.explorationWindows['Standard']!;

  int _minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

  // ─── Load ───────────────────────────────────────────────────
  Future<void> load() async {
    isLoadingStops = true;
    loadError = null;
    notifyListeners();
    try {
      final all = await _stopRepository.getStopsForItinerary(itineraryId);
      _existingStops = all.where((s) => s.dayIndex == dayIndex).toList()
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    } catch (e) {
      loadError = e.toString();
    } finally {
      isLoadingStops = false;
      notifyListeners();
    }
  }

  // ─── Validation ─────────────────────────────────────────────
  /// Business rules: at least one place selected, and each selected
  /// candidate must fit inside the remaining exploration window.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (_selectedPlaceIds.isEmpty) {
      errors['selection'] = 'Select at least one place to add.';
      return errors;
    }

    final selectedTotal = candidates
        .where((c) => _selectedPlaceIds.contains(c.placeId))
        .fold(0, (sum, c) => sum + c.durationMinutes);

    // Allow a small buffer between stops.
    final needed = selectedTotal +
        ItineraryConstants.bufferMinutes * _selectedPlaceIds.length;
    if (needed > availableMinutes) {
      errors['time'] =
          'Not enough time left (${availableMinutes} min free, need $needed min). '
          'Try fewer or shorter places.';
    }
    return errors;
  }

  // ─── Save ───────────────────────────────────────────────────
  /// Persist each selected place as a new [ItineraryStop] appended to
  /// the day, using the next available start time and stop order.
  Future<AddPlaceResult> addPlaces() async {
    final errors = validate();
    if (errors.isNotEmpty) {
      return AddPlaceResult(success: false, message: errors.values.first);
    }

    isSaving = true;
    saveError = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final added = <ItineraryStop>[];

      // Base time: after the last existing stop (or window start).
      var cursor = _nextCursor();
      var nextOrder = _nextStopOrder();

      for (final candidate in candidates.where(
        (c) => _selectedPlaceIds.contains(c.placeId),
      )) {
        final start = cursor;
        final end = start.add(Duration(minutes: candidate.durationMinutes));

        final stop = ItineraryStop(
          stopId: 0, // server-assigned
          itineraryId: itineraryId,
          placeId: candidate.placeId,
          dayIndex: dayIndex,
          stopOrder: nextOrder++,
          startTime: start,
          endTime: end,
          durationMinutes: candidate.durationMinutes,
          stopStatus: 'PLANNED',
          createdAt: now,
          updatedAt: now,
        );

        final saved = await _stopRepository.addStop(stop);
        added.add(saved);

        // Advance cursor with a travel buffer between stops.
        cursor = end.add(
          Duration(minutes: ItineraryConstants.bufferMinutes),
        );
      }

      _existingStops = [..._existingStops, ...added]
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      _selectedPlaceIds.clear();

      return AddPlaceResult(success: true, addedStops: added);
    } catch (e) {
      saveError = e.toString();
      return AddPlaceResult(success: false, message: 'Failed to add: $e');
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  DateTime _nextCursor() {
    final window = _window;
    if (_existingStops.isEmpty) {
      return DateTime(
        2024, 1, 1, window.startHour, window.startMinute,
      );
    }
    final last = _existingStops.last;
    return last.endTime.add(
      Duration(minutes: ItineraryConstants.bufferMinutes),
    );
  }

  int _nextStopOrder() {
    if (_existingStops.isEmpty) return 0;
    return _existingStops
            .map((s) => s.stopOrder)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }
}
