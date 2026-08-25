import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ViewModel/recommendation/nearby_recommendation_viewmodel.dart';

class NearbyRecommendationScreen extends StatelessWidget {
  const NearbyRecommendationScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final viewModel =
    context.watch<NearbyRecommendationViewModel>();

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
                latitude: 3.2150,
                longitude: 101.7260,
              );
            },
          ),
        ],
      ),
      body: _buildBody(viewModel),
    );
  }

  Widget _buildBody(
      NearbyRecommendationViewModel viewModel,
      ) {
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
          child: Text(
            viewModel.errorMessage!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (viewModel.recommendations.isEmpty) {
      return const Center(
        child: Text(
          'No suitable recommendations are available.',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount:
      viewModel.recommendations.length,
      itemBuilder: (context, index) {
        final recommendation =
        viewModel.recommendations[index];

        return Card(
          margin:
          const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                recommendation.rank.toString(),
              ),
            ),
            title: Text(
              recommendation.name,
            ),
            subtitle: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.category,
                ),

                if (recommendation.address != null)
                  Text(
                    recommendation.address!,
                  ),

                const SizedBox(height: 6),

                Text(
                  recommendation.reason,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}