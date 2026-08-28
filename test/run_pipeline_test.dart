// test/run_pipeline_test.dart
//
// Runs the new ItineraryGenerationPipeline end-to-end so all debugPrint
// output is visible in the console.
//
// Run with: flutter test test/run_pipeline_test.dart
// Use --plain-name to filter, or pass --dart-define to override nothing.

import 'package:flutter_test/flutter_test.dart';

import '../lib/bin/run_pipeline.dart';

void main() {
  testWidgets('Run the new itinerary generation pipeline',
      (WidgetTester tester) async {
    final result = await runItineraryPipeline();
    // The pipeline is expected to succeed with real Google Places + AI.
    // We only assert the run completed without throwing; a failure is still
    // a valid diagnostic run (its errors are printed above).
    expect(result, isNotNull);
  });
}
