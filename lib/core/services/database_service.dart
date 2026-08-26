// import 'package:path/path.dart';
//
// class DatabaseService {
//   static final DatabaseService _instance = DatabaseService._internal();
//   factory DatabaseService() => _instance;
//   DatabaseService._internal();
//
//   Database? _database;
//
//   Future<Database> get database async {
//     if (_database != null) return _database!;
//     _database = await _initDatabase();
//     return _database!;
//   }
//
//   Future<Database> _initDatabase() async {
//     String path = join(await getDatabasesPath(), 'narratemy.db');
//   }
// }