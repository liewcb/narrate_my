import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/itinerary_service/add_place_to_day_service.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/Itinerary/add_place_to_day_vm.dart';

// ═══════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

class DayPlan {
  final int dayNumber;
  final DateTime date;
  final List<WizardPlace> places;

  DayPlan({
    required this.dayNumber,
    required this.date,
    required this.places,
  });

  DayPlan copyWith({
    int? dayNumber,
    DateTime? date,
    List<WizardPlace>? places,
  }) {
    return DayPlan(
      dayNumber: dayNumber ?? this.dayNumber,
      date: date ?? this.date,
      places: places ?? List.from(this.places),
    );
  }
}

class WizardPlace {
  final String placeId;
  final String name;
  final String type;
  final IconData typeIcon;
  final double rating;
  final String? imageUrl;
  final String travelTime;
  final IconData travelIcon;
  final String? duration;
  final String location;
  final double latitude;
  final double longitude;
  final DateTime? startTime;
  final DateTime? endTime;

  WizardPlace({
    required this.placeId,
    required this.name,
    required this.type,
    required this.typeIcon,
    required this.rating,
    this.imageUrl,
    required this.travelTime,
    required this.travelIcon,
    this.duration,
    required this.location,
    required this.latitude,
    required this.longitude,
    this.startTime,
    this.endTime,
  });
}

// ═══════════════════════════════════════════════════════════════════════
//  MAIN SCREEN: ManageEditItineraryScreen
// ═══════════════════════════════════════════════════════════════════════

class ManageEditItineraryScreen extends StatefulWidget {
  final int initialDayIndex;
  final List<DayPlan> allDays;

  const ManageEditItineraryScreen({
    super.key,
    required this.initialDayIndex,
    required this.allDays,
  });

  @override
  State<ManageEditItineraryScreen> createState() =>
      _ManageEditItineraryScreenState();
}

class _ManageEditItineraryScreenState extends State<ManageEditItineraryScreen> {
  late final ScrollController _scrollController;
  late List<GlobalKey> _dayKeys;
  late List<DayPlan> _editedDays;
  late List<DayPlan> _initialDaysCopy;
  GoogleMapController? _mapController;

  /// Index (0-based) of the currently active day section. It follows the
  /// traveler's scroll position (scroll listener) and is updated when a day
  /// chip is tapped. Single source of truth for day navigation.
  int _selectedDayIndex = 0;

  /// Preserved from the caller: the day the traveler was reviewing before
  /// editing. Used as the initially active day in the selector.
  late int _initialDayIndex;

  /// Key of the sticky day selector — used to compute the "active line" when
  /// detecting the currently visible day during scrolling.
  final GlobalKey _daySelectorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _editedDays = widget.allDays
        .map((d) => d.copyWith(places: List.from(d.places)))
        .toList();
    _initialDaysCopy = widget.allDays
        .map((d) => d.copyWith(places: List.from(d.places)))
        .toList();
    _initialDayIndex = _editedDays.isEmpty
        ? 0
        : widget.initialDayIndex.clamp(0, _editedDays.length - 1);
    _selectedDayIndex = _editedDays.isEmpty ? 0 : _initialDayIndex;

    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
    _dayKeys = List.generate(_editedDays.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── Scroll → active day detection ─────────────────────────

  /// Updates the active day indicator as the traveler scrolls. This listener
  /// ONLY updates UI state — it never triggers a scroll, so there is no
  /// scroll loop (tap → _scrollToDay → animation → listener updates state).
  void _handleScroll() {
    if (_editedDays.isEmpty) return;
    final detected = _detectActiveDay();
    if (detected != _selectedDayIndex) {
      setState(() {
        _selectedDayIndex = detected;
      });
      _fitMapBoundsForDay(detected);
    }
  }

  /// Determines which day section is currently visible by reading each day's
  /// ACTUAL RenderBox position (GlobalKey context) rather than a fixed pixel
  /// offset — this stays correct when days have different heights.
  int _detectActiveDay() {
    if (_editedDays.isEmpty) return 0;

    // The "active line" is the bottom edge of the sticky day selector.
    double activeLineY = MediaQuery.of(context).size.height;
    final selectorCtx = _daySelectorKey.currentContext;
    if (selectorCtx != null) {
      final box = selectorCtx.findRenderObject() as RenderBox?;
      if (box != null) {
        activeLineY = box.localToGlobal(Offset.zero).dy + box.size.height;
      }
    }

    int detected = 0;
    for (int i = 0; i < _dayKeys.length; i++) {
      final ctx = _dayKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      // The last day whose section top has reached the active line is the
      // one currently being viewed.
      if (top <= activeLineY) detected = i;
    }
    return detected;
  }

  /// Scrolls the page so [dayIndex] is pinned near the top of the visible
  /// area. Uses the ACTUAL day section context (GlobalKey) so each day's
  /// differing height is handled automatically — no hardcoded offsets.
  Future<void> _scrollToDay(int dayIndex) async {
    if (dayIndex < 0 || dayIndex >= _editedDays.length) return;
    final ctx = _dayKeys[dayIndex].currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  void _selectDay(int index) {
    if (index < 0 || index >= _editedDays.length) return;
    _scrollToDay(index);
  }

  /// Recompute the active day after a layout change (add/remove/reorder/
  /// reset) so the selector and map stay in sync.
  void _resyncAfterLayoutChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleScroll();
    });
  }

  void _fitMapBoundsForDay(int dayIndex) {
    if (_mapController == null || _editedDays.isEmpty) return;
    if (dayIndex < 0 || dayIndex >= _editedDays.length) return;
    final places = _editedDays[dayIndex].places;

    if (places.isEmpty) return;

    if (places.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(places.first.latitude, places.first.longitude),
          14,
        ),
      );
      return;
    }

    double minLat = places.first.latitude;
    double maxLat = places.first.latitude;
    double minLng = places.first.longitude;
    double maxLng = places.first.longitude;

    for (var p in places) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50.0,
      ),
    );
  }

  Set<Marker> _buildMarkersForDay(int dayIndex) {
    final places = _editedDays[dayIndex].places;
    final markers = <Marker>{};

    for (int i = 0; i < places.length; i++) {
      final p = places[i];
      markers.add(
        Marker(
          markerId: MarkerId(p.placeId),
          position: LatLng(p.latitude, p.longitude),
          infoWindow: InfoWindow(
            title: '${i + 1}. ${p.name}',
            snippet: p.location,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylinesForDay(int dayIndex) {
    final places = _editedDays[dayIndex].places;
    if (places.length < 2) return {};

    return {
      Polyline(
        polylineId: PolylineId('route_day_${dayIndex + 1}'),
        points: places.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        color: AppColors.green,
        width: 4,
      ),
    };
  }

  void _resetCurrentDay() {
    final idx = _selectedDayIndex;
    if (idx < 0 || idx >= _editedDays.length) return;
    setState(() {
      _editedDays[idx] = _initialDaysCopy[idx].copyWith(
        places: List.from(_initialDaysCopy[idx].places),
      );
    });
    _fitMapBoundsForDay(idx);
    _resyncAfterLayoutChange();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Day ${idx + 1} reset to initial plan.',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.bg),
        ),
        backgroundColor: AppColors.ink,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _saveChanges() {
    Navigator.pop(context, _editedDays);
  }

  void _showAddPlaceSheet(int dayIndex) {
    final day = _editedDays[dayIndex];
    final existingStops = day.places.map(_toStopForContext).toList();
    // Cross-day duplicate guard: a place may not appear twice anywhere in
    // the itinerary (global uniqueness rule).
    final allDayPlaceIds = <String>{
      for (final d in _editedDays)
        for (final p in d.places) p.placeId,
    };

    showModalBottomSheet<AddPlaceInsertResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => _AddPlaceToDaySheet(
        dayNumber: day.dayNumber,
        dayDate: day.date,
        existingStops: existingStops,
        allDayPlaceIds: allDayPlaceIds,
        onInsert: (result) {
          setState(() {
            final places = _editedDays[dayIndex].places;
            final insertIndex = result.insertionIndex < 0
                ? 0
                : (result.insertionIndex > places.length
                ? places.length
                : result.insertionIndex);
            places.insert(insertIndex, result.place);
          });
          if (dayIndex == _selectedDayIndex) {
            _fitMapBoundsForDay(dayIndex);
          }
          _resyncAfterLayoutChange();
          Navigator.pop(ctx, result);
        },
      ),
    );
  }

  /// Converts a [WizardPlace] into an [AddPlaceExistingStop] so the Add
  /// Place validator can validate against the ACTUAL scheduled times of the
  /// existing stops (not a rebuilt approximation).
  AddPlaceExistingStop _toStopForContext(WizardPlace w) {
    final duration = _parseDurationMinutes(w.duration);
    final baseDate = DateTime(2000, 1, 1);
    final start = w.startTime ?? baseDate;
    final end = w.endTime ?? start.add(Duration(minutes: duration));
    return AddPlaceExistingStop(
      place: Place(
        placeId: w.placeId,
        placeName: w.name,
        placeAddress: w.location,
        placeLatitude: w.latitude,
        placeLongitude: w.longitude,
        placeRating: w.rating,
        placeTypes: const [],
        visitDurationMinutes: duration,
      ),
      startTime: start,
      endTime: end,
      durationMinutes: duration,
    );
  }

  int _parseDurationMinutes(String? duration) {
    if (duration == null) return 90;
    final match = RegExp(r'\d+').firstMatch(duration);
    if (match == null) return 90;
    final value = int.parse(match.group(0)!);
    return duration.toLowerCase().contains('hr') ||
        duration.toLowerCase().contains('hour')
        ? value * 60
        : value;
  }

  /// Formats a day date as "12 Aug".
  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  /// Formats a date range as "12 Aug – 15 Aug".
  String _formatDateRange(DateTime first, DateTime last) {
    final a = _formatDate(first);
    final b = _formatDate(last);
    return a == b ? a : '$a – $b';
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD — single vertically scrollable page
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,

      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.ink, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Manage Itinerary',
          style: AppTextStyles.pageTitle,
        ),
        centerTitle: false,
      ),

      body: _editedDays.isEmpty
          ? _buildEmptyItinerary()
          : Column(
        children: [
          // Sticky day selector (navigation control, not a TabBarView).
          _buildDaySelector(),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                bottom: AppSpacing.sectionGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Itinerary hero (once, represents the WHOLE trip).
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenMargin,
                    ),
                    child: _buildItineraryHero(
                      totalDays: _editedDays.length,
                      totalPlaces: _editedDays.fold<int>(
                        0,
                            (sum, day) => sum + day.places.length,
                      ),
                      firstDate: _editedDays.first.date,
                      lastDate: _editedDays.last.date,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.componentGap),
                  // Selected-day interactive map (single map widget).
                  _buildSelectedDayMap(),
                  const SizedBox(height: AppSpacing.sectionGap),
                  // All day sections in one vertical list.
                  for (var i = 0; i < _editedDays.length; i++) ...[
                    _buildDaySection(i),
                    if (i < _editedDays.length - 1)
                      const SizedBox(height: AppSpacing.sectionGap),
                  ],
                ],
              ),
            ),
          ),
          _buildStickyFooter(),
        ],
      ),
    );
  }

  // ─── Sticky day selector ───────────────────────────────────

  Widget _buildDaySelector() {
    return Container(
      key: _daySelectorKey,
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenMargin,
        vertical: 6,
      ),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _editedDays.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final isActive = index == _selectedDayIndex;
            return GestureDetector(
              onTap: () => _selectDay(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pillPaddingX,
                  vertical: AppSpacing.pillPaddingY,
                ),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isActive
                        ? AppColors.accent
                        : AppColors.moduleBorder,
                  ),
                ),
                child: Text(
                  'Day ${index + 1}',
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

  // ─── Itinerary hero (whole trip) ───────────────────────────

  Widget _buildItineraryHero({
    required int totalDays,
    required int totalPlaces,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    // Reuse the first available place photo as the hero backdrop when one
    // exists; otherwise fall back to a themed gradient.
    String? heroImage;
    for (final day in _editedDays) {
      for (final p in day.places) {
        if (p.imageUrl != null && p.imageUrl!.isNotEmpty) {
          heroImage = p.imageUrl;
          break;
        }
      }
      if (heroImage != null) break;
    }

    final dateLabel = _formatDateRange(firstDate, lastDate);

    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.primary],
        ),
        boxShadow: const [
          BoxShadow(
            color: AppShadows.card,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (heroImage != null)
            Image.network(
              heroImage,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (heroImage != null)
            Container(color: AppColors.ink.withOpacity(0.45)),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'YOUR TRAVEL ITINERARY',
                  style: AppTextStyles.sectionLabel.copyWith(
                    color: AppColors.bg,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$totalDays ${totalDays == 1 ? 'Day' : 'Days'} • '
                      '$totalPlaces ${totalPlaces == 1 ? 'Place' : 'Places'}',
                  style: GoogleFonts.nunito(
                    color: AppColors.bg,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: AppColors.bg,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateLabel,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.bg.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Explore your itinerary',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.bg.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Selected-day interactive map (single map widget) ──────

  Widget _buildSelectedDayMap() {
    final dayIndex = _selectedDayIndex;
    final places = _editedDays[dayIndex].places;

    return Container(
      height: 240,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenMargin,
        AppSpacing.screenMargin,
        AppSpacing.screenMargin,
        0,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder),
        boxShadow: const [
          BoxShadow(
            color: AppShadows.card,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: places.isNotEmpty
                ? LatLng(places.first.latitude, places.first.longitude)
                : const LatLng(3.1390, 101.6869),
            zoom: 12,
          ),
          markers: _buildMarkersForDay(dayIndex),
          polylines: _buildPolylinesForDay(dayIndex),
          onMapCreated: (controller) {
            _mapController = controller;
            _fitMapBoundsForDay(dayIndex);
          },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }

  // ─── Day section (GlobalKey) ───────────────────────────────

  Widget _buildDaySection(int index) {
    final day = _editedDays[index];
    final places = day.places;

    return Container(
      key: _dayKeys[index],
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'DAY ${day.dayNumber}',
                style: GoogleFonts.nunito(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _formatDate(day.date),
                  style: AppTextStyles.labelSm,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${places.length} '
                      '${places.length == 1 ? 'place' : 'places'}',
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDayPlaceList(index),
        ],
      ),
    );
  }

  // ─── Modified: Day place list with timeline and editable items ──

  Widget _buildDayPlaceList(int dayIndex) {
    final places = _editedDays[dayIndex].places;

    if (places.isEmpty) {
      return _buildEmptyState(dayIndex);
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: places.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = places.removeAt(oldIndex);
          places.insert(newIndex, item);
        });
        if (dayIndex == _selectedDayIndex) {
          _fitMapBoundsForDay(dayIndex);
        }
        _resyncAfterLayoutChange();
      },
      itemBuilder: (context, index) {
        final place = places[index];
        // Determine transit time from previous stop (if any)
        String? transitTime;
        if (index > 0) {
          // Use the travelTime from the previous place
          transitTime = places[index - 1].travelTime.isNotEmpty
              ? places[index - 1].travelTime
              : null;
        }
        return Container(
          key: ValueKey('day${dayIndex}_${place.placeId}'),
          margin: const EdgeInsets.only(bottom: 8),
          child: _EditableStopItem(
            place: place,
            index: index,
            isFirst: index == 0,
            isLast: index == places.length - 1,
            transitTime: transitTime,
            onRemove: () {
              setState(() {
                places.removeAt(index);
              });
              if (dayIndex == _selectedDayIndex) {
                _fitMapBoundsForDay(dayIndex);
              }
              _resyncAfterLayoutChange();
            },
            onEdit: () {
              // TODO: Open edit bottom sheet or screen for this stop.
              // For now, show a snackbar as a placeholder.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit stop not implemented yet.')),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(int dayIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Icon(Icons.map_outlined, size: 48, color: AppColors.inkFaint),
          const SizedBox(height: AppSpacing.componentGap),
          Text(
            'No places added for Day ${dayIndex + 1}',
            style: AppTextStyles.bodyLg.copyWith(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.cardPadding),
          ElevatedButton.icon(
            onPressed: () => _showAddPlaceSheet(dayIndex),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add, color: AppColors.bg, size: 18),
            label: Text(
              'Add First Place',
              style: AppTextStyles.button,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty itinerary (only when _editedDays.isEmpty) ────────

  Widget _buildEmptyItinerary() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.map_outlined,
            size: 56,
            color: AppColors.inkFaint,
          ),
          const SizedBox(height: AppSpacing.componentGap),
          Text(
            'No itinerary days yet',
            style: AppTextStyles.bodyLg.copyWith(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.cardPadding),
          Text(
            'Select a destination to start planning your trip.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Sticky footer ─────────────────────────────────────────

  Widget _buildStickyFooter() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        boxShadow: [
          BoxShadow(
            color: AppShadows.card,
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _saveChanges,
              child: const Text('Save Changes'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _resetCurrentDay,
              child: Text(
                'Reset Current Day',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.inkFaint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ADD PLACE TO DAY SHEET
// ═══════════════════════════════════════════════════════════════════════

/// Returned by the Add Place sheet: the selected place converted to
/// [WizardPlace] and the insertion position in the day's list.
class AddPlaceInsertResult {
  final WizardPlace place;
  final int insertionIndex;

  const AddPlaceInsertResult({required this.place, required this.insertionIndex});
}

class _AddPlaceToDaySheet extends StatefulWidget {
  final int dayNumber;
  final DateTime dayDate;
  final List<AddPlaceExistingStop> existingStops;
  final Set<String> allDayPlaceIds;
  final ValueChanged<AddPlaceInsertResult> onInsert;

  const _AddPlaceToDaySheet({
    required this.dayNumber,
    required this.dayDate,
    required this.existingStops,
    required this.allDayPlaceIds,
    required this.onInsert,
  });

  @override
  State<_AddPlaceToDaySheet> createState() => _AddPlaceToDaySheetState();
}

class _AddPlaceToDaySheetState extends State<_AddPlaceToDaySheet> {
  late AddPlaceToDayVM _vm;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = AddPlaceToDayVM(
      dayIndex: widget.dayNumber,
      dayDate: widget.dayDate,
      existingDayStops: widget.existingStops,
      allDayPlaceIds: widget.allDayPlaceIds,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.moduleBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add Place to Day ${widget.dayNumber}',
                  style: AppTextStyles.pageTitle.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 16),
                // Search field
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    _vm.query = value;
                    _vm.search();
                  },
                  style: AppTextStyles.bodySm,
                  decoration: InputDecoration(
                    hintText: 'Search attractions, places...',
                    hintStyle: const TextStyle(color: AppColors.inkFaint),
                    prefixIcon: const Icon(Icons.search, color: AppColors.inkFaint),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _vm.query = '';
                      },
                    )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.moduleBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.moduleBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                if (_vm.isSearching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text('Searching...',
                              style: TextStyle(color: AppColors.inkFaint)),
                        ],
                      ),
                    ),
                  )
                else if (_vm.searchError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _vm.searchError!,
                      style: const TextStyle(color: AppColors.inkFaint, fontSize: 14),
                    ),
                  )
                else if (_vm.results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Search for a place to add to this day.',
                        style: TextStyle(color: AppColors.inkFaint, fontSize: 14),
                      ),
                    )
                  else
                    Expanded(
                      child: _buildResultsList(),
                    ),
                const SizedBox(height: 12),
                if (_vm.selectedPlace != null) _buildValidationResult(),
                const SizedBox(height: 12),
                // Add button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _vm.canAdd ? _onAdd : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      _vm.canAdd ? AppColors.accent : AppColors.surface2,
                      foregroundColor:
                      _vm.canAdd ? Colors.white : AppColors.inkFaint,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _vm.confirmed ? 'Added!' : 'Add Place',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultsList() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _vm.results.length,
      itemBuilder: (ctx, idx) {
        final place = _vm.results[idx];
        final isSelected = _vm.selectedPlace?.placeId == place.placeId;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.moduleBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: ListTile(
            leading: Icon(
              place.placeTypes.contains('restaurant') || place.placeTypes.contains('cafe')
                  ? Icons.restaurant
                  : Icons.place,
              color: isSelected ? AppColors.accent : AppColors.teal,
            ),
            title: Text(
              place.placeName,
              style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${place.placeCategory ?? place.placeTypes.firstOrNull ?? 'Attraction'}'
                  '${place.rating > 0 ? ' • ${place.rating}' : ''}',
              style: AppTextStyles.labelSm,
            ),
            trailing: _vm.isValidating && isSelected
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : IconButton(
              icon: Icon(
                isSelected ? Icons.check_circle : Icons.add_circle,
                color: isSelected
                    ? AppColors.green
                    : AppColors.accent,
              ),
              onPressed: isSelected
                  ? null
                  : () => _vm.validateCandidate(place),
            ),
          ),
        );
      },
    );
  }

  Widget _buildValidationResult() {
    final v = _vm.validation;
    if (v == null) return const SizedBox.shrink();
    if (_vm.isValidating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Checking place suitability...',
                style: TextStyle(color: AppColors.inkFaint)),
          ],
        ),
      );
    }
    if (v.isValid) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, size: 18, color: AppColors.green),
                const SizedBox(width: 8),
                const Text('Valid insertion',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.green)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${v.scheduledStartTime ?? '?'} – ${v.scheduledEndTime ?? '?'} '
                  '(${v.visitDurationMinutes} min)',
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            if (v.warningMessage != null) ...[
              const SizedBox(height: 4),
              Text(v.warningMessage!,
                  style: const TextStyle(fontSize: 12, color: AppColors.accent)),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v.errorMessage ?? 'Cannot add this place.',
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _onAdd() async {
    final place = _vm.selectedPlace;
    final validation = _vm.validation;
    if (place == null || validation == null || !validation.isValid) return;

    // Defensive re-validation immediately before insertion (FAIL 10): the
    // itinerary may have changed while the sheet was open. Only a still-valid
    // result is inserted.
    final stillValid = await _vm.revalidateBeforeInsert();
    if (!mounted) return;
    if (!stillValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The itinerary changed. Please re-check this place.',
          ),
        ),
      );
      return;
    }
    final latest = _vm.validation!;

    final photoUrl = place.placePhotoRef != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=400&photoreference=${place.placePhotoRef}'
        '&key=${ApiKeys.googleMapsApiKey}'
        : null;
    final category = place.placeCategory ??
        (place.placeTypes.isNotEmpty ? place.placeTypes.first : 'Attraction');
    final icon = place.placeTypes.contains('restaurant') || place.placeTypes.contains('cafe')
        ? Icons.restaurant
        : place.placeTypes.contains('museum')
        ? Icons.museum
        : Icons.place;

    final scheduledStart = _parseTimeOfDay(latest.scheduledStartTime);
    final scheduledEnd = _parseTimeOfDay(latest.scheduledEndTime);
    final baseDate = widget.dayDate;

    final wizardPlace = WizardPlace(
      placeId: place.placeId,
      name: place.placeName,
      type: category,
      typeIcon: icon,
      rating: place.placeRating,
      imageUrl: photoUrl,
      travelTime: latest.travelFromPreviousMinutes > 0
          ? '${latest.travelFromPreviousMinutes} min'
          : '',
      travelIcon: Icons.directions_car,
      duration: '${latest.visitDurationMinutes} min',
      location: place.placeAddress,
      latitude: place.placeLatitude,
      longitude: place.placeLongitude,
      startTime: scheduledStart != null
          ? DateTime(baseDate.year, baseDate.month, baseDate.day,
          scheduledStart.hour, scheduledStart.minute)
          : null,
      endTime: scheduledEnd != null
          ? DateTime(baseDate.year, baseDate.month, baseDate.day,
          scheduledEnd.hour, scheduledEnd.minute)
          : null,
    );

    _vm.confirm();
    widget.onInsert(AddPlaceInsertResult(
      place: wizardPlace,
      insertionIndex: latest.insertionIndex,
    ));
  }

  TimeOfDay? _parseTimeOfDay(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  NEW: Editable Stop Item (with image, timeline, drag, edit, remove)
// ═══════════════════════════════════════════════════════════════════════

class _EditableStopItem extends StatelessWidget {
  final WizardPlace place;
  final int index;
  final bool isFirst;
  final bool isLast;
  final String? transitTime;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _EditableStopItem({
    required this.place,
    required this.index,
    required this.isFirst,
    required this.isLast,
    this.transitTime,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Transit indicator above the stop (if not first)
        if (!isFirst && transitTime != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.directions_car, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Text(
                  transitTime!,
                  style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
        ],
        // Stop row: timeline dot + content
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline column
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst ? AppColors.primary : AppColors.moduleBorder,
                    border: Border.all(
                      color: isFirst ? Colors.transparent : AppColors.surface,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 40,
                    color: AppColors.moduleBorder,
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Content card (with drag handle, image, details, remove button)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFirst ? AppColors.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: isFirst
                      ? null
                      : Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    // Thumbnail image (same size as final screen)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 56,
                        height: 56,
                        color: AppColors.surface2,
                        child: place.imageUrl != null
                            ? Image.network(
                          place.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_not_supported),
                        )
                            : const Center(child: Text('📍', style: TextStyle(fontSize: 24))),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            '${place.type} · ${place.duration ?? ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Action buttons: drag handle, edit, remove
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle (reorder)
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle, color: AppColors.inkFaint),
                        ),
                        const SizedBox(width: 4),
                        // Edit button
                        GestureDetector(
                          onTap: onEdit,
                          child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.inkSoft),
                        ),
                        const SizedBox(width: 4),
                        // Remove button
                        GestureDetector(
                          onTap: onRemove,
                          child: const Icon(Icons.close, size: 18, color: AppColors.error),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}