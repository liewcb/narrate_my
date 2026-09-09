import 'package:narrate_my/core/services/local_database_service.dart';
import 'package:narrate_my/core/services/remote_database_service.dart';
import 'package:narrate_my/model/repositories/adapters/bookmark/bookmark_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/destination_hotspot_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/destination_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/itinerary_destination_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/itinerary_must_visit_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/itinerary_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/itinerary_selected_destination_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/itinerary_stop_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary/place_repository_adapter.dart';
import 'package:narrate_my/model/repositories/interfaces/bookmark/bookmark_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/destination_hotspot_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/destination_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/itinerary_destination_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/itinerary_must_visit_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/itinerary_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/itinerary_selected_destination_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/itinerary_stop_repository.dart';
import 'package:narrate_my/model/repositories/interfaces/itinerary/place_repository.dart';

class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  factory DatabaseManager() => _instance;
  DatabaseManager._internal();

  final LocalDatabaseService local = LocalDatabaseService();
  final RemoteDatabaseService remote = RemoteDatabaseService();

  // ─── Repositories (singleton per instance, instantiated lazily) ───
  late final PlaceRepository placeRepository =
      PlaceRepositoryAdapter();
  late final BookmarkRepository bookmarkRepository =
      BookmarkRepositoryImpl();
  late final DestinationHotspotRepository
      destinationHotspotRepository =
      DestinationHotspotRepositoryImpl();
  late final DestinationRepository destinationRepository =
      DestinationRepositoryImpl();
  late final ItineraryDestinationRepository
      itineraryDestinationRepository =
      ItineraryDestinationRepositoryImpl();
  late final ItineraryMustVisitRepository
      itineraryMustVisitRepository =
      ItineraryMustVisitRepositoryImpl();
  late final ItineraryRepository itineraryRepository =
      ItineraryRepositoryImpl();
  late final ItinerarySelectedDestinationRepository
      itinerarySelectedDestinationRepository =
      ItinerarySelectedDestinationRepositoryImpl();
  late final ItineraryStopRepository itineraryStopRepository =
      ItineraryStopRepositoryImpl();

  bool _initialized = false;

  /// Initialize both local and remote database services.
  /// Call this once at app startup.
  Future<void> init() async {
    if (_initialized) return;

    // Initialize Supabase Remote
    await remote.init();

    // Warm-up local SQLite DB connection
    await local.database;

    _initialized = true;
  }
}