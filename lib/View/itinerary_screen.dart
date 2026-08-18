import 'package:flutter/material.dart';

class ItineraryScreen extends StatelessWidget {
  const ItineraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Itinerary')),
      body: const Center(child: Text('Itinerary content goes here')),
    );
  }
}