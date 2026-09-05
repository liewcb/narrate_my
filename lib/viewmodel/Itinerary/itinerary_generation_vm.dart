import 'package:flutter/foundation.dart';
import '../../core/config/api_keys.dart';
import '../../core/services/database_manager.dart';
import '../../core/services/google_maps_service.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/itinerary_generation_status.dart';
import '../../model/business_logic/itinerary_service/itinerary_regeneration_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_destination.dart';
import '../../model/entities/itinerary_must_visit.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/repositories/adapters/destination_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_destination_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_must_visit_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_repository_adapter.dart';
import '../../model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import '../../model/repositories/adapters/place_repository_adapter.dart';

/// ViewModel for Step 5 (Generate My Itinerary).
///
/// Builds a [TripRequest] from the traveler's [TripDraft] and runs the
/// real [ItineraryGenerationPipeline]. Exposes generation progress,
/// errors and the final result to the View.
class Step5GenerationVM extends ChangeNotifier {
  final TripDraft draft;
  final String userId;
  final GoogleMapsService _mapsService;

  bool isGenerating = false;
  bool isReady = false;
  String? progressMessage;
  String? errorMessage;
  ItineraryResult? result;

  /// The ID of the persisted itinerary (set after Supabase save).
  String? savedItineraryId;

  Step5GenerationVM(this.draft,
      {this.userId = '252f0924-192c-42fe-8643-881da7bbf285',
        GoogleMapsService? mapsService})
      : _mapsService = mapsService ?? GoogleMapsService();

  int get totalDays => draft.totalDays;

  /// True while the pipeline is still producing a result.
  bool get isLoading => isGenerating && !isReady;

  /// The pipeline's own stage list shown by the loading UI.
  static const List<String> progressStages = [
    'Finding attractions...',
    'Scoring places...',
    'Grouping by location...',
    'Building daily plans...',
    'Creating schedule...',
    'Validating...',
    'Fetching weather...',
    'Getting AI feedback...',
    'Finalizing your itinerary...',
  ];

  /// Run the deterministic itinerary-generation pipeline.
  Future<void> startGeneration() async {
    if (isGenerating) return;
    isGenerating = true;
    isReady = false;
    errorMessage = null;
    result = null;
    savedItineraryId = null;
    progressMessage = 'Finding attractions...';
    notifyListeners();

    final pipeline = ItineraryGenerationPipeline();

    final generated = await pipeline.generate(
      request: await _buildTripDraft(),
      onProgress: (stage) {
        progressMessage = stage;
        notifyListeners();
      },
      tripLocation: _tripHub(),
    );

    isGenerating = false;
    result = generated;
    if (generated.success) {
      isReady = true;
      errorMessage = null;
      // Do NOT auto-save to Supabase. The traveler reviews the itinerary
      // on ItineraryFinalScreen and explicitly clicks Save to persist it.
    } else {
      isReady = false;
      // The pipeline already classifies the reason and returns a
      // traveler-safe message (never a raw exception string).
      errorMessage = generated.message ?? 'Could not generate the itinerary.';
    }
    notifyListeners();
  }

  /// The pipeline-classified traveler-facing status for the generated
  /// itinerary, or null while loading/failed.
  ItineraryGenerationStatus? get status => result?.status;

  /// The traveler-facing message for the current result (success, partial or
  /// failure) straight from the pipeline's classification — the View renders
  /// it verbatim and never guesses the reason.
  String? get statusMessage {
    final r = result;
    if (r == null) return null;
    return r.status?.message ?? r.message;
  }

  /// Re-run the generation pipeline (regeneration request from the final
  /// preview). The pipeline + persistence live here, never in the View.
  Future<void> regenerate() => startGeneration();

  /// Regenerate the itinerary reusing the existing candidate pool, clusters,
  /// and scored candidates (no Google Places re-run, no re-scoring, no
  /// re-clustering). Returns the new result, or the original unchanged
  /// result when all attempts fail.
  Future<ItineraryResult> regenerateItinerary() async {
    if (result == null) throw StateError('No itinerary to regenerate.');
    final regenerationService = ItineraryRegenerationService();
    final oldResult = result!;
    final newResult = await regenerationService.regenerate(
      current: oldResult,
      request: await _buildTripDraft(),
    );

    // The service returns the original object unchanged when all attempts
    // fail — in that case do NOT repersist or replace the state.
    if (!identical(newResult, oldResult) && newResult.success) {
      result = newResult;
      // Do NOT auto-persist — the traveler clicks Save on the final screen.
    }
    return newResult;
  }

  bool isSaving = false;
  bool isSaved = false;
  String? saveError;

  /// Persist the currently held result (called when the traveler explicitly
  /// clicks Save on the final screen). Returns true on success.
  Future<bool> saveItinerary() async {
    final current = result;
    if (current == null) return false;
    if (isSaving) return false; // prevent duplicate saves
    isSaving = true;
    saveError = null;
    notifyListeners();

    debugPrint('[SAVE] Traveler clicked Save');
    debugPrint('[SAVE] Validation status: ${current.success ? 'PASS' : 'FAIL'}');
    if (!current.success) {
      saveError = 'The itinerary is not valid and cannot be saved.';
      isSaving = false;
      notifyListeners();
      return false;
    }

    try {
      await _persistResult(current);
      isSaved = true;
      debugPrint('[SAVE] Itinerary saved successfully');
      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[SAVE] Supabase save failed');
      debugPrint('[SAVE] Error: $e');
      saveError = 'Unable to save itinerary. Please check your connection '
          'and try again.';
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// Persist the generated itinerary (plus stops and their places) to the
  /// local SQLite cache + remote Supabase so it appears in "My Itineraries".
  ///
  /// Sets [savedItineraryId] on success so downstream screens (final preview,
  /// add place, edit) can reference the real persisted itinerary.
  Future<void> _persistResult(ItineraryResult generated) async {
    try {
      final scheduledDays = generated.scheduledDays ?? const [];
      if (scheduledDays.isEmpty) {
        debugPrint('[SAVE] No scheduled days to save — aborting.');
        return;
      }

      final now = DateTime.now();
      final itinerary = Itinerary(
        itineraryId: _generateId('itin'),
        userId: userId,
        title: draft.tripName.isEmpty ? 'My Trip' : draft.tripName,
        description: draft.additionalNotes,
        startDate: draft.startDate ?? now,
        endDate: draft.endDate ?? now,
        totalDays: scheduledDays.length,
        explorationTime: draft.exploration ?? 'Standard',
        travelPace: draft.pace ?? 'Standard',
        travelType: draft.travelType ?? 'Solo',
        transportationMode: draft.transportation,
        interests: List.of(draft.interests),
        coverImageUrl: _coverImageUrl(generated),
        lastModifiedAt: now,
        lastValidationResult: generated.errors != null
            ? {'valid': generated.errors!.isEmpty, 'issues': []}
            : null,
        createdAt: now,
      );

      debugPrint('[SAVE] Saving itinerary header');
      final itineraryRepo = DatabaseManager().itineraryRepository;
      final saved = await itineraryRepo.createItinerary(itinerary);
      savedItineraryId = saved.itineraryId;

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
            debugPrint('[STEP 5 - PERSIST] Place save failed: $e');
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
      debugPrint('[STEP 5 - PERSIST] Saved ${stops.length} stops for '
          '${saved.itineraryId}');

      // Persist selected destinations (itinerary_selected_destinations).
      // Resolve destination names → DB destination_id (e.g. "D001").
      final destRepo = DatabaseManager().itineraryDestinationRepository;
      final destIdByName = <String, String>{};
      try {
        final allDest = await DatabaseManager().destinationRepository.getAllDestinations();
        for (final d in allDest) {
          destIdByName[d.destinationName.trim().toLowerCase()] = d.destinationId;
        }
      } catch (e) {
        debugPrint('[STEP 5 - PERSIST] Destination ID resolution failed: $e');
      }
      for (final destName in draft.destinationNames) {
        final destId = destIdByName[destName.trim().toLowerCase()] ?? destName;
        final allocated =
            draft.daySplit[destName] ?? (draft.totalDays / draft.destinations.length).ceil();
        try {
          await destRepo.addDestination(ItineraryDestination(
            itineraryId: saved.itineraryId,
            destinationId: destId,
            allocatedDays: allocated,
            createdAt: now,
            updatedAt: now,
          ));
        } catch (e) {
          debugPrint('[STEP 5 - PERSIST] Destination save failed: $e');
        }
      }

      // Persist must-visits (itinerary_must_visits).
      final mustVisitRepo = DatabaseManager().itineraryMustVisitRepository;
      for (final mvId in draft.mustVisitPlaceIds) {
        final mvName = generated.placeRegistry?.byId(mvId)?.placeName ?? 'Must visit $mvId';
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
          debugPrint('[STEP 5 - PERSIST] Must-visit save failed: $e');
        }
      }
      debugPrint('[STEP 5 - PERSIST] Saved ${draft.mustVisitPlaceIds.length} '
          'must-visits for ${saved.itineraryId}');
    } catch (e) {
      debugPrint('[STEP 5 - PERSIST] Persistence failed: $e');
    }
  }

  /// Generate a stable, locally-unique id (SQLite TEXT PK).
  String _generateId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  /// Derive the itinerary cover image URL from the first scheduled stop
  /// that has a valid photo reference. Searches all days and stops so a
  /// photo is never missed just because the first stop lacks one.
  String? _coverImageUrl(ItineraryResult generated) {
    final days = generated.scheduledDays;
    if (days == null) return null;
    for (final day in days) {
      for (final stop in day.stops) {
        final ref = stop.attraction.place.placePhotoRef;
        if (ref != null && ref.isNotEmpty) {
          return 'https://maps.googleapis.com/maps/api/place/photo'
              '?maxwidth=800'
              '&photoreference=$ref'
              '&key=${ApiKeys.googleMapsApiKey}';
        }
      }
    }
    return null;
  }

  /// Build a TripRequest from the traveler's actual inputs.
  ///
  /// Every selected destination must have coordinates for the Google
  /// Places search. If a destination is missing coordinates (e.g. the
  /// database row has null lat/lng), we resolve them dynamically by
  /// geocoding the destination name — never a hardcoded coordinate map.
  Future<TripDraft> _buildTripDraft() async {
    final startDate = draft.startDate ?? DateTime.now();
    final endDate = draft.endDate ?? startDate.add(const Duration(days: 1));

    // Start with the coordinates already carried in the draft.
    final coords = Map<String, Coordinates>.of(draft.destinationCoordinates);

    // Geocode any selected destination that has no coordinates yet.
    for (final dest in draft.destinationNames) {
      if (coords.containsKey(dest)) continue;
      debugPrint('[STEP 5 - RESOLVE COORDS] Geocoding "$dest"...');
      final resolved = await _mapsService.geocode(dest);
      if (resolved != null) {
        coords[dest] = resolved;
        debugPrint('[STEP 5 - RESOLVE COORDS] "$dest" -> '
            '(${resolved.latitude}, ${resolved.longitude})');
      } else {
        debugPrint('[STEP 5 - RESOLVE COORDS] "$dest" could not be geocoded');
      }
    }

    return draft.copyWith(
      startDate: startDate,
      endDate: endDate,
      destinationCoordinates: coords,
      interests: draft.interests,
    );
  }

  /// Hub location = first destination's coordinates (used as the
  /// geographic reference for scoring/scheduling).
  Coordinates? _tripHub() {
    if (draft.destinations.isEmpty) return null;
    return draft.destinationCoordinates[draft.destinationNames.first];
  }
}