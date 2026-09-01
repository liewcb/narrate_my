// lib/viewmodel/ItineraryModel/itinerary_final_vm.dart
//
// ViewModel for ItineraryFinalScreen — holds the validated
// ItineraryResult and exposes derived presentation state.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/config/api_keys.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_destination.dart';
import '../../model/entities/itinerary_must_visit.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/repositories/adapters/destination_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_destination_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_must_visit_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';

/// UI display model for a single itinerary stop.
class StopData {
  final String time;
  final String duration;
  final String name;
  final String type;
  final String? imageUrl;
  final String? transitTime;
  final bool isHighlighted;

  /// The underlying Google place ID — used to open the Place Detail screen.
  final String placeId;

  /// The original [Place] joined to this stop (null when unavailable).
  final Place? place;

  StopData({
    required this.time,
    required this.duration,
    required this.name,
    required this.type,
    this.imageUrl,
    this.transitTime,
    this.isHighlighted = false,
    this.placeId = '',
    this.place,
  });
}

/// UI display model for a single day.
class DayData {
  final int dayNumber;
  final String date;
  final int totalStops;
  final String? timeRange;
  final bool isSelected;
  final List<StopData> stops;

  DayData({
    required this.dayNumber,
    required this.date,
    required this.totalStops,
    this.timeRange,
    this.isSelected = false,
    required this.stops,
  });
}

/// ViewModel for the final itinerary preview screen.
///
/// Owns the validated [ItineraryResult] and derives all presentation
/// state (day list, statistics, title, date range, city count, hero
/// image, transit formatting). The View is a pure projection of this
/// state and never performs generation or business logic.
class ItineraryFinalViewModel extends ChangeNotifier {
  ItineraryResult _result;
  final String _title;
  final String? _itineraryId;
  final String _explorationTime;
  final List<String> _mustVisitPlaceIds;
  final DateTime _tripStartDate;
  final Future<void> Function()? _regenerateRequest;
  final Future<ItineraryResult> Function()? _regenerateAlternatives;
  final String _userId;
  final TripDraft? _draft;

  /// The ID of the persisted itinerary (set after a successful save).
  String? _savedItineraryId;

  int _selectedDayIndex = 0;

  ItineraryFinalViewModel({
    required ItineraryResult result,
    required String title,
    String? itineraryId,
    String explorationTime = 'Standard',
    List<String> mustVisitPlaceIds = const [],
    DateTime? tripStartDate,
    Future<void> Function()? regenerateRequest,
    Future<ItineraryResult> Function()? regenerateAlternatives,
    String userId = '252f0924-192c-42fe-8643-881da7bbf285',
    TripDraft? draft,
  }) : _result = result,
       _title = title,
       _itineraryId = itineraryId,
       _explorationTime = explorationTime,
       _mustVisitPlaceIds = mustVisitPlaceIds,
       _tripStartDate = tripStartDate ?? DateTime.now(),
       _regenerateRequest = regenerateRequest,
       _regenerateAlternatives = regenerateAlternatives,
       _userId = userId,
       _draft = draft;

  // ─── State ────────────────────────────────────────────────────

  bool isLoading = false;
  bool isSaving = false;
  bool isSaved = false;
  String? errorMessage;
  String? saveMessage;

  // ─── Getters ──────────────────────────────────────────────────

  ItineraryResult get result => _result;

  String get title => _title;

  String? get itineraryId => _itineraryId;

  /// The ID of the persisted itinerary after a successful save.
  String? get savedItineraryId => _savedItineraryId;

  String get explorationTime => _explorationTime;

  List<String> get mustVisitPlaceIds => List.unmodifiable(_mustVisitPlaceIds);

  DateTime get tripStartDate => _tripStartDate;

  /// Whether a regeneration callback was provided (i.e. the screen can
  /// offer a "Regenerate" action wired to the generation pipeline).
  bool get canRegenerate =>
      _regenerateRequest != null || _regenerateAlternatives != null;

  /// True while regeneration is running (blocks repeated taps).
  bool get isRegenerating => isLoading;

  int get selectedDayIndex => _selectedDayIndex;

  /// The full day list derived from the scheduled days.
  List<DayData> get days => _buildDays();

  int get totalStops =>
      _result.scheduledDays?.fold<int>(0, (sum, d) => sum + d.stops.length) ??
      0;

  Duration get totalTravelTime => Duration(
    minutes:
        _result.scheduledDays?.fold<int>(
          0,
          (sum, d) => sum + d.totalTravelTime.toInt(),
        ) ??
        0,
  );

  /// Number of unique destination IDs from the scheduled stops.
  int get cityCount {
    final ids = <String>{};
    for (final day in _result.scheduledDays ?? []) {
      for (final stop in day.stops) {
        final destId = stop.attraction.place.destinationId;
        if (destId != null && destId.isNotEmpty) ids.add(destId);
      }
    }
    return ids.isNotEmpty
        ? ids.length
        : (_result.scheduledDays?.isNotEmpty == true ? 1 : 0);
  }

  String _buildPhotoUrl(String photoreference, {int maxWidth = 200}) {
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=$maxWidth'
        '&photoreference=$photoreference'
        '&key=${ApiKeys.googleMapsApiKey}';
  }

  /// Date range from the first to last scheduled day.
  String get dateRange {
    final days = _result.scheduledDays;
    if (days == null || days.isEmpty) return '';
    final first = days.first.date;
    final last = days.last.date;
    final formatter = DateFormat('MMM d');
    return '${formatter.format(first)} – ${formatter.format(last)}';
  }

  /// Hero image: first stop's place photo, or null for a neutral placeholder.
  String? get heroImageUrl {
    final ref = _result.scheduledDays?.firstOrNull?.stops?.firstOrNull?.attraction.place.placePhotoRef;
    if (ref == null) return null;
    return _buildPhotoUrl(ref, maxWidth: 800);
  }

  // ─── Actions ──────────────────────────────────────────────────

  void selectDay(int index) {
    _selectedDayIndex = index;
    notifyListeners();
  }

  /// Re-run generation via the provided callback. Sets loading state
  /// and updates [_result] on success. Uses the candidate-reuse
  /// regeneration callback when available, otherwise the full pipeline.
  ///
  /// Old itinerary is preserved when the returned result is the SAME object
  /// (the regeneration service returns the original unchanged on failure).
  Future<void> regenerate() async {
    if (!canRegenerate) return;
    if (isLoading) return; // prevent concurrent regeneration
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (_regenerateAlternatives != null) {
        final newResult = await _regenerateAlternatives();
        if (!identical(newResult, _result)) {
          updateResult(newResult);
        } else {
          errorMessage =
              'Regeneration failed. The previous itinerary has '
              'been preserved.';
        }
      } else if (_regenerateRequest != null) {
        await _regenerateRequest();
      }
    } catch (e) {
      errorMessage = 'Regeneration failed: $e';
    }
    isLoading = false;
    notifyListeners();
  }

  /// Replace the held result (called after regeneration completes).
  void updateResult(ItineraryResult newResult) {
    _result = newResult;
    _selectedDayIndex = 0;
    isSaved = false;
    _savedItineraryId = null;
    saveMessage = null;
    notifyListeners();
  }

  /// Whether the itinerary can be saved. A save is possible whenever the
  /// generated result is valid and non-empty.
  bool get canSave => _result.success && totalStops > 0;

  /// True while a save operation is in progress (blocks duplicate saves).
  bool get isSaveInProgress => isSaving;

  /// Persist the current itinerary (header + stops + places) and report a
  /// boolean success so the View can decide whether to navigate.
  Future<bool> save() async {
    if (isSaving) return false;
    if (!_result.success) {
      saveMessage = 'The itinerary is not valid and cannot be saved.';
      notifyListeners();
      return false;
    }
    final scheduledDays = _result.scheduledDays ?? const [];
    if (scheduledDays.isEmpty) {
      saveMessage = 'Unable to save an empty itinerary.';
      notifyListeners();
      return false;
    }

    isSaving = true;
    saveMessage = null;
    errorMessage = null;
    notifyListeners();

    try {
      await _persistResult(_result, scheduledDays);
      isSaved = true;
      saveMessage = 'Itinerary saved successfully.';
      debugPrint('[FINAL SAVE] Save completed. itineraryId=$_savedItineraryId');
      isSaving = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('[FINAL SAVE] SAVE FAILED');
      debugPrint('[FINAL SAVE] Error: $e');
      debugPrint('[FINAL SAVE] Stack: $st');
      isSaved = false;
      saveMessage = 'Unable to save itinerary. Please try again.';
      errorMessage = 'Unable to save itinerary: $e';
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// Persist the generated itinerary (plus stops and their places) to the
  /// local SQLite cache + remote Supabase so it appears in "My Itineraries".
  ///
  /// Sets [_savedItineraryId] on success so downstream screens (final
  /// preview, add place, edit) can reference the real persisted itinerary.
  Future<void> _persistResult(
    ItineraryResult generated,
    List<ScheduledDay> scheduledDays,
  ) async {
    final now = DateTime.now();
    final draft = _draft;
    final itinerary = Itinerary(
      itineraryId: _generateId('itin'),
      userId: _userId,
      title: _title,
      description: draft?.additionalNotes,
      startDate: _tripStartDate,
      endDate: scheduledDays.isNotEmpty
          ? scheduledDays.last.date
          : _tripStartDate,
      totalDays: scheduledDays.length,
      explorationTime: _explorationTime,
      travelPace: draft?.travelPace ?? 'Standard',
      travelType: draft?.travelType ?? 'Solo',
      transportationMode: draft?.transportation ?? 'walking',
      interests: List.of(draft?.interests ?? const []),
      coverImageUrl: _coverImageUrl(generated),
      lastModifiedAt: now,
      lastValidationResult: generated.errors != null
          ? {'valid': generated.errors!.isEmpty, 'issues': []}
          : null,
      createdAt: now,
    );

    debugPrint('[FINAL SAVE] Saving itinerary header');
    final itineraryRepo = DatabaseManager().itineraryRepository;
    final saved = await itineraryRepo.createItinerary(itinerary);
    _savedItineraryId = saved.itineraryId;
    debugPrint('[FINAL SAVE] Saved itinerary ID: ${saved.itineraryId}');

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
    if (draft != null) {
      final destRepo = DatabaseManager().itineraryDestinationRepository;
      final destIdByName = <String, String>{};
      try {
        final allDest = await DatabaseManager().destinationRepository.getAllDestinations();
        for (final d in allDest) {
          destIdByName[d.destinationName.trim().toLowerCase()] =
              d.destinationId;
        }
      } catch (e) {
        debugPrint('[FINAL SAVE] Destination ID resolution failed: $e');
      }
      for (final destName in draft.destinations) {
        final destId =
            destIdByName[destName.trim().toLowerCase()] ?? destName;
        final allocated = draft.daySplit[destName] ??
            (draft.totalDays / draft.destinations.length).ceil();
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
      for (final mvId in draft.mustVisitPlaceIds) {
        final mvName =
            generated.placeRegistry?.byId(mvId)?.placeName ?? 'Must visit $mvId';
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
      debugPrint('[FINAL SAVE] Saved ${draft.mustVisitPlaceIds.length} '
          'must-visits for ${saved.itineraryId}');
    }
  }

  /// Generate a stable, locally-unique id (SQLite TEXT PK).
  String _generateId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  /// Derive the itinerary cover image URL from the first scheduled stop's
  /// place photo — identical to the hero image used on the final screen.
  String? _coverImageUrl(ItineraryResult generated) {
    final ref = generated.scheduledDays?.firstOrNull?.stops
        .firstOrNull?.attraction.place.placePhotoRef;
    if (ref == null) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=800'
        '&photoreference=$ref'
        '&key=${ApiKeys.googleMapsApiKey}';
  }

  // ─── Private helpers ──────────────────────────────────────────

  List<DayData> _buildDays() {
    final sDays = _result.scheduledDays;
    if (sDays == null || sDays.isEmpty) return [];
    final formatter = DateFormat('EEE, MMM d');

    return sDays.map((day) {
      final stops = day.stops.map((s) {
        final place = s.attraction.place;
        return StopData(
          time: _fmtTime(s.startTime),
          duration: '${s.durationMinutes} min',
          name: place.placeName,
          type:
              place.category ??
              (place.placeTypes.isNotEmpty
                  ? place.placeTypes.first
                  : 'Attraction'),
          imageUrl: place.placePhotoRef != null
              ? _buildPhotoUrl(place.placePhotoRef!, maxWidth: 200)
              : null,
          transitTime: s.travelFromPreviousMinutes > 0
              ? '${s.travelFromPreviousMinutes} min'
              : null,
          isHighlighted: day.stops.isNotEmpty && s == day.stops.first,
          placeId: place.placeId,
          place: place,
        );
      }).toList();

      final first = day.stops.isNotEmpty ? day.stops.first : null;
      final last = day.stops.isNotEmpty ? day.stops.last : null;

      return DayData(
        dayNumber: day.dayIndex + 1,
        date: formatter.format(day.date),
        totalStops: stops.length,
        timeRange: (first != null && last != null)
            ? '${_fmtTime(first.startTime)} - ${_fmtTime(last.endTime)}'
            : null,
        isSelected: day.dayIndex == _selectedDayIndex,
        stops: stops,
      );
    }).toList();
  }

  String _fmtTime(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:$m $ampm';
  }
}
