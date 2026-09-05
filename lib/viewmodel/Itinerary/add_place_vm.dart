import 'package:flutter/foundation.dart';
import '../../core/config/api_keys.dart';
import '../../core/config/itinerary_constants.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/repositories/interfaces/itinerary_stop_repository.dart';

/// A candidate place the user can add to a day of a generated itinerary.
class AddPlaceOption {
  final String placeId;
  final String name;
  final String category;
  final String? imageUrl;
  final int durationMinutes;

  /// Full place record — carried through the AI insertion + validation flow so
  /// stable identity, coordinates, category and opening hours are never lost.
  final Place place;

  const AddPlaceOption({
    required this.placeId,
    required this.name,
    required this.category,
    this.imageUrl,
    required this.durationMinutes,
    required this.place,
  });
}

/// Result of trying to add places to a day.
class AddPlaceResult {
  final bool success;
  final String? message;
  final List<ItineraryStop> addedStops;

  /// Preview mode: the validated, AI-positioned updated day. The caller
  /// replaces ONLY this day in the working itinerary — nothing is written to
  /// the database during preview.
  final ScheduledDay? proposedDay;

  const AddPlaceResult({
    required this.success,
    this.message,
    this.addedStops = const [],
    this.proposedDay,
  });
}

/// ViewModel for "Add a Place" after the itinerary has been generated.
///
/// Two modes:
///
///  * PREVIEW mode ([workingDay] != null) — the itinerary is still an
///    unsaved, in-memory preview. Candidates are retrieved for the SELECTED
///    DAY (existing CandidateRetrieval/Google Places services), filtered
///    (duplicate by stable place_id, valid id, valid coordinates, destination
///    compatibility, existing eligibility rules) and ranked. On selection the
///    existing [CustomPlaceService] builds a specific-day context, asks
///    DeepSeek for the best insertion position, deterministically constructs
///    the complete updated day and hard-validates it. The validated day is
///    returned to the Preview — the database is NEVER touched.
///
///  * LEGACY mode ([workingDay] == null) — a saved itinerary (Manage/detail
///    screens). Behaviour is unchanged: the day's stops are read from the
///    repository and confirmed places are appended as new [ItineraryStop]
///    rows.
class AddPlaceVM extends ChangeNotifier {
  final String itineraryId;
  final int dayIndex;
  final String explorationTime;

  // ─── Preview working state (null → legacy DB mode) ──────────
  final ScheduledDay? workingDay;
  final Set<String> itineraryUsedPlaceIds;
  final DateTime? dayDate;
  final String transportMode;
  final String travelPace;
  final List<String> interests;
  final List<String> mustVisitPlaceIds;
  final Coordinates? destinationCenter;

  final ItineraryStopRepository _stopRepository;
  final CustomPlaceService _service;

  AddPlaceVM({
    required this.itineraryId,
    required this.dayIndex,
    required this.explorationTime,
    this.workingDay,
    this.itineraryUsedPlaceIds = const {},
    this.dayDate,
    this.transportMode = 'walking',
    this.travelPace = 'Standard',
    this.interests = const [],
    this.mustVisitPlaceIds = const [],
    this.destinationCenter,
    ItineraryStopRepository? stopRepository,
    CustomPlaceService? service,
  })  : _stopRepository =
            stopRepository ?? DatabaseManager().itineraryStopRepository,
        _service = service ?? CustomPlaceService();

  bool get isPreviewMode => workingDay != null;

  // ─── Existing schedule ──────────────────────────────────────
  List<ItineraryStop> _existingStops = [];
  bool isLoadingStops = false;
  String? loadError;

  List<ItineraryStop> get existingStops => List.unmodifiable(_existingStops);

  // ─── Candidates & selection ─────────────────────────────────
  final List<AddPlaceOption> _retrievedCandidates = [];
  bool isLoadingCandidates = false;
  String? candidatesError;

  /// Legacy placeholder candidates (unchanged behaviour for saved itineraries).
  static final List<AddPlaceOption> _legacyCandidates = [
    AddPlaceOption(
      placeId: 'central_market',
      name: 'Central Market',
      category: 'Cultural center & shopping',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBgHNdDNXIpGiyneP5zyPFZwuYYaJr6nYVeovUv6YncvycE5pQOqP6ehaGrg2D9xiXEWDxkHAY9dI8Uf4VWN3JYNpAJ4uB6xtvX--FB-AlzakmfqFT6I3jCMPHS9eyWsoGRlt0yzc786tC5p4Adksg6fFfRJ6vDzKF6hq_0iq3V4xqqD9UmIMsY3EhWipclV3i8BX3za2vLLVxfCqhkXVT2C2fwNfrQUy4fu59qLqw8Ke8aJviENCQ4',
      durationMinutes: 60,
      place: Place.empty('central_market'),
    ),
    AddPlaceOption(
      placeId: 'kl_tower',
      name: 'KL Tower',
      category: 'Observation deck views',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuB50EZNAZuVKk0R6JQrKjreuxRZNi9eOUV3exePGJtnCPExi2mCgTyjnds5T8hj3usMqgRUgy1xzhZ35lMFxQqaHQjUPLWarCSDj2Z4QlAQyNu5sHn1a-AzpiAxdfsxTxBZ3bBP0PPxn9g6YbJothsvIqwyswkFWPmLKE8IxOe7J9StbAGRf3l7SmKGn5P8thy_VVhioxrnC1UTe6f9AKfBY6HrgcYl_W14YmKCqQ-zf2k4jMrTfxId',
      durationMinutes: 90,
      place: Place.empty('kl_tower'),
    ),
    AddPlaceOption(
      placeId: 'islamic_arts_museum',
      name: 'Islamic Arts Museum',
      category: 'Extensive art collection',
      imageUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuCnOtY7sYmHJLJNxYA0CLPxNoFXPTr1QkWPVkvx_cmT5i2KJr7-E6XoYTzGHr6HBwmrcrRb9kC0haOFTbfJGKuni_1OUDfu1XxDBYadlW_BTbfOrP1h0gVf7_9n2bigKO9DcO_0xL-egxZSFz7Vp30sXtMoojVqkK6OLUKT67EUQEf0rRjXc2hqQbFjXUxEndts9xeowSaR3Ql04tRr6GgCsGJCdgeqJDYPES3Tx1kMeo4ifSG4-MCM',
      durationMinutes: 120,
      place: Place.empty('islamic_arts_museum'),
    ),
  ];

  List<AddPlaceOption> get candidates =>
      isPreviewMode ? List.unmodifiable(_retrievedCandidates) : _legacyCandidates;

  final Set<String> _selectedPlaceIds = {};
  Set<String> get selectedPlaceIds => Set.unmodifiable(_selectedPlaceIds);

  bool isSelected(String placeId) => _selectedPlaceIds.contains(placeId);

  void toggleSelection(String placeId) {
    if (_selectedPlaceIds.contains(placeId)) {
      _selectedPlaceIds.remove(placeId);
    } else {
      // Preview mode fits ONE place per AI insertion operation; legacy mode
      // keeps the original multi-select behaviour.
      if (isPreviewMode) _selectedPlaceIds.clear();
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
      if (isPreviewMode) {
        _loadPreviewDayContext();
        await _retrieveDayCandidates();
      } else {
        final all = await _stopRepository.getStopsForItinerary(itineraryId);
        _existingStops = all.where((s) => s.dayIndex == dayIndex).toList()
          ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      }
    } catch (e) {
      loadError = 'Unable to load this day. Please try again.';
      debugPrint('[AddPlace] load error: $e');
    } finally {
      isLoadingStops = false;
      notifyListeners();
    }
  }

  /// Builds the display stop list from the CURRENT preview day (never the
  /// database) so the traveler always works against the latest state.
  void _loadPreviewDayContext() {
    final day = workingDay!;
    _existingStops = [
      for (var i = 0; i < day.stops.length; i++)
        ItineraryStop(
          stopId: 0,
          itineraryId: itineraryId,
          placeId: day.stops[i].attraction.place.placeId,
          dayIndex: day.dayIndex,
          stopOrder: i + 1,
          startTime: day.stops[i].startTime,
          endTime: day.stops[i].endTime,
          durationMinutes: day.stops[i].durationMinutes,
          travelFromPrevMinutes: day.stops[i].travelFromPreviousMinutes,
          stopStatus: 'PLANNED',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          place: day.stops[i].attraction.place,
        ),
    ];
  }

  // ─── Candidate retrieval for the selected day ───────────────
  Future<void> _retrieveDayCandidates() async {
    final day = workingDay!;
    isLoadingCandidates = true;
    candidatesError = null;
    _retrievedCandidates.clear();
    notifyListeners();

    try {
      final dayPlaces = day.stops.map((s) => s.attraction.place).toList();
      final anchors = InsertionAnchors(
        previousStop: dayPlaces.isNotEmpty ? dayPlaces.first : null,
        nextStop: dayPlaces.length > 1 ? dayPlaces.last : null,
      );
      final center = destinationCenter ??
          (dayPlaces.isNotEmpty ? dayPlaces.first.coordinates : null);

      // Existing retrieval service — search around the day's route endpoints
      // (or the destination when the day is empty).
      final nearby = await _service.retrieveNearbyPlaces(
        anchors: anchors,
        interests: interests,
        fallbackCenter: center,
      );

      // Filter: valid id, valid coordinates, not already used anywhere in the
      // itinerary, opening hours on the actual travel date.
      final usedIds = <String>{
        ...itineraryUsedPlaceIds,
        ...dayPlaces.map((p) => p.placeId),
      };
      var filtered = _service.filterCandidates(
        candidates: nearby,
        usedPlaceIds: usedIds,
        dayOfWeek: day.date.weekday,
      );

      // Destination compatibility — reuse the existing travel-area ceiling.
      if (center != null) {
        filtered = filtered
            .where((p) =>
                center.distanceTo(p.coordinates) <=
                ItineraryConstants.maxSearchRadiusKm)
            .toList();
      }

      final ranked = _service.rankCandidates(
        candidates: filtered,
        anchors: anchors,
        interests: interests,
        tripLocation: center,
        transportMode: transportMode,
      );

      for (final r in ranked.take(12)) {
        final p = r.place;
        _retrievedCandidates.add(AddPlaceOption(
          placeId: p.placeId,
          name: p.placeName,
          category: p.category ?? 'Attraction',
          imageUrl: _photoUrl(p.placePhotoRef),
          durationMinutes: p.visitDurationMinutes ??
              ItineraryConstants.defaultDurationMinutes,
          place: p,
        ));
      }

      if (_retrievedCandidates.isEmpty) {
        candidatesError = 'No suitable places were found for this day.';
      }
    } catch (e) {
      candidatesError = 'No suitable places were found for this day.';
      debugPrint('[AddPlace] candidate retrieval failed: $e');
    } finally {
      isLoadingCandidates = false;
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
          'Not enough time left ($availableMinutes min free, need $needed min). '
          'Try fewer or shorter places.';
    }
    return errors;
  }

  // ─── Save ───────────────────────────────────────────────────
  Future<AddPlaceResult> addPlaces() async {
    if (isPreviewMode) return _addPlaceToPreviewDay();
    return _addPlacesLegacy();
  }

  /// Preview mode — AI proposes the insertion position, Dart builds the
  /// complete updated day and hard-validates it. Only the selected day is
  /// produced; the database is never written.
  Future<AddPlaceResult> _addPlaceToPreviewDay() async {
    final day = workingDay!;
    if (_selectedPlaceIds.isEmpty) {
      return const AddPlaceResult(
          success: false, message: 'Select a place to add.');
    }
    AddPlaceOption? option;
    for (final c in _retrievedCandidates) {
      if (c.placeId == _selectedPlaceIds.first) {
        option = c;
        break;
      }
    }
    if (option == null) {
      return const AddPlaceResult(
          success: false, message: 'The selected place is no longer available.');
    }

    isSaving = true;
    saveError = null;
    notifyListeners();

    try {
      final existing = [
        for (final s in day.stops)
          ExistingStopContext(
            place: s.attraction.place,
            startTime: s.startTime,
            endTime: s.endTime,
            durationMinutes: s.durationMinutes,
            travelFromPrevMinutes: s.travelFromPreviousMinutes,
            isMustVisit: mustVisitPlaceIds.contains(s.attraction.place.placeId) ||
                s.attraction.isMustVisit,
          ),
      ];

      final plan = await _service.planInsertion(
        dayIndex: day.dayIndex,
        date: day.date,
        existingStops: existing,
        newPlace: option.place,
        explorationTime: explorationTime,
        transportMode: transportMode,
        travelPace: travelPace,
        interests: interests,
        tripLocation: destinationCenter ??
            (existing.isNotEmpty ? existing.first.place.coordinates : null),
      );

      if (!plan.success || plan.proposedDay == null) {
        return AddPlaceResult(
          success: false,
          message: plan.message ??
              'The selected place cannot fit into the current schedule.',
        );
      }

      _selectedPlaceIds.clear();
      return AddPlaceResult(success: true, proposedDay: plan.proposedDay);
    } catch (e) {
      debugPrint('[AddPlace] AI insertion failed: $e');
      saveError = 'Unable to update the selected day. Please try again.';
      return const AddPlaceResult(
        success: false,
        message: 'Unable to update the selected day. Please try again.',
      );
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  /// Legacy mode — append confirmed places as new stop rows (unchanged).
  Future<AddPlaceResult> _addPlacesLegacy() async {
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
      saveError = 'Failed to add: $e';
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

  String? _photoUrl(String? photoRef) {
    if (photoRef == null || photoRef.isEmpty) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=400&photoreference=$photoRef'
        '&key=${ApiKeys.googleMapsApiKey}';
  }
}
