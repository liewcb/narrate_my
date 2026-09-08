import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/entities/ar_site.dart';
import 'package:narrate_my/model/entities/place.dart';
import 'package:narrate_my/model/repositories/interfaces/ar_exploration/ar_site_place_repository.dart';
import 'package:narrate_my/viewmodel/recommendation/nearby_ar_site_details_vm.dart';

const _site = ARSite(
  siteId: 'AR_SITE_1',
  name: 'Test AR Site',
  latitude: 3.139,
  longitude: 101.6869,
);

const _place = Place(
  placeId: 'google-place-1',
  placeName: 'Test AR Site',
  placeAddress: 'Kuala Lumpur',
  placeLatitude: 3.139,
  placeLongitude: 101.6869,
  placeRating: 4.5,
  placeTypes: ['tourist_attraction'],
);

class _FakeARSitePlaceRepository implements ARSitePlaceRepository {
  final Place? result;
  final Object? error;

  const _FakeARSitePlaceRepository({this.result, this.error});

  @override
  Future<Place?> resolvePlace(ARSite site) async {
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  test('loads resolved place through the repository interface', () async {
    final viewModel = NearbyArSiteDetailsVm(
      const _FakeARSitePlaceRepository(result: _place),
    );

    expect(viewModel.isLoading, isTrue);
    await viewModel.load(_site);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.place, same(_place));
    expect(viewModel.errorMessage, isNull);
  });

  test('exposes a safe failed state when place resolution fails', () async {
    final viewModel = NearbyArSiteDetailsVm(
      _FakeARSitePlaceRepository(error: StateError('offline')),
    );

    await viewModel.load(_site);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.place, isNull);
    expect(viewModel.errorMessage, contains('offline'));
  });
}
