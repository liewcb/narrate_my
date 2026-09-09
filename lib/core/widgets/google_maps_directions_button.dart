import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
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
        SnackBar(
          content: Text(AppLocalizations.t('recommendation.mapsOpenFailed')),
        ),
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
        label: AppLocalizations.t(
          'recommendation.openDirectionsSemantics',
        ).replaceFirst('{place}', destinationName),
        child: OutlinedButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.directions_rounded),
          label: Text(AppLocalizations.t('recommendation.openInGoogleMaps')),
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
