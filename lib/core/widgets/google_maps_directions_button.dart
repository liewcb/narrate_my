import 'package:flutter/material.dart';

import '../services/google_maps_launcher.dart';
import '../theme/app_theme.dart';

class GoogleMapsDirectionsButton extends StatelessWidget {
  final String destinationName;
  final double latitude;
  final double longitude;
  final String? googlePlaceId;

  const GoogleMapsDirectionsButton({
    super.key,
    required this.destinationName,
    required this.latitude,
    required this.longitude,
    this.googlePlaceId,
  });

  Future<void> _open(BuildContext context) async {
    final opened = await GoogleMapsLauncher.openDirections(
      destinationName: destinationName,
      latitude: latitude,
      longitude: longitude,
      googlePlaceId: googlePlaceId,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        button: true,
        link: true,
        label: 'Open directions to $destinationName in Google Maps',
        child: OutlinedButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.directions_rounded),
          label: const Text('Open in Google Maps'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}
