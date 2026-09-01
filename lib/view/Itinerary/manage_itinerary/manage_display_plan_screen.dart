import 'package:flutter/material.dart';
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
import 'interactive_maps_screen.dart';
import 'manage_edit_itinerary_screen.dart';
import '../widgets/view_place_detail_screen.dart';

class ManageDisplayPlanScreen extends StatefulWidget {
  final String itineraryId;

  const ManageDisplayPlanScreen({Key? key, required this.itineraryId})
      : super(key: key);

  @override
  State<ManageDisplayPlanScreen> createState() => _ManageDisplayPlanScreenState();
}

class _ManageDisplayPlanScreenState extends State<ManageDisplayPlanScreen> {
  late ManageDisplayPlanViewModel _viewModel;

  // Stores GlobalKeys for each day to allow targeted scrolling
  final Map<int, GlobalKey> _dayKeys = {};

  // Scroll controller for the day-navigation (All Days scrolls to top).
  final ScrollController _scrollController = ScrollController();

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

  // Selects the day filter and scrolls to the corresponding content.
  // null = All Days → scroll back to the top of the itinerary content.
  void _selectDay(int? dayIndex) {
    // 1. Handle "All Days" top scroll
    if (dayIndex == null) {
      _viewModel.selectDay(null);
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
      return;
    }

    // 2. Perform smooth scroll to the target day key
    final key = _dayKeys[dayIndex];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        alignment: 0.05, // Position near top of viewport
      );
    }

    // 3. Update the selected tab highlight in ViewModel
    _viewModel.selectDay(dayIndex);
  }

  /// Validates if a specific day can be edited.
  /// Now it simply returns true if the entire itinerary is customizable.
  bool _canEditDay(DateTime dayDate) {
    return _viewModel.canCustomize;
  }

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
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.ink),
                onSelected: (value) {
                  if (value == 'interactive_map') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InteractiveMapsScreen(
                          itineraryId: widget.itineraryId,
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'interactive_map',
                    child: Row(
                      children: [
                        Icon(Icons.map_outlined, color: AppColors.ink),
                        SizedBox(width: 12),
                        Text('Interactive Map (All)'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Stack(
            children: [
              ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(
                  left: 20.0,
                  right: 20.0,
                  top: 8.0,
                  bottom: 160.0,
                ),
                children: [
                  _buildHeroSection(itinerary),
                  const SizedBox(height: 24.0),

                  // Jump To Day Navigation Tabs
                  // _buildDayNavigationTabs(),
                  // const SizedBox(height: 16.0),

                  ..._buildDayCards(),
                ],
              ),
              _buildStickyBottomBar(context),
            ],
          ),
        );
      },
    );
  }

  // ─── Hero Section ───────────────────────────────────────────

  Widget _buildHeroSection(dynamic itinerary) {
    final heroImageUrl = _viewModel.getHeroImageUrl(_viewModel.selectedDayFilter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            height: 180,
            width: double.infinity,
            color: AppColors.accent.withOpacity(0.15),
            child: heroImageUrl != null
                ? Image.network(
              heroImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.map_outlined,
                  size: 56,
                  color: AppColors.inkFaint,
                ),
              ),
            )
                : const Center(
              child: Icon(
                Icons.map_outlined,
                size: 56,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                itinerary?.title ?? 'My Trip',
                style: AppTextStyles.pageTitle,
              ),
            ),
            const SizedBox(width: 8.0),
            _buildStatusBadge(),
          ],
        ),
        const SizedBox(height: 6.0),
        Text(
          itinerary != null
              ? '${itinerary.totalDays} Days • ${DateFormat('d MMM').format(itinerary.startDate)} – ${DateFormat('d MMM').format(itinerary.endDate)}'
              : '',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Widget _buildStatusBadge() {
    final status = _viewModel.temporalStatus;
    // Default styling for all statuses except 'past'
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

  // ─── Jump to Day Tabs ────────────────────────────────────────

  Widget _buildDayNavigationTabs() {
    final days = _viewModel.availableDayIndices;
    if (days.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'JUMP TO DAY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 12.0),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              // "All Days" is always the first tab.
              _buildDayTabItem('All Days', null, Icons.view_day_outlined),
              const SizedBox(width: 12),
              for (final day in days) ...[
                _buildDayTabItem('Day $day', day, Icons.calendar_today_outlined),
                const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayTabItem(String label, int? dayIndex, IconData icon) {
    final isActive = _viewModel.selectedDayFilter == dayIndex;

    return GestureDetector(
      onTap: () => _selectDay(dayIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.moduleBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? AppColors.bg : AppColors.ink,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.labelSm.copyWith(
                color: isActive ? AppColors.bg : AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Day Cards & Timeline ──────────────────────────────────────

  List<Widget> _buildDayCards() {
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
          child: _buildDaySection(
            dayTitle: dayTitle,
            dayMeta: dayMeta,
            stops: stops,
            dayIndex: dayIndex,
            dayDate: date ?? DateTime.now(),
          ),
        ),
      );
      cards.add(const SizedBox(height: 28.0));
    }

    return cards;
  }

  Widget _buildDaySection({
    required String dayTitle,
    required String dayMeta,
    required List<ItineraryStop> stops,
    required int dayIndex,
    required DateTime dayDate,
  }) {
    // Now simply checks overall editability – all days of editable trips show the button.
    final canEditThisDay = _canEditDay(dayDate);

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
            // Day Header Row with Edit Button
            Row(
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
                if (canEditThisDay)
                  OutlinedButton.icon(
                    onPressed: () => _openEditDay(dayIndex),
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
            ),
            const SizedBox(height: 20.0),

            // Timeline Section
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

            Stack(
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
                    return _buildStopItem(
                      stop: stop,
                      number: index + 1,
                      isFirst: index == 0,
                      isLast: index == stops.length - 1,
                      canEdit: canEditThisDay,
                    );
                  }),
                ),
              ],
            ),

            // Add Place Actions
            if (canEditThisDay) ...[
              const SizedBox(height: 12.0),
              GestureDetector(
                onTap: () => _openAddPlace(dayIndex, dayDate),
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
                onTap: () => _openAddBookmarks(dayIndex),
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
          ],
        ));
  }

  Widget _buildStopItem({
    required ItineraryStop stop,
    required int number,
    required bool isFirst,
    required bool isLast,
    bool canEdit = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Number indicator
          Container(
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
          ),
          const SizedBox(width: 14),

          // Stop Card
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openStop(stop),
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
                              onTap: () => _openEditStop(stop),
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

  Future<void> _openStop(ItineraryStop stop) async {
    if (stop.placeId.isEmpty && stop.place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open this place. Place information is unavailable.',
          ),
        ),
      );
      return;
    }

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

  /// Opens the Edit Stop screen for a specific stop. Editing is localized to
  /// the selected stop — it never regenerates the whole itinerary. Reloads
  /// the plan state on return so Preview reflects the change.
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

  // ─── Sticky Bottom Bar ──────────────────────────────────────

  Widget _buildStickyBottomBar(BuildContext context) {
    if (!_viewModel.canCustomize) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.only(
            left: 20.0,
            right: 20.0,
            top: 16.0,
            bottom: MediaQuery.of(context).padding.bottom + 16.0,
          ),
          decoration: BoxDecoration(
            color: AppColors.bg.withOpacity(0.95),
            border: Border(top: BorderSide(color: AppColors.moduleBorder)),
          ),
          child: Text(
            _viewModel.isReadOnly
                ? 'This itinerary is in the past and is read-only.'
                : 'This itinerary is upcoming — you can view it but progress cannot be recorded yet.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20.0,
          right: 20.0,
          top: 14.0,
          bottom: MediaQuery.of(context).padding.bottom + 14.0,
        ),
        decoration: BoxDecoration(
          color: AppColors.bg.withOpacity(0.95),
          border: Border(
            top: BorderSide(color: AppColors.moduleBorder),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _viewModel.isSaving ? null : () => _discardChanges(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: BorderSide(color: AppColors.moduleBorder),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                child: const Text('Discard'),
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _viewModel.isSaving ? null : () => _saveChanges(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                child: Text(_viewModel.isSaving ? 'Saving…' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChanges(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _viewModel.saveChanges();
      messenger.showSnackBar(
        const SnackBar(content: Text('Itinerary saved.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  Future<void> _discardChanges(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Unsaved customization changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _viewModel.load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes discarded.')),
      );
    }
  }
}

// ─── Dashed Line Custom Painter ────────────────────────────────

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