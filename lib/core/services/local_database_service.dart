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
      version: 2,
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
  }
}