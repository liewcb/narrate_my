import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bin/check_plan_state.dart';
import 'bin/run_pipeline.dart';
import 'core/config/app_config.dart';
import 'core/routes/app_routes.dart';
import 'core/services/database_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Initialize DatabaseManager
  final dbManager = DatabaseManager();
  await dbManager.init();
  //await runItineraryPipeline();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'narrate_my',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AppRoutes(),
    );
  }
}
// import 'package:flutter/material.dart';
// // Make sure to import your AddPlaceScreen file here
// // import 'path/to/your/add_place_screen.dart';
//
// void main() {
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Itinerary App',
//       theme: ThemeData(
//         colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
//         useMaterial3: true,
//       ),
//       // Call AddPlaceScreen directly as the home screen
//       home: const AddPlaceScreen(
//         itineraryId: 'TEST_ITINERARY_001',
//         dayIndex: 0,
//       ),
//     );
//   }
// }