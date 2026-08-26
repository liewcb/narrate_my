import 'package:flutter/foundation.dart';
import '../../core/services/google_maps_service.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/trip_draft.dart';
import '../../model/entities/trip_request.dart';
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
    progressMessage = 'Finding attractions...';
    notifyListeners();

    final pipeline = ItineraryGenerationPipeline();

    final generated = await pipeline.generate(
      request: await _buildTripRequest(),
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
      await _persistResult(generated);
    } else {
      isReady = false;
      errorMessage = generated.message ?? 'Could not generate the itinerary.';
    }
    notifyListeners();
  }

  /// Persist the generated itinerary (plus stops and their places) to the
  /// local SQLite cache so it appears in "My Itineraries".
  Future<void> _persistResult(ItineraryResult generated) async {
    try {
      final scheduledDays = generated.scheduledDays ?? const [];
      if (scheduledDays.isEmpty) return;

      final now = DateTime.now();
      final itinerary = Itinerary(
        itineraryId: _generateId('itin'),
        userId: userId,
        title: draft.tripName.isEmpty ? 'My Trip' : draft.tripName,
        description: draft.additionalNotes,
        startDate: draft.startDate ?? now,
        endDate: draft.endDate ?? now,
        totalDays: scheduledDays.length,
        explorationTime: draft.explorationTime ?? 'Standard',
        travelPace: draft.travelPace ?? 'Standard',
        interests: List.of(draft.interests),
        lastModifiedAt: now,
        lastValidationResult: generated.errors != null
            ? {'valid': generated.errors!.isEmpty, 'issues': []}
            : null,
        createdAt: now,
      );

      final itineraryRepo = ItineraryRepositoryImpl();
      final saved = await itineraryRepo.createItinerary(itinerary);

      // Build stops + save places so the edit screen can join them.
      final stopRepo = ItineraryStopRepositoryImpl();
      final placeRepo = PlaceRepositoryAdapter();
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
    } catch (e) {
      debugPrint('[STEP 5 - PERSIST] Persistence failed: $e');
    }
  }

  /// Generate a stable, locally-unique id (SQLite TEXT PK).
  String _generateId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  /// Build a TripRequest from the traveler's actual inputs.
  ///
  /// Every selected destination must have coordinates for the Google
  /// Places search. If a destination is missing coordinates (e.g. the
  /// database row has null lat/lng), we resolve them dynamically by
  /// geocoding the destination name — never a hardcoded coordinate map.
  Future<TripRequest> _buildTripRequest() async {
    final startDate = draft.startDate ?? DateTime.now();
    final endDate = draft.endDate ?? startDate.add(const Duration(days: 1));

    // Start with the coordinates already carried in the draft.
    final coords = Map<String, Coordinates>.of(draft.destinationCoordinates);

    // Geocode any selected destination that has no coordinates yet.
    for (final dest in draft.destinations) {
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

    return TripRequest(
      destinations: List.of(draft.destinations),
      destinationCoordinates: coords,
      title: draft.tripName,
      startDate: startDate,
      endDate: endDate,
      explorationTime: draft.explorationTime ?? 'Standard',
      travelPace: draft.travelPace ?? 'Standard',
      interests: List.of(draft.interests),
      additionalNotes: draft.additionalNotes,
      mustVisitIds: List.of(draft.mustVisitIds),
      daySplit: Map.of(draft.daySplit),
      transportMode: draft.transportMode,
      tripLocation: _tripHub(),
    );
  }

  /// Hub location = first destination's coordinates (used as the
  /// geographic reference for scoring/scheduling).
  Coordinates? _tripHub() {
    if (draft.destinations.isEmpty) return null;
    return draft.destinationCoordinates[draft.destinations.first];
  }
}