import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../model/data_sources/remote/recommendation_data_source.dart';
import '../../model/entities/ar_site.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/recommendation.dart';
import '../../model/repositories/adapters/ar_site_repository_adapter.dart';
import '../../model/repositories/adapters/recommendation_repository_adapter.dart';
import '../../viewmodel/recommendation/nearby_recommendation_vm.dart';
import 'nearby_ar_site_details_screen.dart';
import 'nearby_recommendation_details_screen.dart';

class NearbyRecommendationScreen extends StatelessWidget {
  final VoidCallback? onOpenAr;

  const NearbyRecommendationScreen({super.key, this.onOpenAr});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final dataSource = RecommendationRemoteDataSource();
        final repository = RecommendationRepositoryAdapter(dataSource);
        return NearbyRecommendationVm(
          repository,
          arSiteRepository: SupabaseARSiteRepositoryAdapter(),
        )..loadRecommendations();
      },
      child: _NearbyRecommendationMap(onOpenAr: onOpenAr),
    );
  }
}

class _NearbyRecommendationMap extends StatefulWidget {
  final VoidCallback? onOpenAr;

  const _NearbyRecommendationMap({this.onOpenAr});

  @override
  State<_NearbyRecommendationMap> createState() =>
      _NearbyRecommendationMapState();
}

class _NearbyRecommendationMapState extends State<_NearbyRecommendationMap> {
  static const _recommendationBlue = Color(0xFF4285F4);
  static const _arAvailableRed = Color(0xFFEA4335);

  maps.GoogleMapController? _mapController;
  String? _lastCameraSignature;
  maps.BitmapDescriptor? _recommendationMarker;
  maps.BitmapDescriptor? _arAvailableMarker;

  @override
  void initState() {
    super.initState();
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    final icons = await Future.wait([
      _createMapPin(_recommendationBlue),
      _createMapPin(_arAvailableRed),
    ]);
    if (!mounted) return;
    setState(() {
      _recommendationMarker = icons[0];
      _arAvailableMarker = icons[1];
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NearbyRecommendationVm>();
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
    final markers = _buildMarkers(
      viewModel.recommendations,
      viewModel.arSites,
      location,
    );

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
            if (viewModel.recommendations.isNotEmpty ||
                viewModel.arSites.isNotEmpty)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 72,
                left: 16,
                child: const _MapLegend(),
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
                top: MediaQuery.paddingOf(context).top + 118,
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

  Set<maps.Marker> _buildMarkers(
    List<Recommendation> recommendations,
    List<ARSite> arSites,
    Coordinates userLocation,
  ) {
    final markers = <maps.Marker>{};
    final matchedSiteIds = <String>{};

    for (final recommendation in recommendations) {
      final arSite = _findMatchingARSite(recommendation, arSites);
      if (arSite != null) matchedSiteIds.add(arSite.siteId);
      markers.add(
        maps.Marker(
          markerId: maps.MarkerId(recommendation.placeId),
          position: maps.LatLng(
            recommendation.latitude,
            recommendation.longitude,
          ),
          icon: arSite == null
              ? (_recommendationMarker ??
                    maps.BitmapDescriptor.defaultMarkerWithHue(
                      maps.BitmapDescriptor.hueAzure,
                    ))
              : (_arAvailableMarker ?? maps.BitmapDescriptor.defaultMarker),
          infoWindow: maps.InfoWindow(
            title: recommendation.name,
            snippet: arSite == null
                ? recommendation.category
                : 'AR available • ${recommendation.category}',
          ),
          onTap: () => showNearbyRecommendationDetails(
            context,
            recommendation,
            arSite: arSite,
            userLocation: userLocation,
            onOpenAr: widget.onOpenAr,
          ),
        ),
      );
    }

    for (final site in arSites) {
      if (matchedSiteIds.contains(site.siteId)) continue;
      markers.add(
        maps.Marker(
          markerId: maps.MarkerId('ar-site-${site.siteId}'),
          position: maps.LatLng(site.latitude, site.longitude),
          icon: _arAvailableMarker ?? maps.BitmapDescriptor.defaultMarker,
          infoWindow: maps.InfoWindow(
            title: site.name,
            snippet:
                '${site.experiences.length} AR ${site.experiences.length == 1 ? 'experience' : 'experiences'} available',
          ),
          onTap: () => showNearbyArSiteDetails(
            context,
            site: site,
            userLocation: userLocation,
            onOpenAr: widget.onOpenAr == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onOpenAr!();
                  },
          ),
        ),
      );
    }

    return markers;
  }

  Future<maps.BitmapDescriptor> _createMapPin(Color color) async {
    const width = 84.0;
    const height = 108.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final pin = Path()
      ..moveTo(42, 103)
      ..cubicTo(34, 86, 12, 64, 12, 42)
      ..cubicTo(12, 21, 25, 8, 42, 8)
      ..cubicTo(59, 8, 72, 21, 72, 42)
      ..cubicTo(72, 64, 50, 86, 42, 103)
      ..close();
    canvas.drawPath(pin.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawPath(pin, Paint()..color = color);
    canvas.drawCircle(const Offset(42, 40), 14, Paint()..color = Colors.white);

    final image = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return maps.BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: 36,
      height: 46,
    );
  }

  ARSite? _findMatchingARSite(
    Recommendation recommendation,
    List<ARSite> sites,
  ) {
    for (final site in sites) {
      if (site.matchesPlace(
        googlePlaceId: recommendation.placeId,
        placeName: recommendation.name,
        placeLatitude: recommendation.latitude,
        placeLongitude: recommendation.longitude,
      )) {
        return site;
      }
    }
    return null;
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

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendItem(color: Color(0xFF4285F4), label: 'Recommended'),
            SizedBox(width: 10),
            _LegendItem(color: Color(0xFFEA4335), label: 'AR available'),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on_rounded, color: color, size: 17),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    );
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
