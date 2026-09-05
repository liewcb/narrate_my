import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:intl/intl.dart';
import '../../../core/config/api_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/Itinerary/manage_display_plan_vm.dart';
import 'package:narrate_my/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';
import 'add_from_bookmark.dart';
import 'add_custom_screen.dart';
import 'edit_stop_screen.dart';
import 'manage_edit_itinerary_screen.dart';
import '../widgets/view_place_detail_screen.dart';

/// Screen that displays a single itinerary with a map, day selector, and day cards.
/// Supports editing if the itinerary is not in the past.
class ManageDisplayPlanScreen extends StatefulWidget {
  final String itineraryId;

  const ManageDisplayPlanScreen({Key? key, required this.itineraryId})
      : super(key: key);

  @override
  State<ManageDisplayPlanScreen> createState() =>
      _ManageDisplayPlanScreenState();
}

class _ManageDisplayPlanScreenState extends State<ManageDisplayPlanScreen> {
  late ManageDisplayPlanViewModel _viewModel;

  // Keys for scrolling to specific day cards
  final Map<int, GlobalKey> _dayKeys = {};
  final ScrollController _scrollController = ScrollController();

  // ─── Day selector & map state ──────────────────────────────────
  int _selectedMapDayIndex = 1; // will be updated from available days
  List<int> _availableDays = [];

  @override
  void initState() {
    super.initState();
    _viewModel = ManageDisplayPlanViewModel(itineraryId: widget.itineraryId);
    _viewModel.load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Scroll to a specific day card ─────────────────────────────
  void _scrollToDay(int dayIndex) {
    final key = _dayKeys[dayIndex];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  // ─── Open stop detail ──────────────────────────────────────────
  Future<void> _openStopDetail(ItineraryStop stop) async {
    if (stop.placeId.isEmpty && stop.place == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlaceDetailScreen(
          placeId: stop.placeId,
          initialPlace: stop.place,
        ),
      ),
    );
  }

  // ─── Edit stop ──────────────────────────────────────────────────
  Future<void> _openEditStop(ItineraryStop stop) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStopScreen(
          stop: stop,
          itineraryStartDate: _viewModel.itinerary?.startDate ?? DateTime.now(),
          isReadOnly: _viewModel.isReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _viewModel.load();
    }
  }

  // ─── Edit whole day ─────────────────────────────────────────────
  Future<void> _openEditDay(int dayIndex) async {
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

    if (edited != null && mounted) {
      await _viewModel.load();
    }
  }

  // ─── Add custom place ───────────────────────────────────────────
  Future<void> _openAddPlace(int dayIndex, DateTime dayDate) async {
    final itinerary = _viewModel.itinerary;
    if (itinerary == null) return;

    final availableDays = _viewModel.stops
        .map((s) => s.dayIndex)
        .toSet()
        .toList()
      ..sort();

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddCustomStopScreen(
          itineraryId: widget.itineraryId,
          dayIndex: dayIndex,
          dayDate: dayDate,
          availableDayIndices: availableDays,
          explorationTime: itinerary.explorationTime,
          travelPace: itinerary.travelPace,
          transportMode: itinerary.transportationMode,
          interests: itinerary.interests,
          userId: itinerary.userId,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _viewModel.load();
    }
  }

  // ─── Add from bookmarks ─────────────────────────────────────────
  Future<void> _openAddBookmarks(int dayIndex) async {
    final selectedIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddFromBookmarksScreen(
          userId: _viewModel.itinerary?.userId ?? '',
        ),
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty && mounted) {
      final added = await _viewModel.addBookmarkedPlaces(
        dayIndex: dayIndex,
        placeIds: selectedIds,
      );
      if (added > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added bookmark(s).')),
        );
        await _viewModel.load();
      }
    }
  }

  // ─── Build all days for editing ────────────────────────────────
  List<DayPlan> _buildAllDays() {
    final grouped = <int, List<ItineraryStop>>{};
    for (final stop in _viewModel.stops) {
      grouped.putIfAbsent(stop.dayIndex, () => []).add(stop);
    }
    final dayIndices = grouped.keys.toList()..sort();
    final startDate = _viewModel.itinerary?.startDate ?? DateTime.now();

    return dayIndices.map((dayIndex) {
      final dayStops = grouped[dayIndex]!
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      return DayPlan(
        dayNumber: dayIndex,
        date: startDate.add(Duration(days: dayIndex - 1)),
        places: dayStops.map(_toWizardPlace).toList(),
      );
    }).toList();
  }

  WizardPlace _toWizardPlace(ItineraryStop stop) {
    final place = stop.place ?? Place.empty(stop.placeId);
    final type = place.placeCategory ??
        (place.placeTypes.isNotEmpty ? place.placeTypes.first : 'Attraction');
    final travelMinutes = stop.travelFromPrevMinutes;

    return WizardPlace(
      placeId: stop.placeId,
      name: place.placeName,
      type: type,
      typeIcon: _categoryIcon(type),
      rating: place.placeRating,
      imageUrl: place.placePhotoRef != null
          ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${place.placePhotoRef}&key=${ApiKeys.googleMapsApiKey}'
          : null,
      travelTime: travelMinutes != null ? '$travelMinutes min' : '',
      travelIcon: Icons.directions_car,
      duration: '${stop.durationMinutes} min',
      location: place.placeAddress,
      latitude: place.placeLatitude,
      longitude: place.placeLongitude,
      startTime: stop.startTime,
      endTime: stop.endTime,
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

  // ──────────────────────────────────────────────────────────────
  //  BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        if (_viewModel.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final itinerary = _viewModel.itinerary;
        final stops = _viewModel.stops;

        // Update available days and selected day
        _availableDays = stops.map((s) => s.dayIndex).toSet().toList()..sort();
        if (_availableDays.isNotEmpty && !_availableDays.contains(_selectedMapDayIndex)) {
          _selectedMapDayIndex = _availableDays.first;
        }

        final canEdit = _viewModel.canCustomize;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.ink),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              itinerary?.title ?? 'Trip Details',
              style: AppTextStyles.pageTitle.copyWith(fontSize: 18),
            ),
          ),
          body: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.only(
              left: 20.0,
              right: 20.0,
              top: 8.0,
              bottom: 40.0, // reduced bottom padding since no sticky bar
            ),
            children: [
              // ─── Hero Section ──────────────────────────────
              _HeroSection(
                title: itinerary?.title ?? 'My Trip',
                totalDays: itinerary?.totalDays ?? 0,
                startDate: itinerary?.startDate,
                endDate: itinerary?.endDate,
                status: _viewModel.temporalStatus,
              ),
              const SizedBox(height: 24.0),

              // ─── Day Selector ──────────────────────────────
              if (_availableDays.isNotEmpty)
                _DaySelector(
                  days: _availableDays,
                  selectedDay: _selectedMapDayIndex,
                  onDaySelected: (day) {
                    setState(() {
                      _selectedMapDayIndex = day;
                    });
                  },
                ),

              // ─── Map Card ──────────────────────────────────
              _MapCard(
                stops: stops,
                dayIndex: _selectedMapDayIndex,
                onStopTap: _openStopDetail,
              ),
              const SizedBox(height: 16.0),

              // ─── Day Cards ──────────────────────────────────
              ..._buildDayCards(canEdit),
            ],
          ),
        );
      },
    );
  }

  // ─── Build day cards (stops per day) ──────────────────────────
  List<Widget> _buildDayCards(bool canEdit) {
    final grouped = <int, List<ItineraryStop>>{};
    for (final stop in _viewModel.stops) {
      grouped.putIfAbsent(stop.dayIndex, () => []).add(stop);
    }

    if (grouped.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              'No stops found for this itinerary.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
            ),
          ),
        ),
      ];
    }

    final days = grouped.keys.toList()..sort();
    final itinerary = _viewModel.itinerary;
    final cards = <Widget>[];

    for (final dayIndex in days) {
      final stops = grouped[dayIndex]!..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      final date = itinerary?.startDate.add(Duration(days: dayIndex - 1));
      final dayTitle = 'Day $dayIndex';
      final dayMeta = date != null
          ? '${DateFormat('d MMM').format(date)} • ${stops.length} stops'
          : '${stops.length} stops';

      _dayKeys[dayIndex] ??= GlobalKey();

      cards.add(
        Container(
          key: _dayKeys[dayIndex],
          child: _DayCard(
            dayIndex: dayIndex,
            dayTitle: dayTitle,
            dayMeta: dayMeta,
            stops: stops,
            dayDate: date ?? DateTime.now(),
            canEdit: canEdit,
            onEditDay: () => _openEditDay(dayIndex),
            onEditStop: _openEditStop,
            onAddPlace: (day, date) => _openAddPlace(day, date),
            onAddBookmarks: _openAddBookmarks,
            onStopTap: _openStopDetail,
          ),
        ),
      );
      cards.add(const SizedBox(height: 28.0));
    }

    return cards;
  }
}

// ════════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS (unchanged)
// ════════════════════════════════════════════════════════════════

/// Hero section with title, dates, and status badge.
class _HeroSection extends StatelessWidget {
  final String title;
  final int totalDays;
  final DateTime? startDate;
  final DateTime? endDate;
  final ItineraryTemporalStatus status;

  const _HeroSection({
    required this.title,
    required this.totalDays,
    this.startDate,
    this.endDate,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8.0),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.pageTitle,
              ),
            ),
            const SizedBox(width: 8.0),
            _StatusBadge(status: status),
          ],
        ),
        const SizedBox(height: 6.0),
        if (startDate != null && endDate != null)
          Text(
            '$totalDays Days • ${DateFormat('d MMM').format(startDate!)} – ${DateFormat('d MMM').format(endDate!)}',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
          ),
      ],
    );
  }
}

/// Status badge (Past / Ongoing / Upcoming).
class _StatusBadge extends StatelessWidget {
  final ItineraryTemporalStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor = AppColors.surface;
    Color fgColor = AppColors.ink;
    IconData icon = Icons.circle_outlined;
    String label = '';

    switch (status) {
      case ItineraryTemporalStatus.past:
        bgColor = AppColors.surface2;
        fgColor = AppColors.inkFaint;
        icon = Icons.history;
        label = 'Past';
        break;
      case ItineraryTemporalStatus.ongoing:
        label = 'Ongoing';
        icon = Icons.play_circle_outline;
        break;
      case ItineraryTemporalStatus.upcoming:
        label = 'Upcoming';
        icon = Icons.event_available;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSm.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrollable day selector.
class _DaySelector extends StatelessWidget {
  final List<int> days;
  final int selectedDay;
  final ValueChanged<int> onDaySelected;

  const _DaySelector({
    required this.days,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final day = days[index];
            final isActive = day == selectedDay;
            return GestureDetector(
              onTap: () => onDaySelected(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isActive ? AppColors.accent : AppColors.moduleBorder,
                  ),
                ),
                child: Text(
                  'Day $day',
                  style: AppTextStyles.labelSm.copyWith(
                    color: isActive ? AppColors.bg : AppColors.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Google Map card showing stops for a given day.
class _MapCard extends StatelessWidget {
  final List<ItineraryStop> stops;
  final int dayIndex;
  final void Function(ItineraryStop) onStopTap;

  const _MapCard({
    required this.stops,
    required this.dayIndex,
    required this.onStopTap,
  });

  @override
  Widget build(BuildContext context) {
    final stopsForDay = stops
        .where((s) => s.dayIndex == dayIndex)
        .toList()
      ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

    final validStops = _MappableStop.fromStops(stopsForDay);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
        ),
        child: validStops.isEmpty
            ? _EmptyMapState(dayIndex: dayIndex)
            : _DayMapWidget(
          stops: validStops,
          dayIndex: dayIndex,
          onStopTap: onStopTap,
        ),
      ),
    );
  }
}

/// Empty map state (no valid coordinates).
class _EmptyMapState extends StatelessWidget {
  final int dayIndex;

  const _EmptyMapState({required this.dayIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.accent.withOpacity(0.15),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 40, color: AppColors.inkFaint),
            const SizedBox(height: 8),
            Text(
              'No map location available for Day $dayIndex',
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// The actual Google Map widget with markers and polyline.
class _DayMapWidget extends StatefulWidget {
  final List<_MappableStop> stops;
  final int dayIndex;
  final void Function(ItineraryStop) onStopTap;

  const _DayMapWidget({
    required this.stops,
    required this.dayIndex,
    required this.onStopTap,
  });

  @override
  State<_DayMapWidget> createState() => _DayMapWidgetState();
}

class _DayMapWidgetState extends State<_DayMapWidget> {
  maps.GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        maps.GoogleMap(
          initialCameraPosition: _initialCameraPosition(),
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          mapType: maps.MapType.normal,
          compassEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (controller) {
            _mapController = controller;
            _fitMapBounds();
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
              'Day ${widget.dayIndex} • ${widget.stops.length} ${widget.stops.length == 1 ? 'stop' : 'stops'}',
              style: AppTextStyles.labelSm.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  maps.CameraPosition _initialCameraPosition() {
    if (widget.stops.isEmpty) {
      return const maps.CameraPosition(
        target: maps.LatLng(0, 0),
        zoom: 1,
      );
    }
    return maps.CameraPosition(
      target: maps.LatLng(
        widget.stops.first.latitude,
        widget.stops.first.longitude,
      ),
      zoom: 14,
    );
  }

  Set<maps.Marker> _buildMarkers() {
    return widget.stops.map((item) {
      return maps.Marker(
        markerId: maps.MarkerId(item.stop.placeId),
        position: maps.LatLng(item.latitude, item.longitude),
        icon: maps.BitmapDescriptor.defaultMarkerWithHue(
          maps.BitmapDescriptor.hueBlue,
        ),
        infoWindow: maps.InfoWindow(
          title: item.stop.place?.name ?? item.stop.placeId,
          snippet:
          'Day ${widget.dayIndex} • Stop ${item.stop.stopOrder}\n${_formattedTime(item.stop)}',
        ),
        onTap: () => widget.onStopTap(item.stop),
      );
    }).toSet();
  }

  Set<maps.Polyline> _buildPolylines() {
    if (widget.stops.length < 2) return {};
    return {
      maps.Polyline(
        polylineId: const maps.PolylineId('day_route'),
        points: widget.stops
            .map((s) => maps.LatLng(s.latitude, s.longitude))
            .toList(),
        color: AppColors.accent,
        width: 4,
      ),
    };
  }

  void _fitMapBounds() {
    final controller = _mapController;
    if (controller == null || widget.stops.isEmpty) return;

    if (widget.stops.length == 1) {
      controller.animateCamera(
        maps.CameraUpdate.newLatLngZoom(
          maps.LatLng(widget.stops.first.latitude, widget.stops.first.longitude),
          14,
        ),
      );
      return;
    }

    var minLat = widget.stops.first.latitude;
    var maxLat = widget.stops.first.latitude;
    var minLng = widget.stops.first.longitude;
    var maxLng = widget.stops.first.longitude;

    for (final item in widget.stops) {
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
        60,
      ),
    );
  }

  String _formattedTime(ItineraryStop stop) =>
      '${DateFormat('HH:mm').format(stop.startTime)} – '
          '${DateFormat('HH:mm').format(stop.endTime)}';
}

/// A stop with valid, mappable coordinates.
class _MappableStop {
  final ItineraryStop stop;
  final double latitude;
  final double longitude;

  const _MappableStop({
    required this.stop,
    required this.latitude,
    required this.longitude,
  });

  static List<_MappableStop> fromStops(List<ItineraryStop> stops) {
    final result = <_MappableStop>[];
    for (final stop in stops) {
      final place = stop.place;
      if (place == null) continue;
      final lat = place.placeLatitude;
      final lng = place.placeLongitude;
      if (lat == 0 && lng == 0) continue; // Place.empty placeholder
      result.add(_MappableStop(
        stop: stop,
        latitude: lat,
        longitude: lng,
      ));
    }
    return result;
  }
}

/// Card displaying a single day's stops with a timeline.
class _DayCard extends StatelessWidget {
  final int dayIndex;
  final String dayTitle;
  final String dayMeta;
  final List<ItineraryStop> stops;
  final DateTime dayDate;
  final bool canEdit;
  final VoidCallback onEditDay;
  final Future<void> Function(ItineraryStop) onEditStop;
  final Future<void> Function(int, DateTime) onAddPlace;
  final Future<void> Function(int) onAddBookmarks;
  final void Function(ItineraryStop) onStopTap;

  const _DayCard({
    required this.dayIndex,
    required this.dayTitle,
    required this.dayMeta,
    required this.stops,
    required this.dayDate,
    required this.canEdit,
    required this.onEditDay,
    required this.onEditStop,
    required this.onAddPlace,
    required this.onAddBookmarks,
    required this.onStopTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20.0),
          const Text(
            'STOPS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 12.0),
          _buildTimeline(),
          if (canEdit) _buildAddActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dayTitle,
                style: AppTextStyles.pageTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 2.0),
              Text(
                dayMeta,
                style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
        if (canEdit)
          OutlinedButton.icon(
            onPressed: onEditDay,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit Plan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeline() {
    return Stack(
      children: [
        Positioned(
          left: 17,
          top: 20,
          bottom: 20,
          child: SizedBox(
            width: 2,
            child: CustomPaint(
              painter: _DashedLinePainter(color: AppColors.moduleBorder),
            ),
          ),
        ),
        Column(
          children: List.generate(stops.length, (index) {
            final stop = stops[index];
            return _StopItem(
              stop: stop,
              number: index + 1,
              isFirst: index == 0,
              isLast: index == stops.length - 1,
              canEdit: canEdit,
              onTap: () => onStopTap(stop),
              onEdit: () => onEditStop(stop),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildAddActions() {
    return Column(
      children: [
        const SizedBox(height: 12.0),
        GestureDetector(
          onTap: () => onAddPlace(dayIndex, dayDate),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 2),
                    color: AppColors.surface,
                  ),
                  child: const Icon(Icons.add, size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Text(
                  'Add custom place to ${dayTitle.toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6.0),
        GestureDetector(
          onTap: () => onAddBookmarks(dayIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.green, width: 2),
                    color: AppColors.surface,
                  ),
                  child: const Icon(Icons.bookmark_add_outlined, size: 16, color: AppColors.green),
                ),
                const SizedBox(width: 12),
                Text(
                  'Add from bookmarks to ${dayTitle.toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A single stop in the timeline.
class _StopItem extends StatelessWidget {
  final ItineraryStop stop;
  final int number;
  final bool isFirst;
  final bool isLast;
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _StopItem({
    required this.stop,
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.canEdit,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StopNumber(number: number, isFirst: isFirst),
          const SizedBox(width: 14),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.moduleBorder.withOpacity(0.8)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x08000000),
                        offset: Offset(0, 2),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stop.place?.name ?? stop.placeId,
                                  style: AppTextStyles.bodyLg.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: AppColors.inkFaint,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${DateFormat('HH:mm').format(stop.startTime)} – ${DateFormat('HH:mm').format(stop.endTime)}',
                                      style: AppTextStyles.bodySm.copyWith(
                                        color: AppColors.inkFaint,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
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
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              stop.place?.address ?? stop.place?.address ?? '',
                              style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.inkFaint,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (canEdit)
                            GestureDetector(
                              onTap: onEdit,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: AppColors.surface2,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle with stop number.
class _StopNumber extends StatelessWidget {
  final int number;
  final bool isFirst;

  const _StopNumber({required this.number, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFirst ? AppColors.accent : AppColors.surface2,
        border: isFirst ? null : Border.all(color: AppColors.moduleBorder),
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isFirst ? AppColors.surface : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Dashed line painter for the timeline.
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({this.color = AppColors.moduleBorder});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashHeight = 6.0;
    const dashSpace = 6.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(0, startY),
        Offset(0, (startY + dashHeight).clamp(0, size.height)),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}