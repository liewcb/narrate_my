import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'narratemy.db');
    return await openDatabase(
      path,
      version: 4,
      onConfigure: (db) async {
        // Enforce Foreign Key constraints in SQLite
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Migrate older databases so they gain the same schema as a fresh install.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS destination_hotspots (
          id TEXT PRIMARY KEY,
          destination_id TEXT NOT NULL,
          hotspot_name TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          suggested_radius_km REAL DEFAULT 2.0,
          popularity_rank INTEGER NOT NULL,
          primary_theme TEXT DEFAULT '',
          tags TEXT DEFAULT ''
        )
      ''');
    }

    if (oldVersion < 4) {
      // Align the local cache with the remote Supabase schema:
      // - places gained the columns written by PlaceDto.toMap()
      // - itineraries gained travel_type + transportation_mode
      // - itinerary_selected_destinations table (with destination_order)
      // - itinerary_must_visits table
      // - itinerary_stops gained destination_id
      await db.execute('ALTER TABLE places ADD COLUMN types TEXT');
      await db.execute('ALTER TABLE places ADD COLUMN price_level INTEGER');
      await db.execute('ALTER TABLE places ADD COLUMN phone_number TEXT');
      await db.execute('ALTER TABLE places ADD COLUMN website TEXT');
      await db.execute('ALTER TABLE places ADD COLUMN photo_reference TEXT');
      await db.execute('ALTER TABLE places ADD COLUMN best_time_suggestion TEXT');

      await db.execute('ALTER TABLE itineraries ADD COLUMN travel_type TEXT');
      await db.execute(
          'ALTER TABLE itineraries ADD COLUMN transportation_mode TEXT');

      await db.execute('ALTER TABLE itinerary_stops ADD COLUMN destination_id TEXT');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS itinerary_selected_destinations (
          itinerary_id TEXT NOT NULL,
          destination_id TEXT NOT NULL,
          allocated_days INTEGER NOT NULL,
          destination_order INTEGER NOT NULL,
          created_at TEXT,
          updated_at TEXT,
          PRIMARY KEY (itinerary_id, destination_id),
          FOREIGN KEY (itinerary_id) REFERENCES itineraries (itinerary_id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS itinerary_must_visits (
          must_visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
          itinerary_id TEXT NOT NULL,
          place_id TEXT,
          place_name TEXT NOT NULL,
          destination_id TEXT,
          source TEXT DEFAULT 'GOOGLE_SEARCH',
          is_verified INTEGER DEFAULT 0,
          created_at TEXT,
          FOREIGN KEY (itinerary_id) REFERENCES itineraries (itinerary_id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS destinations (
          destination_id TEXT PRIMARY KEY,
          destination_name TEXT NOT NULL,
          image_url TEXT NOT NULL,
          latitude REAL,
          longitude REAL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS places (
          id TEXT PRIMARY KEY,
          place_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          address TEXT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          rating REAL,
          category TEXT,
          visit_duration_minutes INTEGER,
          opening_hours TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS itineraries (
          itinerary_id TEXT PRIMARY KEY,
          id TEXT NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          total_days INTEGER NOT NULL,
          exploration_time TEXT NOT NULL,
          travel_pace TEXT NOT NULL,
          interests TEXT NOT NULL,
          cover_image_url TEXT,
          status TEXT DEFAULT 'UPCOMING',
          version INTEGER DEFAULT 1,
          last_modified_at TEXT,
          last_validation_result TEXT,
          is_draft INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS itinerary_stops (
          stop_id INTEGER PRIMARY KEY AUTOINCREMENT,
          itinerary_id TEXT NOT NULL,
          place_id TEXT NOT NULL,
          day_index INTEGER NOT NULL,
          stop_order INTEGER NOT NULL,
          start_time TEXT NOT NULL,
          end_time TEXT NOT NULL,
          duration_minutes INTEGER NOT NULL,
          travel_from_prev_minutes INTEGER DEFAULT 0,
          stop_status TEXT DEFAULT 'PLANNED',
          skip_reason TEXT,
          weather_note TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (itinerary_id) REFERENCES itineraries (itinerary_id) ON DELETE CASCADE,
          FOREIGN KEY (place_id) REFERENCES places (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Destinations Table
    await db.execute('''
      CREATE TABLE destinations (
        destination_id TEXT PRIMARY KEY,
        destination_name TEXT NOT NULL,
        image_url TEXT NOT NULL,
        latitude REAL,
        longitude REAL
      )
    ''');

    // 2. Places Table
    await db.execute('''
      CREATE TABLE places (
        id TEXT PRIMARY KEY,
        place_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        address TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        rating REAL,
        types TEXT,
        category TEXT,
        visit_duration_minutes INTEGER,
        best_time_suggestion TEXT,
        price_level INTEGER,
        phone_number TEXT,
        website TEXT,
        photo_reference TEXT,
        opening_hours TEXT
      )
    ''');

    // 3. Itineraries Table (Matches ItineraryDTO.toMapForLocal)
    await db.execute('''
      CREATE TABLE itineraries (
        itinerary_id TEXT PRIMARY KEY,
        id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        total_days INTEGER NOT NULL,
        exploration_time TEXT NOT NULL,
        travel_pace TEXT NOT NULL,
        travel_type TEXT,
        transportation_mode TEXT,
        interests TEXT NOT NULL,
        cover_image_url TEXT,
        status TEXT DEFAULT 'UPCOMING',
        version INTEGER DEFAULT 1,
        last_modified_at TEXT,
        last_validation_result TEXT,
        is_draft INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 4. Itinerary Stops Table
    await db.execute('''
      CREATE TABLE itinerary_stops (
        stop_id INTEGER PRIMARY KEY AUTOINCREMENT,
        itinerary_id TEXT NOT NULL,
        place_id TEXT NOT NULL,
        destination_id TEXT,
        day_index INTEGER NOT NULL,
        stop_order INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        duration_minutes INTEGER NOT NULL,
        travel_from_prev_minutes INTEGER DEFAULT 0,
        stop_status TEXT DEFAULT 'PLANNED',
        skip_reason TEXT,
        weather_note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (itinerary_id) REFERENCES itineraries (itinerary_id) ON DELETE CASCADE,
        FOREIGN KEY (place_id) REFERENCES places (id) ON DELETE CASCADE
      )
    ''');

    // 5. Destination Hotspots Table (candidate-discovery anchors)
    await db.execute('''
      CREATE TABLE destination_hotspots (
        id TEXT PRIMARY KEY,
        destination_id TEXT NOT NULL,
        hotspot_name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        suggested_radius_km REAL DEFAULT 2.0,
        primary_theme TEXT DEFAULT '',
        tags TEXT DEFAULT ''
      )
    ''');

    // 6. Itinerary Selected Destinations Table
    await db.execute('''
      CREATE TABLE itinerary_selected_destinations (
        itinerary_id TEXT NOT NULL,
        destination_id TEXT NOT NULL,
        allocated_days INTEGER NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        PRIMARY KEY (itinerary_id, destination_id),
        FOREIGN KEY (itinerary_id) REFERENCES itineraries (itinerary_id) ON DELETE CASCADE
      )
    ''');

    // 7. Itinerary Must-Visits Table
    await db.execute('''
      CREATE TABLE itinerary_must_visits (
        must_visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
        itinerary_id TEXT NOT NULL,
        place_id TEXT,
        place_name TEXT NOT NULL,
        destination_id TEXT,
        source TEXT DEFAULT 'GOOGLE_SEARCH',
        is_verified INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (itinerary_id) REFERENCES itineraries (itinerary_id) ON DELETE CASCADE
      )
    ''');
  }
}