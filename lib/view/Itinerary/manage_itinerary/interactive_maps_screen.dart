// lib/view/Itinerary/manage_itinerary/interactive_maps_screen.dart
//
// Interactive Maps screen: shows the traveler's itinerary on a Google Map
// (markers for each stop, colored per day, filtered by the selected day),
// with the daily plans listed below. Each daily plan has an Edit button
// that opens the existing ManageEditItineraryScreen for that exact day.

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:intl/intl.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../viewmodel/Itinerary/interactive_maps_vm.dart';
import 'manage_edit_itinerary_screen.dart';
import '../widgets/view_place_detail_screen.dart';

class InteractiveMapsScreen extends StatefulWidget {
  final String itineraryId;

  const InteractiveMapsScreen({Key? key, required this.itineraryId})
      : super(key: key);

  @override
  State<InteractiveMapsScreen> createState() => _InteractiveMapsScreenState();
}

class _InteractiveMapsScreenState extends State<InteractiveMapsScreen> {
  late InteractiveMapsViewModel _viewModel;
  maps.GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _viewModel = InteractiveMapsViewModel(itineraryId: widget.itineraryId);
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── Handlers ───────────────────────────────────────────────

  /// Open ManageEditItineraryScreen for a specific day and refresh on save.
  Future<void> _openEditDay(int dayIndex) async {
    debugPrint('[INTERACTIVE MAP] Edit Day $dayIndex');
    debugPrint('[INTERACTIVE MAP] Opening ManageEditItineraryScreen '
        'itineraryId=${widget.itineraryId} dayNumber=$dayIndex');

    final allDays = _buildAllDays();
    final initialIndex = allDays.indexWhere((d) => d.dayNumber == dayIndex);
    final safeIndex = initialIndex < 0 ? 0 : initialIndex;

    final edited = await Navigator.push<List<DayPlan>>(
      context,
      MaterialPageRoute(
        builder: (_) => ManageEditItineraryScreen(
          initialDayIndex: safeIndex,
          allDays: allDays,
        ),
      ),
    );

    debugPrint('[INTERACTIVE MAP] Edit result: ${edited != null}');

    if (edited != null && mounted) {
      debugPrint('[INTERACTIVE MAP] Refreshing itinerary after edit');
      await _viewModel.load();
    }
  }

  /// Builds the `DayPlan` list consumed by ManageEditItineraryScreen from
  /// the ViewModel's itinerary data (no Supabase access from the UI).
  List<DayPlan> _buildAllDays() {
    return _viewModel.dailyPlans.map((plan) {
      return DayPlan(
        dayNumber: plan.dayIndex,
        date: plan.date,
        places: plan.stops.map(_toWizardPlace).toList(),
      );
    }).toList();
  }

  /// Maps a joined itinerary stop into the edit screen's `WizardPlace` model.
  WizardPlace _toWizardPlace(MapStopItem item) {
    final place = item.place;
    final type = place.placeCategory ??
        (place.placeTypes.isNotEmpty ? place.placeTypes.first : 'Attraction');
    final travelMinutes = item.stop.travelFromPrevMinutes;

    return WizardPlace(
      placeId: item.placeId,
      name: item.name,
      type: type,
      typeIcon: _categoryIcon(type),
      rating: place.placeRating,
      imageUrl: place.placePhotoRef != null
          ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${place.placePhotoRef}&key=${ApiKeys.googleMapsApiKey}'
          : null,
      travelTime: travelMinutes != null ? '$travelMinutes min' : '',
      travelIcon: Icons.directions_car,
      duration: '${item.stop.durationMinutes} min',
      location: item.address,
      latitude: item.latitude,
      longitude: item.longitude,
    );
  }

  static IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'museum':
        return Icons.museum;
      case 'cultural':
        return Icons.palette;
      case 'adventure':
        return Icons.attractions;
      case 'nature':
        return Icons.park;
      case 'shopping':
        return Icons.shopping_bag;
      case 'restaurant':
      case 'cafe':
        return Icons.restaurant;
      case 'nightlife':
      case 'bar':
        return Icons.nightlife;
      default:
        return Icons.place;
    }
  }

  /// Open the existing View Place Detail screen for a marker's place.
  Future<void> _openPlaceDetail(MapStopItem item) async {
    debugPrint('[INTERACTIVE MAP] Opening ViewPlaceDetailScreen '
        'placeId=${item.placeId}');
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlaceDetailScreen(
          placeId: item.placeId,
          initialPlace: item.place,
        ),
      ),
    );
  }

  // ─── Map helpers ────────────────────────────────────────────

  Set<maps.Marker> _buildMarkers(List<MapStopItem> items) {
    return items.map((item) {
      final hue = _dayHue(item.dayIndex);
      return maps.Marker(
        markerId: maps.MarkerId(item.placeId),
        position: maps.LatLng(item.latitude, item.longitude),
        icon: maps.BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: maps.InfoWindow(
          title: item.name,
          snippet:
              'Day ${item.dayIndex} • Stop ${item.stopOrder}\n${item.formattedTime}',
        ),
        onTap: () => _openPlaceDetail(item),
      );
    }).toSet();
  }

  Set<maps.Polyline> _buildPolylines(List<MapStopItem> items) {
    if (items.length < 2) return {};
    return {
      maps.Polyline(
        polylineId: const maps.PolylineId('itinerary_route'),
        points: items
            .map((s) => maps.LatLng(s.latitude, s.longitude))
            .toList(),
        color: AppColors.accent,
        width: 4,
      ),
    };
  }

  /// Fit the camera to all visible markers.
  void _fitMapBounds(List<MapStopItem> items) {
    final controller = _mapController;
    if (controller == null || items.isEmpty) return;

    if (items.length == 1) {
      controller.animateCamera(
        maps.CameraUpdate.newLatLngZoom(
          maps.LatLng(items.first.latitude, items.first.longitude),
          14,
        ),
      );
      return;
    }

    var minLat = items.first.latitude;
    var maxLat = items.first.latitude;
    var minLng = items.first.longitude;
    var maxLng = items.first.longitude;

    for (final item in items) {
      if (item.latitude < minLat) minLat = item.latitude;
      if (item.latitude > maxLat) maxLat = item.latitude;
      if (item.longitude < minLng) minLng = item.longitude;
      if (item.longitude > maxLng) maxLng = item.longitude;
    }

    controller.animateCamera(
      maps.CameraUpdate.newLatLngBounds(
        maps.LatLngBounds(
          southwest: maps.LatLng(minLat, minLng),
          northeast: maps.LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  static double _dayHue(int dayIndex) {
    const hues = [
      maps.BitmapDescriptor.hueBlue,
      maps.BitmapDescriptor.hueGreen,
      maps.BitmapDescriptor.hueOrange,
      maps.BitmapDescriptor.hueViolet,
      maps.BitmapDescriptor.hueRose,
      maps.BitmapDescriptor.hueCyan,
    ];
    return hues[(dayIndex - 1).clamp(0, hues.length - 1)];
  }

  // ─── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Interactive Map',
          style: AppTextStyles.pageTitle.copyWith(fontSize: 20),
        ),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return _buildLoading();
          }

          if (_viewModel.error != null) {
            return _buildError(_viewModel.error!);
          }

          if (_viewModel.stops.isEmpty) {
            return _buildEmpty();
          }

          return _buildContent();
        },
      ),
    );
  }

  // ─── States ─────────────────────────────────────────────────

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading itinerary map...',
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            const Text(
              'Unable to load itinerary.\nPlease try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _viewModel.load(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 56, color: AppColors.inkFaint),
            SizedBox(height: 16),
            Text(
              'No itinerary stops available.',
              style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Content ────────────────────────────────────────────────

  Widget _buildContent() {
    final items = _viewModel.mapStops;
    final dailyPlans = _viewModel.dailyPlans;

    return Column(
      children: [
        // ── Day filter chips ──
        _buildDayFilter(),
        const SizedBox(height: 12),

        // ── Map ──
        SizedBox(
          height: 320,
          width: double.infinity,
          child: _buildMap(items),
        ),
        const SizedBox(height: 16),

        // ── Daily plans ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: dailyPlans
                .map((plan) => _DailyPlanCard(
                      plan: plan,
                      canEdit: _viewModel.canEdit,
                      onEdit: () => _openEditDay(plan.dayIndex),
                      onTapStop: _openPlaceDetail,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDayFilter() {
    final options = <(int?, String)>[
      (null, 'All Days'),
      for (final day in _viewModel.availableDayIndices) (day, 'Day $day'),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (value, label) = options[index];
          final isActive = _viewModel.selectedDayFilter == value;
          return GestureDetector(
            onTap: () => _viewModel.selectDay(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: isActive ? AppColors.accent : AppColors.moduleBorder,
                ),
              ),
              child: Text(
                label,
                style: AppTextStyles.labelSm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.surface : AppColors.ink,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMap(List<MapStopItem> items) {
    if (items.isEmpty) {
      return Container(
        color: AppColors.surface2,
        child: const Center(
          child: Text(
            'No stops for this day.',
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
      );
    }

    // Initial camera target from the first visible stop.
    final target = maps.LatLng(items.first.latitude, items.first.longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        fit: StackFit.expand,
        children: [
          maps.GoogleMap(
            key: ValueKey('interactive_maps_${_viewModel.selectedDayFilter}'),
            initialCameraPosition: maps.CameraPosition(target: target, zoom: 12),
            markers: _buildMarkers(items),
            polylines: _buildPolylines(items),
            mapType: maps.MapType.normal,
            compassEnabled: true,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              _fitMapBounds(items);
            },
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.9),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${items.length} ${items.length == 1 ? 'stop' : 'stops'}',
                style: AppTextStyles.labelSm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DAILY PLAN CARD
// ═══════════════════════════════════════════════════════════════════════

class _DailyPlanCard extends StatelessWidget {
  final DailyPlanItem plan;
  final bool canEdit;
  final VoidCallback onEdit;
  final ValueChanged<MapStopItem> onTapStop;

  const _DailyPlanCard({
    required this.plan,
    required this.canEdit,
    required this.onEdit,
    required this.onTapStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Day + date + Edit button ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Day ${plan.dayIndex}',
                      style: AppTextStyles.pageTitle.copyWith(fontSize: 20),
                    ),
                    Text(
                      DateFormat('d MMM').format(plan.date),
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, size: 16, color: AppColors.accent),
                        SizedBox(width: 6),
                        Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Stops ──
          if (plan.stops.isEmpty)
            Text(
              'No places on this day yet.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
            )
          else
            ...plan.stops.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _StopRow(
                number: index + 1,
                item: item,
                onTap: () => onTapStop(item),
              );
            }),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  final int number;
  final MapStopItem item;
  final VoidCallback onTap;

  const _StopRow({
    required this.number,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface2,
                border: Border.all(color: AppColors.moduleBorder),
              ),
              child: Text(
                '$number',
                style: AppTextStyles.labelSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: AppTextStyles.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.formattedTime,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.inkFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.inkFaint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
