import 'package:narrate_my/core/services/local_database_service.dart';
import 'package:narrate_my/core/services/remote_database_service.dart';
import 'package:narrate_my/model/repositories/adapters/bookmark_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/destination_hotspot_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/destination_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary_destination_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary_must_visit_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary_selected_destination_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/itinerary_stop_repository_adapter.dart';
import 'package:narrate_my/model/repositories/adapters/place_repository_adapter.dart';

class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  factory DatabaseManager() => _instance;
  DatabaseManager._internal();

  final LocalDatabaseService local = LocalDatabaseService();
  final RemoteDatabaseService remote = RemoteDatabaseService();

  // ─── Repositories (singleton per instance, instantiated lazily) ───
  late final PlaceRepositoryAdapter placeRepository =
      PlaceRepositoryAdapter();
  late final BookmarkRepositoryImpl bookmarkRepository =
      BookmarkRepositoryImpl();
  late final DestinationHotspotRepositoryImpl
      destinationHotspotRepository =
      DestinationHotspotRepositoryImpl();
  late final DestinationRepositoryImpl destinationRepository =
      DestinationRepositoryImpl();
  late final ItineraryDestinationRepositoryImpl
      itineraryDestinationRepository =
      ItineraryDestinationRepositoryImpl();
  late final ItineraryMustVisitRepositoryImpl
      itineraryMustVisitRepository =
      ItineraryMustVisitRepositoryImpl();
  late final ItineraryRepositoryImpl itineraryRepository =
      ItineraryRepositoryImpl();
  late final ItinerarySelectedDestinationRepositoryImpl
      itinerarySelectedDestinationRepository =
      ItinerarySelectedDestinationRepositoryImpl();
  late final ItineraryStopRepositoryImpl itineraryStopRepository =
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