import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
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
    return openDatabase(
      path,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createItineraryTables(db, ifNotExists: true);
    }
    if (oldVersion < 3) {
      await _upgradeBookmarkCacheV3(db);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createItineraryTables(db);
    await _createBookmarksTable(db);
  }

  Future<void> _createItineraryTables(
    Database db, {
    bool ifNotExists = false,
  }) async {
    final guard = ifNotExists ? 'IF NOT EXISTS ' : '';
    await db.execute('''
      CREATE TABLE ${guard}destinations (
        destination_id TEXT PRIMARY KEY,
        destination_name TEXT NOT NULL,
        image_url TEXT NOT NULL,
        latitude REAL,
        longitude REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${guard}places (
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
        opening_hours TEXT,
        price_level INTEGER,
        phone_number TEXT,
        website TEXT,
        photo_reference TEXT,
        best_time_suggestion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${guard}itineraries (
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
      CREATE TABLE ${guard}itinerary_stops (
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

  Future<void> _upgradeBookmarkCacheV3(Database db) async {
    for (final column in const <String, String>{
      'types': 'TEXT',
      'price_level': 'INTEGER',
      'phone_number': 'TEXT',
      'website': 'TEXT',
      'photo_reference': 'TEXT',
      'best_time_suggestion': 'TEXT',
    }.entries) {
      await _addColumnIfMissing(db, 'places', column.key, column.value);
    }

    final bookmarkTable = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name = 'bookmarks'",
    );
    if (bookmarkTable.isEmpty) {
      await _createBookmarksTable(db);
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info(bookmarks)');
    final itemIdColumns = columns.where(
      (column) => column['name'] == 'item_id',
    );
    final itemIdIsRequired =
        itemIdColumns.isNotEmpty &&
        (itemIdColumns.first['notnull'] as int? ?? 0) == 1;
    if (!itemIdIsRequired) return;

    // SQLite cannot drop NOT NULL in place, so rebuild while preserving data.
    await db.execute('ALTER TABLE bookmarks RENAME TO bookmarks_v2_backup');
    await _createBookmarksTable(db);
    await db.execute('''
      INSERT OR IGNORE INTO bookmarks (
        id, user_id, item_id, item_type, place_id, created_at
      )
      SELECT id, user_id, item_id, item_type, place_id, created_at
      FROM bookmarks_v2_backup
    ''');
    await db.execute('DROP TABLE bookmarks_v2_backup');
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((item) => item['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _createBookmarksTable(Database db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        item_id TEXT,
        item_type TEXT NOT NULL,
        place_id TEXT,
        created_at TEXT,
        CHECK (item_id IS NOT NULL OR place_id IS NOT NULL),
        UNIQUE (user_id, place_id),
        FOREIGN KEY (place_id) REFERENCES places (id) ON DELETE CASCADE
      )
    ''');
  }
}
