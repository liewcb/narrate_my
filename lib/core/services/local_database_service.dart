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
      version: 3,
      onConfigure: (db) async {
        // Enforce Foreign Key constraints in SQLite
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Migrate older databases (created before the itinerary tables existed)
  /// so they gain the same schema as a fresh install.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {      // --- Existing tables from version 1 ---
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
          travel_type TEXT DEFAULT 'Solo',
          transportation_mode TEXT DEFAULT 'walking',
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

      // --- NEW TABLE added in version 2 (for hotspot caching) ---
      await db.execute('''
        CREATE TABLE IF NOT EXISTS destination_hotspots (
          id TEXT PRIMARY KEY,
          destination_id TEXT NOT NULL,
          hotspot_name TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          suggested_radius_km REAL DEFAULT 2.0,
          primary_theme TEXT NOT NULL,
          tags TEXT NOT NULL
        )
      ''');
    }

    // Version 3: add the itinerary header columns that ItineraryDTO maps
    // (travel_type, transportation_mode). Existing databases created at
    // version 2 are missing them, which made local inserts fail.
    if (oldVersion < 3) {
      final cols = await db.rawQuery('PRAGMA table_info(itineraries)');
      final existing = cols.map((c) => c['name'].toString()).toSet();
      if (!existing.contains('travel_type')) {
        await db.execute(
          "ALTER TABLE itineraries ADD COLUMN travel_type TEXT DEFAULT 'Solo'",
        );
      }
      if (!existing.contains('transportation_mode')) {
        await db.execute(
          "ALTER TABLE itineraries ADD COLUMN transportation_mode TEXT DEFAULT 'walking'",
        );
      }
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
        category TEXT,
        visit_duration_minutes INTEGER,
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

    // 5. Destination Hotspots Table (NEW – for caching hotspots locally)
    await db.execute('''
      CREATE TABLE destination_hotspots (
        id TEXT PRIMARY KEY,
        destination_id TEXT NOT NULL,
        hotspot_name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        suggested_radius_km REAL DEFAULT 2.0,
        primary_theme TEXT NOT NULL,
        tags TEXT NOT NULL
      )
    ''');
  }
}