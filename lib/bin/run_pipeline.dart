// lib/run_pipeline.dart
import 'package:flutter/foundation.dart';

import '../core/services/ai_service.dart';
import '../core/services/weather_service.dart';
import '../model/business_logic/itinerary_service/ai_schedule_service.dart';
import '../model/business_logic/itinerary_service/candidate_retrieval_service.dart';
import '../model/business_logic/itinerary_service/clustering_service.dart';
import '../model/business_logic/itinerary_service/itinerary_plan_state.dart';
import '../model/business_logic/itinerary_service/scoring_service.dart';
import '../model/data_sources/remote/places_remote_data_source.dart';
import '../model/entities/place.dart';
import '../model/entities/trip_request.dart';
import '../model/entities/coordinates.dart';

/// Run the full pipeline with real Google Places API and multi-provider AI scheduling.
Future<ItineraryPlanState> runItineraryPipeline() async {
  // 1. Set up services
  final placesDataSource = PlacesRemoteDataSource();
  final retrievalService = CandidateRetrievalService(placesDataSource: placesDataSource);
  final scoringService = ScoringService();
  final clusteringService = ClusteringService();
  final weatherService = WeatherService();

  // Initialize your custom robust AIService (handles DeepSeek, OpenRouter, Cohere fallbacks)
  final aiGatewayService = AIService();
  final aiScheduleService = AiScheduleService(aiGatewayService);

  // 2. Define trip parameters using the TripRequest model
  final startDate = DateTime(2026, 9, 1);
  final tripDays = 2;
  final endDate = startDate.add(Duration(days: tripDays - 1));
  final mainDestination = 'Langkawi';

  final tripRequest = TripRequest(
    destinations: [mainDestination],
    destinationCoordinates: {
      mainDestination: const Coordinates(latitude: 6.350, longitude: 99.800),
    },
    title: 'Langkawi Adventure Sprint',
    startDate: startDate,
    endDate: endDate,
    explorationTime: 'Intense',
    travelPace: 'Fast',
    interests: ['Nature & Outdoors', 'Water Sports', 'Food & Culinary'],
    additionalNotes: '',
    mustVisitIds: [],
    daySplit: {mainDestination: tripDays},
  );

  final dietaryPrefs = ['Seafood-Free'];
  final accessibilityPrefs = <String>[];
  final exclusions = ['shopping_mall'];
  // 3. Step 1: Candidate Retrieval
  debugPrint('🚀 Starting Itinerary Pipeline');
  final pool = await retrievalService.retrieveCandidates(
    request: tripRequest, // Now cleanly passing the TripRequest object
  );

  // 4. Step 2: Scoring
  debugPrint('⭐ SCORING');
  final allPlaces = pool.all;
  final scored = scoringService.scorePlaces(
    places: allPlaces,
    selectedInterests: tripRequest.interests,
    mustVisitIds: tripRequest.mustVisitIds,
    explorationTime: tripRequest.explorationTime,
    tripLocation: null,
    // Strict-preference inputs (optional; defaults keep other callers intact).
    travelerType: 'Solo',
    travelPace: tripRequest.travelPace,
    accessibilityRequirements: accessibilityPrefs,
    categoryExclusions: exclusions,
    strictInterestFilter: true,
    minPoolFloor: 3,
  );

  // 5. Step 3: Clustering
  debugPrint('🗺️ CLUSTERING');
  final clusters = clusteringService.clusterPlaces(
    scoredPlaces: scored,
    numberOfDays: tripDays,
    pace: tripRequest.travelPace,
  );

  // 6. Step 4: Fetch Weather Forecast
  debugPrint('🌤️ FETCHING WEATHER');
  final forecast = await weatherService.getDailyForecast(
    latitude: tripRequest.destinationCoordinates[mainDestination]!.latitude,
    longitude: tripRequest.destinationCoordinates[mainDestination]!.longitude,
    startDate: tripRequest.startDate,
    endDate: tripRequest.endDate,
  );

  // 7. Step 5: AI-Driven Scheduling & Routing
  debugPrint('🤖 GENERATING AI SCHEDULE');
  debugPrint('[PIPELINE] ExplorationTime=${tripRequest.explorationTime} '
      'TravelPace=${tripRequest.travelPace}');
  final aiSchedule = await aiScheduleService.generateSchedule(
    dailyClusters: clusters,
    forecast: forecast,
    travelPace: tripRequest.travelPace,
    intensity: tripRequest.explorationTime,
    interests: tripRequest.interests,
    destinationName: mainDestination,
    dietaryPreferences: dietaryPrefs,
    categoryExclusions: exclusions,
    startDate: tripRequest.startDate,
  );

  final List<List<Place>> finalDailyStops = [];

  for (final day in aiSchedule) {
    final List<Place> dayPlaces = [];
    for (final stop in day.schedule) {
      final place = pool.findByPlaceId(stop.placeId);
      if (place != null) {
        dayPlaces.add(place);
      }
    }
    debugPrint('[FINAL ITINERARY] Day ${day.dayIndex + 1}: '
        '${dayPlaces.length} places mapped '
        '(aiSchedule dayIndex=${day.dayIndex}, date=${day.date})');
    finalDailyStops.add(dayPlaces);
  }

  // Convert destinations for the state
  final queryDestinations = tripRequest.destinations.map((name) {
    final coords = tripRequest.destinationCoordinates[name];
    return QueryDestination(
      name: name,
      latitude: coords?.latitude ?? 0.0,
      longitude: coords?.longitude ?? 0.0,
    );
  }).toList();

  // ============================================================
  // 9. PACKAGE INTO CENTRALIZED STATE & RETURN
  // ============================================================
  final finalPlanState = ItineraryPlanState(
    itineraryId: 'trip_${DateTime.now().millisecondsSinceEpoch}',
    destinations: queryDestinations,
    totalDays: tripDays,
    pace: tripRequest.travelPace,
    intensity: tripRequest.explorationTime,
    selectedInterests: tripRequest.interests,
    mustVisitPlaceIds: tripRequest.mustVisitIds,
    destinationPools: {
      mainDestination: pool,
    },
    dailyStops: finalDailyStops,
    dailyClusters: clusters,      // Pass the clusters here
    aiDaySchedules: aiSchedule,   // Pass the AI Schedule here
  );

  // Print the state to verify it packaged correctly
  finalPlanState.debugPrintState();

// 8. Print final summary and verify structure for Supabase
  debugPrint('═══════════════════════════════════════════');
  debugPrint('✅ PIPELINE COMPLETE');
  debugPrint('═══════════════════════════════════════════');
  debugPrint('Total candidates retrieved: ${pool.totalCount}');
  debugPrint('Clusters created: ${clusters.length}');

  for (final day in aiSchedule) {
    // CHANGE: Use day.schedule instead of day.stops
    debugPrint('Day ${day.dayIndex}: ${day.schedule.length} stops generated.');
    for (final stop in day.schedule) {
      debugPrint('  - [${stop.startTime} - ${stop.endTime}] Place ID: ${stop.placeId} (Order: ${stop.stopOrder})');
    }
  }

  return finalPlanState;
}