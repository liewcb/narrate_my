import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../model/data_sources/remote/recommendation_data_source.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/recommendation.dart';
import '../../model/repositories/adapters/recommendation_repository_adapter.dart';
import '../../viewmodel/recommendation/nearby_recommendation_viewmodel.dart';
import 'nearby_recommendation_details_screen.dart';

class NearbyRecommendationScreen extends StatelessWidget {
  const NearbyRecommendationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final dataSource = RecommendationRemoteDataSource();
        final repository = RecommendationRepositoryAdapter(dataSource);
        return NearbyRecommendationViewModel(repository)..loadRecommendations();
      },
      child: const _NearbyRecommendationMap(),
    );
  }
}

class _NearbyRecommendationMap extends StatefulWidget {
  const _NearbyRecommendationMap();

  @override
  State<_NearbyRecommendationMap> createState() =>
      _NearbyRecommendationMapState();
}

class _NearbyRecommendationMapState extends State<_NearbyRecommendationMap> {
  maps.GoogleMapController? _mapController;
  String? _lastCameraSignature;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NearbyRecommendationViewModel>();
    final location = viewModel.currentLocation;

    if (location == null) {
      return Scaffold(
        body: _LocationState(
          isLoading: viewModel.isLoading,
          message: viewModel.errorMessage,
          onRetry: viewModel.loadRecommendations,
        ),
      );
    }

    _scheduleCameraFit(location, viewModel.recommendations);
    final markers = _buildMarkers(viewModel.recommendations);

    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            maps.GoogleMap(
              key: const ValueKey('nearby_recommendation_fullscreen_map_v2'),
              initialCameraPosition: maps.CameraPosition(
                target: maps.LatLng(location.latitude, location.longitude),
                zoom: 14,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                _lastCameraSignature = null;
                _scheduleCameraFit(location, viewModel.recommendations);
              },
              markers: markers,
              mapType: maps.MapType.normal,
              compassEnabled: true,
              mapToolbarEnabled: false,
              myLocationEnabled: viewModel.hasLocationPermission,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              padding: const EdgeInsets.only(top: 88, bottom: 88),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _MapHeader(
                    count: viewModel.recommendations.length,
                    isLoading: viewModel.isLoading,
                    onRefresh: viewModel.refreshRecommendations,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Center(
                  child: _MapHint(
                    isLoading: viewModel.isLoading,
                    hasRecommendations: viewModel.recommendations.isNotEmpty,
                  ),
                ),
              ),
            ),
            if (viewModel.errorMessage != null)
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.paddingOf(context).top + 78,
                child: _ErrorBanner(
                  message: viewModel.errorMessage!,
                  onRetry: viewModel.refreshRecommendations,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Set<maps.Marker> _buildMarkers(List<Recommendation> recommendations) {
    return recommendations.map((recommendation) {
      final hue = recommendation.rank.isEven
          ? maps.BitmapDescriptor.hueOrange
          : maps.BitmapDescriptor.hueCyan;
      return maps.Marker(
        markerId: maps.MarkerId(recommendation.placeId),
        position: maps.LatLng(
          recommendation.latitude,
          recommendation.longitude,
        ),
        icon: maps.BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: maps.InfoWindow(
          title: recommendation.name,
          snippet: recommendation.category,
        ),
        onTap: () => showNearbyRecommendationDetails(context, recommendation),
      );
    }).toSet();
  }

  void _scheduleCameraFit(
    Coordinates location,
    List<Recommendation> recommendations,
  ) {
    final signature = [
      '${location.latitude},${location.longitude}',
      ...recommendations.map(
        (item) => '${item.placeId}:${item.latitude},${item.longitude}',
      ),
    ].join('|');
    if (_lastCameraSignature == signature) return;
    _lastCameraSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitCamera(location, recommendations);
    });
  }

  Future<void> _fitCamera(
    Coordinates location,
    List<Recommendation> recommendations,
  ) async {
    final controller = _mapController;
    if (controller == null) return;

    final points = <maps.LatLng>[
      maps.LatLng(location.latitude, location.longitude),
      ...recommendations.map(
        (item) => maps.LatLng(item.latitude, item.longitude),
      ),
    ];

    if (points.length == 1) {
      await controller.animateCamera(
        maps.CameraUpdate.newLatLngZoom(points.first, 14),
      );
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }

    try {
      await controller.animateCamera(
        maps.CameraUpdate.newLatLngBounds(
          maps.LatLngBounds(
            southwest: maps.LatLng(minLat, minLng),
            northeast: maps.LatLng(maxLat, maxLng),
          ),
          72,
        ),
      );
    } catch (_) {
      // The map may still be laying out during the first frame. Its initial
      // camera remains correctly centered on the user's live location.
    }
  }
}

class _MapHeader extends StatelessWidget {
  final int count;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _MapHeader({
    required this.count,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(25),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Nearby Attractions',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5F1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count found',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          elevation: 3,
          child: IconButton(
            tooltip: 'Refresh nearby attractions',
            onPressed: isLoading ? null : onRefresh,
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _MapHint extends StatelessWidget {
  final bool isLoading;
  final bool hasRecommendations;

  const _MapHint({required this.isLoading, required this.hasRecommendations});

  @override
  Widget build(BuildContext context) {
    final text = isLoading
        ? 'Finding attractions near you...'
        : hasRecommendations
        ? 'Tap any attraction to view details'
        : 'No mappable attractions found';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasRecommendations ? Icons.location_on_rounded : Icons.info_outline,
            color: AppColors.accent,
            size: 22,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationState extends StatelessWidget {
  final bool isLoading;
  final String? message;
  final VoidCallback onRetry;

  const _LocationState({
    required this.isLoading,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const CircularProgressIndicator()
              else
                const Icon(
                  Icons.location_off_outlined,
                  size: 54,
                  color: AppColors.primary,
                ),
              const SizedBox(height: 18),
              Text(
                message ?? 'Finding your current location...',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
              ),
              if (!isLoading) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
