import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../model/data_sources/remote/recommendation_data_source.dart';
import '../../model/repositories/adapters/recommendation_repository_adapter.dart';
import '../../viewmodel/recommendation/nearby_recommendation_viewmodel.dart';

class NearbyRecommendationScreen extends StatelessWidget {
  const NearbyRecommendationScreen({super.key});

  static const _latitude = 3.2150;
  static const _longitude = 101.7260;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final dataSource = RecommendationRemoteDataSource(
          Supabase.instance.client,
        );
        final repository = RecommendationRepositoryAdapter(dataSource);

        return NearbyRecommendationViewModel(repository)
          ..loadRecommendations(latitude: _latitude, longitude: _longitude);
      },
      child: const _NearbyRecommendationView(),
    );
  }
}

class _NearbyRecommendationView extends StatelessWidget {
  const _NearbyRecommendationView();

  static const _mapCenter = maps.LatLng(
    NearbyRecommendationScreen._latitude,
    NearbyRecommendationScreen._longitude,
  );

  static const _initialCameraPosition = maps.CameraPosition(
    target: _mapCenter,
    zoom: 14.5,
  );

  static final _markers = <maps.Marker>{
    const maps.Marker(
      markerId: maps.MarkerId('recommendation_center'),
      position: _mapCenter,
      infoWindow: maps.InfoWindow(
        title: 'TAR UMT area',
        snippet: 'Nearby recommendation search centre',
      ),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NearbyRecommendationViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Attractions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Temporary test coordinates.
              // Later replace with actual device GPS.
              viewModel.refreshRecommendations(
                latitude: NearbyRecommendationScreen._latitude,
                longitude: NearbyRecommendationScreen._longitude,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 260,
                width: double.infinity,
                child: maps.GoogleMap(
                  initialCameraPosition: _initialCameraPosition,
                  markers: _markers,
                  mapType: maps.MapType.normal,
                  compassEnabled: true,
                  mapToolbarEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(viewModel)),
        ],
      ),
    );
  }

  Widget _buildBody(NearbyRecommendationViewModel viewModel) {
    if (viewModel.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Finding attractions for you...'),
          ],
        ),
      );
    }

    if (viewModel.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(viewModel.errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }

    if (viewModel.recommendations.isEmpty) {
      return const Center(
        child: Text('No suitable recommendations are available.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: viewModel.recommendations.length,
      itemBuilder: (context, index) {
        final recommendation = viewModel.recommendations[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(child: Text(recommendation.rank.toString())),
            title: Text(recommendation.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recommendation.category),

                if (recommendation.address != null)
                  Text(recommendation.address!),

                const SizedBox(height: 6),

                Text(recommendation.reason),
              ],
            ),
          ),
        );
      },
    );
  }
}
