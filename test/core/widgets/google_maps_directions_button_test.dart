import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/localization/app_localizations.dart';
import 'package:narrate_my/core/widgets/google_maps_directions_button.dart';

void main() {
  setUp(() => AppLocalizations.currentCode = 'en');
  tearDown(() => AppLocalizations.currentCode = 'en');

  testWidgets('uses the selected language for its label and semantics', (
    tester,
  ) async {
    AppLocalizations.currentCode = 'zh';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GoogleMapsDirectionsButton(
            destinationName: 'Suria KLCC',
            latitude: 3.1578,
            longitude: 101.7123,
          ),
        ),
      ),
    );

    expect(find.text('在 Google 地图中打开'), findsOneWidget);
    expect(
      find.bySemanticsLabel('在 Google 地图中打开前往 Suria KLCC 的路线'),
      findsOneWidget,
    );
  });
}
