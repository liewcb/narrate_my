// lib/viewmodel/Itinerary/itinerary_final_vm.dart
import 'package:flutter/foundation.dart';

import '../../core/config/api_keys.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_destination.dart';
import '../../model/entities/itinerary_must_visit.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';

class ItineraryFinalViewModel extends ChangeNotifier {
  final ItineraryResult _result;
  final String _title;
  final String? _itineraryId;
  final String _explorationTime;
  final List<String> _mustVisitPlaceIds;
  final DateTime _tripStartDate;
  final Future<void> Function()? _regenerateRequest;
  final Future<ItineraryResult> Function()? _regenerateAlternatives;
  final String _userId;
  final TripDraft? _draft;

  String? _savedItineraryId;

  // State
  bool _isLoading = false;
  bool _isRegenerating = false;
  bool _isSaving = false;
  bool _isSaved = false;
  String? _errorMessage;
  String? _saveMessage;
  int _selectedDayIndex = 0;

  ItineraryFinalViewModel({
    required ItineraryResult result,
    required String title,
    String? itineraryId,
    String explorationTime = 'Standard',
    List<String> mustVisitPlaceIds = const [],
    required DateTime tripStartDate,
    Future<void> Function()? regenerateRequest,
    Future<ItineraryResult> Function()? regenerateAlternatives,
    String userId = '',
    TripDraft? draft,
  })  : _result = result,
        _title = title,
        _itineraryId = itineraryId,
        _explorationTime = explorationTime,
        _mustVisitPlaceIds = mustVisitPlaceIds,
        _tripStartDate = tripStartDate,
        _regenerateRequest = regenerateRequest,
        _regenerateAlternatives = regenerateAlternatives,
        _userId = userId,
        _draft = draft,
        _savedItineraryId = null;

  // ─── Getters ────────────────────────────────────────────────

  ItineraryResult get result => _result;
  String get title => _title;
  String? get itineraryId => _itineraryId;
  String get explorationTime => _explorationTime;
  List<String> get mustVisitPlaceIds => _mustVisitPlaceIds;
  DateTime get tripStartDate => _tripStartDate;

  /// The traveler's wizard draft (transport mode, interests, etc.).
  TripDraft? get draft => _draft;
  bool get isLoading => _isLoading;
  bool get isRegenerating => _isRegenerating;
  bool get isSaving => _isSaving;
  bool get isSaved => _isSaved;
  String? get errorMessage => _errorMessage;
  String? get saveMessage => _saveMessage;
  int get selectedDayIndex => _selectedDayIndex;
  bool get isSaveInProgress => _isSaving;

  /// The ID of the persisted itinerary (available after a successful save).
  String? get savedItineraryId => _savedItineraryId;

  bool get canSave {
    if (_result.scheduledDays == null || _result.scheduledDays!.isEmpty) return false;
    if (_result.scheduledDays!.any((day) => day.stops.isEmpty)) return false;
    return true;
  }

  bool get canRegenerate => _regenerateRequest != null && !_isRegenerating;

  List<DayData> get days {
    if (_result.scheduledDays == null) return [];
    return _result.scheduledDays!.map((day) {
      return DayData(
        dayNumber: day.dayIndex + 1,
        date: _formatDate(day.date),
        stops: day.stops.map((stop) {
          final place = stop.attraction.place;
          return StopData(
            name: place.placeName,
            type: place.category ?? 'Attraction',
            placeId: place.placeId,
            place: place,
            time: _formatTime(stop.startTime) + ' - ' + _formatTime(stop.endTime),
            duration: '${stop.durationMinutes} min',
            transitTime: stop.travelFromPreviousMinutes > 0
                ? '${stop.travelFromPreviousMinutes.round()} min'
                : null,
            imageUrl: _placePhotoUrl(place.placePhotoRef, maxWidth: 400),
          );
        }).toList(),
        totalStops: day.stops.length,
        timeRange: day.stops.isEmpty
            ? null
            : _formatTime(day.stops.first.startTime) +
            ' - ' +
            _formatTime(day.stops.last.endTime),
        isSelected: false,
      );
    }).toList();
  }

  int get totalStops {
    return days.fold(0, (sum, d) => sum + d.stops.length);
  }

  Duration get totalTravelTime {
    if (_result.scheduledDays == null) return Duration.zero;
    return _result.scheduledDays!.fold<Duration>(Duration.zero, (sum, day) {
      final travel = day.totalTravelTime;
      return sum + Duration(minutes: travel.round());
    });
  }

  int get cityCount {
    // unique destinations from places
    final destinations = <String>{};
    for (final day in days) {
      for (final stop in day.stops) {
        if (stop.place?.destinationId != null) {
          destinations.add(stop.place!.destinationId!);
        }
      }
    }
    return destinations.length;
  }

  String get dateRange {
    if (_result.scheduledDays == null || _result.scheduledDays!.isEmpty) return '';
    final first = _result.scheduledDays!.first.date;
    final last = _result.scheduledDays!.last.date;
    return '${_formatDate(first)} - ${_formatDate(last)}';
  }

  String? get heroImageUrl {
    // Use first stop's image if available
    final firstDay = days.isNotEmpty ? days.first : null;
    if (firstDay != null && firstDay.stops.isNotEmpty) {
      return firstDay.stops.first.imageUrl;
    }
    return null;
  }

  // ─── Actions ─────────────────────────────────────────────────

  void selectDay(int index) {
    _selectedDayIndex = index;
    notifyListeners();
  }

  Future<void> regenerate() async {
    if (_regenerateRequest == null || _isRegenerating) return;
    _isRegenerating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _regenerateRequest!();
      // After regeneration, the parent should rebuild with new result.
      // We assume the parent screen updates the result via callback.
    } catch (e) {
      _errorMessage = 'Regeneration failed. Please try again.';
      debugPrint('[Regeneration] Error: $e');
    } finally {
      _isRegenerating = false;
      notifyListeners();
    }
  }

  /// Saves the itinerary to the `itineraries` table (+ stops, places,
  /// selected destinations, must-visits). The draft persistence that used
  /// to happen here is REMOVED — the draft is RAM-only now and is cleared
  /// separately via [clearDraft]. Returns true on success.
  Future<bool> save() async {
    if (_isSaving) return false;
    if (!canSave) {
      _saveMessage = 'Itinerary is not valid.';
      notifyListeners();
      return false;
    }

    _isSaving = true;
    _saveMessage = 'Saving...';
    _errorMessage = null;
    _isSaved = false;
    notifyListeners();

    try {
      await _persistResult(_result);
      _isSaved = true;
      _saveMessage = 'Itinerary saved successfully!';
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[Save] Exception: $e');
      _isSaved = false;
      _saveMessage = 'Unable to save itinerary. Please try again.';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// The wizard draft is tracked in-memory by the wizard ViewModels; there
  /// is nothing left to clear here. Kept as a no-op so existing save/discard
  /// flows are unchanged.
  Future<void> clearDraft() async {}

  /// Called when the user edits the itinerary from the edit screen.
  void updateResult(ItineraryResult newResult) {
    // Since the result is final, we can't reassign it. Instead we notify
    // the parent screen to rebuild with new result. The parent screen
    // should pass the new result back via a callback or route result.
    // For simplicity, we just notify that the result changed; the parent
    // screen will handle it via the Navigator result.
    notifyListeners();
  }

  // ─── Persistence (itineraries table — unchanged behaviour) ────

  /// Persists the generated itinerary (header + stops + places + selected
  /// destinations + must-visits) so it appears in "My Itineraries".
  /// Sets [_savedItineraryId] on success.
  Future<void> _persistResult(ItineraryResult generated) async {
    final scheduledDays = generated.scheduledDays ?? const <ScheduledDay>[];
    if (scheduledDays.isEmpty) {
      throw StateError('No scheduled days to save.');
    }

    final now = DateTime.now();
    final itinerary = Itinerary(
      itineraryId: _generateId('itin'),
      userId: _userId.isNotEmpty
          ? _userId
          : '252f0924-192c-42fe-8643-881da7bbf285',
      title: _title.isEmpty ? 'My Trip' : _title,
      description: _draft?.additionalNotes,
      startDate: _tripStartDate,
      endDate: _tripStartDate.add(Duration(days: scheduledDays.length - 1)),
      totalDays: scheduledDays.length,
      explorationTime: _explorationTime,
      travelPace: _draft?.pace ?? 'Standard',
      travelType: _draft?.travelType ?? 'Solo',
      transportationMode: _draft?.transportation ?? 'walking',
      interests: List.of(_draft?.interests ?? const <String>{}),
      coverImageUrl: _coverImageUrl(generated),
      lastModifiedAt: now,
      createdAt: now,
    );

    debugPrint('[FINAL SAVE] Saving itinerary header');
    final itineraryRepo = DatabaseManager().itineraryRepository;
    final saved = await itineraryRepo.createItinerary(itinerary);
    _savedItineraryId = saved.itineraryId;

    // Build stops + save places so the edit screen can join them.
    final stopRepo = DatabaseManager().itineraryStopRepository;
    final placeRepo = DatabaseManager().placeRepository;
    final stops = <ItineraryStop>[];

    for (final day in scheduledDays) {
      for (var i = 0; i < day.stops.length; i++) {
        final scheduledStop = day.stops[i];
        final place = scheduledStop.attraction.place;
        try {
          await placeRepo.savePlace(place);
        } catch (e) {
          debugPrint('[FINAL SAVE] Place save failed: $e');
        }
        stops.add(ItineraryStop(
          stopId: 0,
          itineraryId: saved.itineraryId,
          placeId: place.placeId,
          destinationId: place.destinationId,
          // DB schema is 1-based: day_index > 0, stop_order > 0.
          dayIndex: day.dayIndex + 1,
          stopOrder: i + 1,
          startTime: scheduledStop.startTime,
          endTime: scheduledStop.endTime,
          durationMinutes: scheduledStop.durationMinutes,
          travelFromPrevMinutes: i > 0
              ? scheduledStop.startTime
                  .difference(day.stops[i - 1].endTime)
                  .inMinutes
                  .abs()
              : 0,
          stopStatus: 'PLANNED',
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    await stopRepo.saveStops(stops);
    debugPrint('[FINAL SAVE] Saved ${stops.length} stops for '
        '${saved.itineraryId}');

    // Persist selected destinations (itinerary_selected_destinations).
    // Resolve destination names → DB destination_id (e.g. "D001").
    final destRepo = DatabaseManager().itineraryDestinationRepository;
    final destIdByName = <String, String>{};
    try {
      final allDest =
          await DatabaseManager().destinationRepository.getAllDestinations();
      for (final d in allDest) {
        destIdByName[d.destinationName.trim().toLowerCase()] = d.destinationId;
      }
    } catch (e) {
      debugPrint('[FINAL SAVE] Destination ID resolution failed: $e');
    }
    for (final destName in _draft?.destinationNames ?? const <String>[]) {
      final destId = destIdByName[destName.trim().toLowerCase()] ?? destName;
      final allocated = _draft?.daySplit[destName] ??
          (scheduledDays.length /
                  (_draft?.destinations.isEmpty ?? true
                      ? 1
                      : _draft!.destinations.length))
              .ceil();
      try {
        await destRepo.addDestination(ItineraryDestination(
          itineraryId: saved.itineraryId,
          destinationId: destId,
          allocatedDays: allocated,
          createdAt: now,
          updatedAt: now,
        ));
      } catch (e) {
        debugPrint('[FINAL SAVE] Destination save failed: $e');
      }
    }

    // Persist must-visits (itinerary_must_visits).
    final mustVisitRepo = DatabaseManager().itineraryMustVisitRepository;
    for (final mvId in _mustVisitPlaceIds) {
      final mvName = generated.placeRegistry?.byId(mvId)?.placeName ??
          'Must visit $mvId';
      try {
        await mustVisitRepo.addMustVisit(ItineraryMustVisit(
          mustVisitId: 0,
          itineraryId: saved.itineraryId,
          placeId: mvId,
          placeName: mvName,
          source: 'GOOGLE_SEARCH',
          isVerified: true,
          createdAt: now,
        ));
      } catch (e) {
        debugPrint('[FINAL SAVE] Must-visit save failed: $e');
      }
    }
    debugPrint('[FINAL SAVE] Saved ${_mustVisitPlaceIds.length} must-visits '
        'for ${saved.itineraryId}');
  }

  // ─── Helpers ─────────────────────────────────────────────────

  /// Generate a stable, locally-unique id (SQLite TEXT PK).
  String _generateId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  String? _placePhotoUrl(String? photoRef, {int maxWidth = 400}) {
    if (photoRef == null || photoRef.isEmpty) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=$maxWidth'
        '&photoreference=$photoRef'
        '&key=${ApiKeys.googleMapsApiKey}';
  }

  /// Derive the itinerary cover image URL from the first scheduled stop
  /// that has a valid photo reference.
  String? _coverImageUrl(ItineraryResult generated) {
    final days = generated.scheduledDays;
    if (days == null) return null;
    for (final day in days) {
      for (final stop in day.stops) {
        final ref = stop.attraction.place.placePhotoRef;
        if (ref != null && ref.isNotEmpty) {
          return _placePhotoUrl(ref, maxWidth: 800);
        }
      }
    }
    return null;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

// ─── Data classes for the UI ───────────────────────────────────

class DayData {
  final int dayNumber;
  final String date;
  final List<StopData> stops;
  final int totalStops;
  final String? timeRange;
  final bool isSelected;

  DayData({
    required this.dayNumber,
    required this.date,
    required this.stops,
    required this.totalStops,
    this.timeRange,
    this.isSelected = false,
  });
}

class StopData {
  final String name;
  final String type;
  final String placeId;
  final Place? place;
  final String time;
  final String duration;
  final String? transitTime;
  final String? imageUrl;

  StopData({
    required this.name,
    required this.type,
    required this.placeId,
    this.place,
    required this.time,
    required this.duration,
    this.transitTime,
    this.imageUrl,
  });
}
