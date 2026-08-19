import 'package:flutter/material.dart';

class NearbyRecommendationScreen extends StatelessWidget {
  const NearbyRecommendationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby')),
      body: const Center(child: Text('Nearby recommendations go here')),
    );
  }
}