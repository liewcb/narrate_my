import '../../core/utils/schedule_display.dart';
// lib/viewmodel/Itinerary/itinerary_final_vm.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/api_keys.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/database_manager.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/itinerary_generation_status.dart';
import '../../model/business_logic/itinerary_service/itinerary_regeneration_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_destination.dart';
import '../../model/entities/itinerary_must_visit.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/entities/weather.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';

class ItineraryFinalViewModel extends ChangeNotifier {
  ItineraryResult _result;
  final String _title;
  final String? _itineraryId;
  final String _explorationTime;
  final List<String> _mustVisitPlaceIds;
  final DateTime _tripStartDate;
  final Future<void> Function()? _regenerateRequest;
  final String _userId;
  final TripDraft? _draft;  // final – cannot be reassigned

  String? _savedItineraryId;

  // State
  bool _isLoading = false;
  bool _isRegenerating = false;
  bool _isSaving = false;
  bool _isSaved = false;
  String? _errorMessage;
  String? _saveMessage;
  int _selectedDayIndex = -1; // -1 represents "All Days"

  // NEW: track unsaved changes
  bool _hasUnsavedChanges = false;
  ItineraryRegenerationService? _regenerationService;

  ItineraryFinalViewModel({
    required ItineraryResult result,
    required String title,
    String? itineraryId,
    String explorationTime = 'Standard',
    List<String> mustVisitPlaceIds = const [],
    required DateTime tripStartDate,
    Future<void> Function()? regenerateRequest,
    Future<ItineraryResult> Function()? regenerateAlternatives,
    String? userId,
    TripDraft? draft,
    ItineraryRegenerationService? regenerationService,
  })  : _result = result,
        _title = title,
        _itineraryId = itineraryId,
        _explorationTime = explorationTime,
        _mustVisitPlaceIds = mustVisitPlaceIds,
        _tripStartDate = tripStartDate,
        _regenerateRequest = regenerateRequest,
        _userId = (userId != null && userId.isNotEmpty)
            ? userId
            : _safeCurrentUserId(),
        _draft = draft,
        _regenerationService = regenerationService;

  static String _safeCurrentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  ItineraryRegenerationService get regenerationService =>
      _regenerationService ??= ItineraryRegenerationService();

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

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;
  set isProcessing(bool value) {
    _isProcessing = value;
    notifyListeners();
  }

  // Determine if there are unsaved changes (compare draft with saved version)
  bool get hasUnsavedChanges {
    // If there's no saved itineraryId, we treat it as "unsaved draft"
    if (itineraryId == null) return true;

    // Otherwise, use the flag set on edits
    return _hasUnsavedChanges;
  }

  /// The ID of the persisted itinerary (available after a successful save).
  String? get savedItineraryId => _savedItineraryId;

  bool get canSave {
    if (_result.scheduledDays == null || _result.scheduledDays!.isEmpty) return false;
    // Allow saving as long as there is at least one scheduled stop across the trip
    return _result.scheduledDays!.any((day) => day.stops.isNotEmpty);
  }

  bool get canRegenerate => _regenerateRequest != null && !_isRegenerating;

  List<DayData> get days {
    if (_result.scheduledDays == null) return [];
    return _result.scheduledDays!.map((day) {
      return DayData(
        dayNumber: day.dayIndex + 1,
        date: _formatDate(day.date),
        reason: day.reason,
        stops: List.generate(day.stops.length, (i) {
          final stop = day.stops[i];
          final place = stop.attraction.place;

          final isUnscheduled = (stop.startTime.hour == 0 && stop.startTime.minute == 0 &&
              stop.endTime.hour == 0 && stop.endTime.minute == 0);

          String? conflict;
          if (!isUnscheduled && i > 0) {
            final prev = day.stops[i - 1];
            final prevUnscheduled = (prev.startTime.hour == 0 && prev.startTime.minute == 0 &&
                prev.endTime.hour == 0 && prev.endTime.minute == 0);
            if (!prevUnscheduled) {
              final travel = stop.travelFromPreviousMinutes.round();
              final minStart = prev.endTime.add(Duration(minutes: travel));
              if (stop.startTime.isBefore(prev.endTime)) {
                final diff = prev.endTime.difference(stop.startTime).inMinutes;
                conflict = 'Time overlap: starts ${formatScheduleMinutes(diff)} before previous stop ends';
              } else if (stop.startTime.isBefore(minStart)) {
                final available = stop.startTime.difference(prev.endTime).inMinutes;
                conflict = 'Travel conflict: only ${formatScheduleMinutes(available)} between stops (needs ${formatScheduleMinutes(travel)})';
              }
            }
          }

          final oh = place.openingHours;
          if (!isUnscheduled && oh != null && !oh.isOpen24Hours && oh.periods.isNotEmpty) {
            final weekday = day.date.weekday % 7;
            final dayPeriods = oh.periods.where((p) => p.open.day == weekday).toList();
            if (dayPeriods.isEmpty) {
              conflict = (conflict != null ? '$conflict • ' : '') + 'Might be closed at this time';
            } else {
              final startMins = stop.startTime.hour * 60 + stop.startTime.minute;
              final endMins = stop.endTime.hour * 60 + stop.endTime.minute;
              bool isOpen = false;
              for (final p in dayPeriods) {
                final openMin = _hhmmToMinutes(p.open.time);
                var closeMin = _hhmmToMinutes(p.close.time);
                var curStart = startMins;
                var curEnd = endMins;
                if (closeMin <= openMin) {
                  closeMin += 1440;
                  if (curStart < openMin) {
                    curStart += 1440;
                    curEnd += 1440;
                  }
                }
                if (curStart >= openMin && curEnd <= closeMin) {
                  isOpen = true;
                  break;
                }
              }
              if (!isOpen) {
                conflict = (conflict != null ? '$conflict • ' : '') + 'Might be closed at this time';
              }
            }
          }

          final timeDisplay = isUnscheduled
              ? 'Time to be arranged'
              : _formatTime(stop.startTime) + ' - ' + _formatTime(stop.endTime);

          return StopData(
            name: place.placeName,
            type: place.category ?? 'Attraction',
            placeId: place.placeId,
            place: place,
            time: timeDisplay,
            duration: isUnscheduled ? '${stop.durationMinutes} min (Unscheduled)' : '${stop.durationMinutes} min',
            transitTime: (!isUnscheduled && stop.travelFromPreviousMinutes > 0)
                ? '${stop.travelFromPreviousMinutes.round()} min'
                : null,
            imageUrl: _resolvePlacePhotoUrl(place, maxWidth: 400),
            scheduleReason: isUnscheduled
                ? 'Time not arranged yet — tap Edit to set a time'
                : stop.scheduleReason,
            conflict: conflict,
            isUnscheduled: isUnscheduled,
          );
        }),
        totalStops: day.stops.length,
        timeRange: () {
          final scheduled = day.stops.where((s) =>
              !(s.startTime.hour == 0 && s.startTime.minute == 0 && s.endTime.hour == 0 && s.endTime.minute == 0)).toList();
          if (scheduled.isEmpty) {
            return day.stops.isEmpty ? null : 'Time to be arranged';
          }
          return _formatTime(scheduled.first.startTime) + ' - ' + _formatTime(scheduled.last.endTime);
        }(),
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
    // 1. Search for first stop with a valid image
    for (final day in days) {
      for (final stop in day.stops) {
        if (stop.imageUrl != null && stop.imageUrl!.trim().isNotEmpty) {
          return stop.imageUrl!.trim();
        }
      }
    }
    // 2. Check generated cover image
    final cover = _coverImageUrl(_result);
    if (cover != null && cover.trim().isNotEmpty) {
      return cover.trim();
    }
    // 3. High quality destination fallback photo
    return 'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=1200&q=80';
  }

  // ─── Actions ─────────────────────────────────────────────────

  void selectDay(int index) {
    if (_selectedDayIndex == index) return;
    _selectedDayIndex = index;
    notifyListeners();
  }

  Future<void> regenerate() async {
    _isRegenerating = true;
    _saveMessage = null; // Clear previous messages
    notifyListeners();

    try {
      final result = await regenerationService.regenerate(
        current: _result,
        request: _draft!,
      );

      if (identical(result, _result) || result == _result) {
        _saveMessage = "Could not generate a better alternative. Retained original plan.";
      } else {
        _result = result;
        _saveMessage = "Itinerary updated with new places!";
      }
    } catch (e) {
      _saveMessage = "Regeneration failed: ${e.toString()}";
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
      _hasUnsavedChanges = false;
      _saveMessage = 'Itinerary saved successfully!';
      debugPrint('[FINAL] database save SUCCESS — itineraryId=$_savedItineraryId');
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e, stack) {
      debugPrint('[Save] Exception: $e\n$stack');
      debugPrint('[FINAL] database save FAILED — working state preserved');
      _isSaved = false;
      _saveMessage = 'Unable to save itinerary: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// Clears the draft state (memory only). Since _draft is final,
  /// we simply reset the unsaved changes flag.
  Future<void> clearDraft() async {
    // Reset the unsaved changes flag; the draft reference will be
    // released when the ViewModel is disposed (screen is popped).
    _hasUnsavedChanges = false;
    notifyListeners();
    debugPrint('Draft cleared from memory.');
  }

  /// Called when the user edits the itinerary from the edit screen
  /// (Remove / Reorder / Duration / Replace). The edit screen returns a full
  /// [ItineraryResult] whose selected day already reflects the change; we must
  /// adopt it as the new working state so the later Save persists the edit
  /// (e.g. a removed stop actually disappears from itinerary_stops).
  void updateResult(ItineraryResult newResult) {
    final beforeDays = _result.scheduledDays?.length ?? 0;
    final beforeStops = _result.scheduledDays
            ?.fold<int>(0, (sum, d) => sum + d.stops.length) ??
        0;
    _result = newResult;
    _hasUnsavedChanges = true; // mark that we have unsaved edits

    final afterDays = _result.scheduledDays?.length ?? 0;
    final afterStops = _result.scheduledDays
            ?.fold<int>(0, (sum, d) => sum + d.stops.length) ??
        0;
    debugPrint('[WORKING STATE] updateResult applied — '
        'days $beforeDays→$afterDays, stops $beforeStops→$afterStops');
    notifyListeners();
  }

  // ─── Add Place (preview working state) ───────────────────────

  /// Every place_id currently scheduled across ALL days — used by Add Place
  /// for whole-itinerary duplicate detection.
  Set<String> get allPlaceIds {
    final ids = <String>{};
    for (final day in (_result.scheduledDays ?? const <ScheduledDay>[])) {
      for (final stop in day.stops) {
        ids.add(stop.attraction.place.placeId);
      }
    }
    return ids;
  }

  /// Geographic centre of a day (centroid of its stops), falling back to the
  /// draft's primary coordinates. Used as the Add Place destination reference.
  Coordinates? destinationCenterForDay(int dayIndex) {
    final days = _result.scheduledDays;
    if (days != null && dayIndex >= 0 && dayIndex < days.length) {
      final stops = days[dayIndex].stops;
      if (stops.isNotEmpty) {
        double lat = 0, lng = 0;
        for (final s in stops) {
          lat += s.attraction.place.placeLatitude;
          lng += s.attraction.place.placeLongitude;
        }
        return Coordinates(
          latitude: lat / stops.length,
          longitude: lng / stops.length,
        );
      }
    }
    return _draft?.primaryCoordinates;
  }

  /// Replaces ONLY the selected day in the working itinerary with the
  /// validated, AI-positioned [updatedDay]. Every other day, the candidate
  /// pool, registry, clusters and must-visits are preserved untouched. The
  /// database is NOT modified — persistence still happens on Save.
  void applyDayUpdate(int dayIndex, ScheduledDay updatedDay) {
    _hasUnsavedChanges = true; // mark that we have unsaved edits
    final days = _result.scheduledDays;
    if (days == null || dayIndex < 0 || dayIndex >= days.length) return;

    final newDays = List<ScheduledDay>.from(days);
    newDays[dayIndex] = updatedDay;

    _result = ItineraryResult.success(
      scheduledDays: newDays,
      weather: _result.weather ?? WeatherForecast(daily: []),
      criticFeedback: _result.criticFeedback ??
          const CriticResult(
            overallSuitable: true,
            score: 0,
            issues: [],
            recommendations: [],
            summary: '',
          ),
      status: _result.status ?? ItineraryGenerationStatus.success,
      warnings: _result.warnings,
      candidatePool: _result.candidatePool,
      placeRegistry: _result.placeRegistry,
      scoredCandidates: _result.scoredCandidates,
      clusters: _result.clusters,
      unretrievableMustVisits: _result.unretrievableMustVisits,
    );
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

    final authUser = Supabase.instance.client.auth.currentUser;
    final effectiveUserId = authUser?.id ?? (_userId.isNotEmpty ? _userId : null);
    if (effectiveUserId == null || effectiveUserId.isEmpty) {
      throw StateError('You must be logged in to save an itinerary.');
    }

    final now = DateTime.now();
    final targetItinId = _savedItineraryId ?? _itineraryId ?? _generateId('itin');
    final itinerary = Itinerary(
      itineraryId: targetItinId,
      userId: effectiveUserId,
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
    late final Itinerary saved;
    if (_savedItineraryId != null || _itineraryId != null) {
      try {
        saved = await itineraryRepo.updateItinerary(itinerary);
      } catch (e) {
        debugPrint('[FINAL SAVE] Update failed, falling back to create: $e');
        saved = await itineraryRepo.createItinerary(itinerary);
      }
    } else {
      saved = await itineraryRepo.createItinerary(itinerary);
    }
    _savedItineraryId = saved.itineraryId;

    // ✅ MOVED UP: Resolve destination IDs BEFORE saving stops
    final destRepo = DatabaseManager().itineraryDestinationRepository;
    final destIdByName = <String, String>{};
    final allDest = <dynamic>[];
    try {
      final fetched =
          await DatabaseManager().destinationRepository.getAllDestinations();
      allDest.addAll(fetched);
      for (final d in fetched) {
        destIdByName[d.destinationName.trim().toLowerCase()] = d.destinationId;
      }
    } catch (e) {
      debugPrint('[FINAL SAVE] Destination ID resolution failed: $e');
    }

    // ✅ Determine a safe default destination ID from the draft
    String defaultDestId = allDest.isNotEmpty ? allDest.first.destinationId : 'D001';
    final draft = _draft;
    if (draft != null && draft.destinationNames.isNotEmpty) {
      for (final name in draft.destinationNames) {
        final key = name.trim().toLowerCase();
        if (destIdByName.containsKey(key)) {
          defaultDestId = destIdByName[key]!;
          break;
        }
      }
    }

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
        final isUnscheduled = (scheduledStop.startTime.hour == 0 && scheduledStop.startTime.minute == 0 &&
            scheduledStop.endTime.hour == 0 && scheduledStop.endTime.minute == 0);
        stops.add(ItineraryStop(
          stopId: 0,
          itineraryId: saved.itineraryId,
          placeId: place.placeId,
          // ✅ FIX APPLIED: Fallback to the itinerary's destination if null
          destinationId: place.destinationId ?? defaultDestId,
          // DB schema is 1-based: day_index > 0, stop_order > 0.
          dayIndex: day.dayIndex + 1,
          stopOrder: i + 1,
          startTime: scheduledStop.startTime,
          endTime: scheduledStop.endTime,
          durationMinutes: scheduledStop.durationMinutes,
          travelFromPrevMinutes: (!isUnscheduled && i > 0)
              ? scheduledStop.startTime
              .difference(day.stops[i - 1].endTime)
              .inMinutes
              .abs()
              : 0,
          stopStatus: isUnscheduled ? 'UNSCHEDULED' : 'PLANNED',
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    await stopRepo.saveStops(stops);
    debugPrint('[FINAL SAVE] Saved ${stops.length} stops for ${saved.itineraryId}');

    // Persist selected destinations (itinerary_selected_destinations).
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
      final meta = _draft?.mustVisitPlaceInfo[mvId];
      final mvName = meta?.placeName ??
          generated.placeRegistry?.byId(mvId)?.placeName ??
          'Must visit $mvId';
      try {
        await mustVisitRepo.addMustVisit(ItineraryMustVisit(
          mustVisitId: 0,
          itineraryId: saved.itineraryId,
          placeId: mvId,
          placeName: mvName,
          destinationId: meta?.destinationId,
          source: meta?.source ?? 'GOOGLE_SEARCH',
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

  String? _resolvePlacePhotoUrl(Place place, {int maxWidth = 400}) {
    if (place.placeImageUrl != null && place.placeImageUrl!.trim().isNotEmpty) {
      return place.placeImageUrl!.trim();
    }
    final ref = place.placePhotoRef?.trim();
    if (ref != null && ref.trim().isNotEmpty) {
      if (ref.startsWith('http://') || ref.startsWith('https://')) {
        return ref.trim();
      }
      return _placePhotoUrl(ref.trim(), maxWidth: maxWidth);
    }
    if (place.placePhotoGoogleMapsUri != null && place.placePhotoGoogleMapsUri!.trim().isNotEmpty) {
      return place.placePhotoGoogleMapsUri!.trim();
    }
    return null;
  }

  /// Derive the itinerary cover image URL from the first scheduled stop
  /// that has a valid photo.
  String? _coverImageUrl(ItineraryResult generated) {
    final days = generated.scheduledDays;
    if (days == null) return null;
    for (final day in days) {
      for (final stop in day.stops) {
        final url = _resolvePlacePhotoUrl(stop.attraction.place, maxWidth: 800);
        if (url != null && url.isNotEmpty) {
          return url;
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

  int _hhmmToMinutes(String time) {
    final clean = time.replaceAll(':', '');
    final h = clean.length >= 2 ? (int.tryParse(clean.substring(0, 2)) ?? 0) : 0;
    final m = clean.length >= 4 ? (int.tryParse(clean.substring(2, 4)) ?? 0) : 0;
    return h * 60 + m;
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
  final String reason;

  DayData({
    required this.dayNumber,
    required this.date,
    required this.stops,
    required this.totalStops,
    this.timeRange,
    this.isSelected = false,
    this.reason = '',
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
  final String scheduleReason;
  final String? conflict;
  final bool isUnscheduled;

  StopData({
    required this.name,
    required this.type,
    required this.placeId,
    this.place,
    required this.time,
    required this.duration,
    this.transitTime,
    this.imageUrl,
    this.scheduleReason = '',
    this.conflict,
    this.isUnscheduled = false,
  });
}