import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:narrate_my/core/localization/app_localizations.dart';
import 'package:narrate_my/model/business_logic/shared_services/location_service.dart';
import 'package:narrate_my/model/entities/ar_object.dart';
import 'package:narrate_my/model/entities/ar_recommendation.dart';
import 'package:narrate_my/model/repositories/interfaces/recommendation/ar_recommendation_repository.dart';
import 'package:narrate_my/viewmodel/ar/ar_recommendation_vm.dart';

class _FakeRepository implements ARRecommendationRepository {
  final List<String> languageCodes = [];

  @override
  Future<List<ARRecommendation>> recommend({
    required String currentMarkerId,
    required String currentAttractionName,
    required double latitude,
    required double longitude,
    required List<String> excludedMarkerIds,
    required String languageCode,
  }) async {
    languageCodes.add(languageCode);
    return const [
      ARRecommendation(
        attractionId: 'AD002',
        markerId: 'MK002',
        placeId: 'google-place-2',
        name: 'Test attraction',
        category: 'Museum',
        address: 'Kuala Lumpur',
        summary: 'Test summary',
        reason: 'Test reason',
        relationship: 'Nearby attraction',
        rank: 1,
        latitude: 3.15,
        longitude: 101.71,
        distanceKm: 0.5,
      ),
    ];
  }
}

class _FakeLocationService extends LocationService {
  @override
  Future<Position> getCurrentPosition() async => Position(
    longitude: 101.71,
    latitude: 3.15,
    timestamp: DateTime(2026, 9, 9),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
    isMocked: true,
  );
}

void main() {
  const marker = ARMarker(
    markerId: 'MK001',
    latitude: 3.15,
    longitude: 101.71,
    name: 'Current attraction',
    activationRadiusMeters: 80,
  );

  setUp(() => AppLocalizations.currentCode = 'en');
  tearDown(() => AppLocalizations.currentCode = 'en');

  test('requests AR recommendations in the selected language', () async {
    final repository = _FakeRepository();
    final viewModel = ARRecommendationVm(
      repository,
      locationService: _FakeLocationService(),
    );

    AppLocalizations.currentCode = 'zh';
    await viewModel.open(marker);

    expect(repository.languageCodes, ['zh']);
    viewModel.dispose();
  });

  test('refreshes AR recommendation text when language changes', () async {
    final repository = _FakeRepository();
    final viewModel = ARRecommendationVm(
      repository,
      locationService: _FakeLocationService(),
    );

    await viewModel.open(marker);
    AppLocalizations.currentCode = 'es';
    await viewModel.refreshForCurrentLanguage();

    expect(repository.languageCodes, ['en', 'es']);
    viewModel.dispose();
  });
}
