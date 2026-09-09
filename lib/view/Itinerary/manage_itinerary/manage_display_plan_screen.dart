import '../../../core/utils/schedule_display.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:intl/intl.dart';
import '../../../core/config/api_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/Itinerary/manage_display_plan_vm.dart';
import 'package:narrate_my/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';
import './add_from_bookmark.dart';
import './add_custom_screen.dart';
import './edit_stop_screen.dart';
import './manage_edit_itinerary_screen.dart';
import '../widgets/view_place_detail_screen.dart';

/// Screen that displays a single itinerary with a map, day selector, and day cards.
/// Supports editing if the itinerary is not in the past.
class ManageDisplayPlanScreen extends StatefulWidget {
  final String itineraryId;

  /// When true (opened via "Track"), the screen automatically selects and
  /// scrolls to today's itinerary day once the day cards are rendered.
  /// Normal opens leave this false and behave exactly as before.
  final bool openTrackedDay;

  const ManageDisplayPlanScreen({
    Key? key,
    required this.itineraryId,
    this.openTrackedDay = false,
  }) : super(key: key);

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

  // Ensures "Track today" is applied only once, so later manual day taps are
  // never overridden.
  bool _trackApplied = false;

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

  // ─── Track today's travel plan ─────────────────────────────────
  /// Selects today's itinerary day (via the ViewModel's calendar-day
  /// calculation) and scrolls to it. Runs once; manual selection still works
  /// afterwards. Pure view/navigation — no itinerary/stop data is modified.
  void _trackToday() {
    if (_trackApplied) return;
    _trackApplied = true;

    final today = _viewModel.calculateCurrentDayIndex();
    if (today == null) return;

    if (_selectedMapDayIndex != today) {
      setState(() => _selectedMapDayIndex = today);
    }
    _scrollToDayWhenReady(today);
  }

  /// Scrolls to [dayIndex] once its day card has actually been rendered
  /// (its GlobalKey has a live context), retrying across a few frames.
  void _scrollToDayWhenReady(int dayIndex, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _dayKeys[dayIndex];
      if (key?.currentContext != null) {
        _scrollToDay(dayIndex);
      } else if (attempt < 8) {
        _scrollToDayWhenReady(dayIndex, attempt + 1);
      }
    });
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

  // ─── Tap day card handler ──────────────────────────────────────
  void _onDayCardTap(int dayIndex) {
    // Update the selected map day and scroll to the card
    setState(() {
      _selectedMapDayIndex = dayIndex;
    });
    _scrollToDay(dayIndex);
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

    final availableDays =
        _viewModel.stops.map((s) => s.dayIndex).toSet().toList()..sort();

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
        builder: (_) =>
            AddFromBookmarksScreen(userId: _viewModel.itinerary?.userId ?? ''),
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty && mounted) {
      final added = await _viewModel.addBookmarkedPlaces(
        dayIndex: dayIndex,
        placeIds: selectedIds,
      );
      if (added > 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Added $added bookmark(s).')));
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
    final type =
        place.placeCategory ??
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
      travelIcon: getTransportationIcon(_viewModel.itinerary?.transportationMode),
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

        // Update available days and selected day (0 represents All Days)
        _availableDays = stops.map((s) => s.dayIndex).toSet().toList()..sort();
        if (_availableDays.isNotEmpty &&
            !_availableDays.contains(_selectedMapDayIndex) &&
            _selectedMapDayIndex != 0) {
          _selectedMapDayIndex = _availableDays.first;
        }

        // Track: focus today's day once, after the itinerary has loaded and
        // the day cards are in the tree (post-frame). No-op for normal opens.
        if (widget.openTrackedDay &&
            !_trackApplied &&
            !_viewModel.isLoading &&
            _viewModel.itinerary != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _trackToday();
          });
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
          body: RefreshIndicator(
            onRefresh: () => _viewModel.load(),
            color: AppColors.accent,
            child: ListView(
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
                  onToggleAllDays: () {
                    setState(() {
                      if (_selectedMapDayIndex == 0) {
                        _selectedMapDayIndex = _availableDays.isNotEmpty
                            ? _availableDays.first
                            : 1;
                      } else {
                        _selectedMapDayIndex = 0;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16.0),

                // ─── Day Cards ──────────────────────────────────
                ..._buildDayCards(canEdit),
              ],
            ),
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

    final allDays = grouped.keys.toList()..sort();
    final days = _selectedMapDayIndex == 0
        ? allDays
        : allDays.where((d) => d == _selectedMapDayIndex).toList();
    final itinerary = _viewModel.itinerary;
    final cards = <Widget>[];

    // Prominent section title indicating exactly what day is displayed
    if (_selectedMapDayIndex > 0) {
      final date = itinerary?.startDate.add(Duration(days: _selectedMapDayIndex - 1));
      cards.add(
        Padding(
          padding: const EdgeInsets.only(top: 6.0, bottom: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Day $_selectedMapDayIndex Schedule',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (date != null)
                Text(
                  DateFormat('EEEE, d MMM').format(date),
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      cards.add(
        Padding(
          padding: const EdgeInsets.only(top: 6.0, bottom: 12.0),
          child: Text(
            'All Days Schedule (${allDays.length} Days)',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
      );
    }

    for (final dayIndex in days) {
      final stops = grouped[dayIndex]!
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      final date = itinerary?.startDate.add(Duration(days: dayIndex - 1));
      final dayTitle = 'Day $dayIndex';
      final dayMeta = date != null
          ? '${DateFormat('d MMM').format(date)} • ${stops.length} stops'
          : '${stops.length} stops';

      _dayKeys[dayIndex] ??= GlobalKey();

      // ✅ NEW LOGIC: Combine global edit status with this specific day's date
      final bool canEditThisDay = canEdit && _viewModel.isDayEditable(dayIndex);

      cards.add(
        Container(
          key: _dayKeys[dayIndex],
          child: _DayCard(
            dayIndex: dayIndex,
            dayTitle: dayTitle,
            dayMeta: dayMeta,
            stops: stops,
            dayDate: date ?? DateTime.now(),

            // ✅ APPLY IT: Pass the calculated value to the Day Card
            canEdit: canEditThisDay,

            isSelected: _selectedMapDayIndex == dayIndex,
            onEditDay: () => _openEditDay(dayIndex),
            onEditStop: _openEditStop,
            onAddPlace: (day, date) => _openAddPlace(day, date),
            onAddBookmarks: _openAddBookmarks,
            onStopTap: _openStopDetail,
            onTapDay: _onDayCardTap,
          ),
        ),
      );
      cards.add(const SizedBox(height: 28.0));
    }

    return cards;
  }
}

// ════════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.moduleBorder.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 4),
            blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StatusBadge(status: status),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.accent),
                    const SizedBox(width: 5),
                    Text(
                      '$totalDays ${totalDays == 1 ? 'Day' : 'Days'} Trip',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.2,
            ),
          ),
          if (startDate != null && endDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.date_range_rounded, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Text(
                  '${DateFormat('d MMM yyyy').format(startDate!)} – ${DateFormat('d MMM yyyy').format(endDate!)}',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
        bgColor = const Color(0xFFFFE0B2);
        fgColor = const Color(0xFFE65100);
        icon = Icons.history_rounded;
        label = 'Past';
        break;
      case ItineraryTemporalStatus.ongoing:
        bgColor = const Color(0xFFC8E6C9);
        fgColor = const Color(0xFF2E7D32);
        icon = Icons.play_circle_fill_rounded;
        label = 'Ongoing';
        break;
      case ItineraryTemporalStatus.upcoming:
        bgColor = const Color(0xFFE0F2F1);
        fgColor = AppColors.teal;
        icon = Icons.event_available_rounded;
        label = 'Upcoming';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.nunito(
              color: fgColor,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrollable day selector with "All Days" multi-day option.
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
    // 0 represents All Days, followed by individual days
    final items = [0, ...days];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = items[index];
          final isActive = day == selectedDay;
          final isAll = day == 0;

          return InkWell(
            onTap: () => onDaySelected(day),
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: isActive
                    ? const LinearGradient(
                        colors: [Color(0xFF00796B), Color(0xFF004D40)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isActive ? null : AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isActive ? AppColors.teal : AppColors.moduleBorder,
                  width: isActive ? 1.5 : 1.0,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.teal.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : const [
                        BoxShadow(
                          color: Color(0x05000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isAll) ...[
                      Icon(
                        Icons.map_outlined,
                        size: 14,
                        color: isActive ? Colors.white : AppColors.inkSoft,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      isAll ? 'All Days' : 'Day $day',
                      style: GoogleFonts.nunito(
                        color: isActive ? Colors.white : AppColors.inkSoft,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Google Map card showing stops for a given day or all days.
class _MapCard extends StatelessWidget {
  final List<ItineraryStop> stops;
  final int dayIndex; // 0 for All Days, or specific day number
  final void Function(ItineraryStop) onStopTap;
  final VoidCallback? onToggleAllDays;

  const _MapCard({
    required this.stops,
    required this.dayIndex,
    required this.onStopTap,
    this.onToggleAllDays,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAllDays = dayIndex == 0;
    final List<ItineraryStop> displayedStops;

    if (isAllDays) {
      displayedStops = stops.toList()
        ..sort((a, b) {
          final dayCmp = a.dayIndex.compareTo(b.dayIndex);
          return dayCmp != 0 ? dayCmp : a.stopOrder.compareTo(b.stopOrder);
        });
    } else {
      displayedStops = stops.where((s) => s.dayIndex == dayIndex).toList()
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    }

    final validStops = _MappableStop.fromStops(displayedStops);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: (screenHeight * 0.38).clamp(300.0, 420.0),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: validStops.isEmpty
            ? _EmptyMapState(dayIndex: dayIndex)
            : _DayMapWidget(
                stops: validStops,
                dayIndex: dayIndex,
                onStopTap: onStopTap,
                onToggleAllDays: onToggleAllDays,
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
              dayIndex == 0
                  ? 'No map locations available for this trip'
                  : 'No map location available for Day $dayIndex',
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Google Map widget with movable touch gestures, multi-day routes, and recenter button.
class _DayMapWidget extends StatefulWidget {
  final List<_MappableStop> stops;
  final int dayIndex; // 0 for All Days
  final void Function(ItineraryStop) onStopTap;
  final VoidCallback? onToggleAllDays;

  const _DayMapWidget({
    required this.stops,
    required this.dayIndex,
    required this.onStopTap,
    this.onToggleAllDays,
  });

  @override
  State<_DayMapWidget> createState() => _DayMapWidgetState();
}

class _DayMapWidgetState extends State<_DayMapWidget> {
  maps.GoogleMapController? _mapController;

  static const List<Color> _dayRouteColors = [
    Color(0xFF00796B), // Day 1: Teal
    Color(0xFFFF6F00), // Day 2: Amber
    Color(0xFF7B1FA2), // Day 3: Royal Purple
    Color(0xFF1976D2), // Day 4: Deep Blue
    Color(0xFFE91E63), // Day 5: Vibrant Pink
    Color(0xFF00838F), // Day 6: Cyan
    Color(0xFF388E3C), // Day 7: Forest Green
  ];

  static const List<double> _dayMarkerHues = [
    maps.BitmapDescriptor.hueAzure,
    maps.BitmapDescriptor.hueOrange,
    maps.BitmapDescriptor.hueViolet,
    maps.BitmapDescriptor.hueBlue,
    maps.BitmapDescriptor.hueRose,
    maps.BitmapDescriptor.hueCyan,
    maps.BitmapDescriptor.hueGreen,
  ];

  @override
  void didUpdateWidget(covariant _DayMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayIndex != widget.dayIndex ||
        oldWidget.stops.length != widget.stops.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitMapBounds();
      });
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAllDays = widget.dayIndex == 0;
    final totalDaysCount =
        widget.stops.map((s) => s.stop.dayIndex).toSet().length;

    return Stack(
      fit: StackFit.expand,
      children: [
        maps.GoogleMap(
          initialCameraPosition: _initialCameraPosition(),
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          mapType: maps.MapType.normal,
          compassEnabled: true,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          // ✅ Enable gestures so user can drag, pan, pinch to zoom, and rotate the map freely
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          onMapCreated: (controller) {
            _mapController = controller;
            _fitMapBounds();
          },
        ),

        // ─── Top Left: Day & Stop Badge ─────────────────────────
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.ink.withOpacity(0.85),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x25000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAllDays ? Icons.alt_route_rounded : Icons.place_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  isAllDays
                      ? 'All Days ($totalDaysCount days) • ${widget.stops.length} stops'
                      : 'Day ${widget.dayIndex} • ${widget.stops.length} ${widget.stops.length == 1 ? 'stop' : 'stops'}',
                  style: AppTextStyles.labelSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── Top Right: Quick Toggle Chip (All Days / Single Day) ─
        if (widget.onToggleAllDays != null)
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: widget.onToggleAllDays,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAllDays
                            ? Icons.filter_1_rounded
                            : Icons.layers_rounded,
                        size: 14,
                        color: AppColors.ink,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isAllDays ? 'Single Day' : 'All Days',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ─── Bottom Right: Recenter route button ─────────────────
        Positioned(
          bottom: 12,
          right: 12,
          child: Material(
            color: Colors.white.withOpacity(0.92),
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _fitMapBounds,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.center_focus_strong_rounded,
                  size: 20,
                  color: AppColors.ink,
                ),
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
        target: maps.LatLng(3.1390, 101.6869),
        zoom: 11,
      );
    }
    return maps.CameraPosition(
      target: maps.LatLng(
        widget.stops.first.latitude,
        widget.stops.first.longitude,
      ),
      zoom: 13,
    );
  }

  Set<maps.Marker> _buildMarkers() {
    return widget.stops.map((item) {
      final day = item.stop.dayIndex;
      final hueIndex = (day - 1).clamp(0, _dayMarkerHues.length - 1);
      final hue = widget.dayIndex == 0
          ? _dayMarkerHues[hueIndex]
          : maps.BitmapDescriptor.hueAzure;

      return maps.Marker(
        markerId: maps.MarkerId(
          '${item.stop.dayIndex}_${item.stop.placeId}_${item.stop.stopOrder}',
        ),
        position: maps.LatLng(item.latitude, item.longitude),
        icon: maps.BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: maps.InfoWindow(
          title: item.stop.place?.name ?? item.stop.placeId,
          snippet:
              'Day ${item.stop.dayIndex} • Stop ${item.stop.stopOrder}\n${_formattedTime(item.stop)}',
        ),
        onTap: () => widget.onStopTap(item.stop),
      );
    }).toSet();
  }

  Set<maps.Polyline> _buildPolylines() {
    if (widget.stops.length < 2) return {};

    if (widget.dayIndex == 0) {
      // Group by dayIndex to create a separate polyline per day with distinct colors
      final grouped = <int, List<_MappableStop>>{};
      for (final s in widget.stops) {
        grouped.putIfAbsent(s.stop.dayIndex, () => []).add(s);
      }

      final polylines = <maps.Polyline>{};
      for (final entry in grouped.entries) {
        final day = entry.key;
        final dayStops = entry.value;
        if (dayStops.length < 2) continue;

        final colorIndex = (day - 1).clamp(0, _dayRouteColors.length - 1);
        final color = _dayRouteColors[colorIndex];

        polylines.add(
          maps.Polyline(
            polylineId: maps.PolylineId('day_${day}_route'),
            points: dayStops
                .map((s) => maps.LatLng(s.latitude, s.longitude))
                .toList(),
            color: color,
            width: 4,
          ),
        );
      }
      return polylines;
    }

    // Single day
    return {
      maps.Polyline(
        polylineId: maps.PolylineId('day_${widget.dayIndex}_route'),
        points: widget.stops
            .map((s) => maps.LatLng(s.latitude, s.longitude))
            .toList(),
        color: AppColors.teal,
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
          maps.LatLng(
            widget.stops.first.latitude,
            widget.stops.first.longitude,
          ),
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

    // Safety check: if min == max (e.g. stops at same location), avoid newLatLngBounds crash
    if ((maxLat - minLat).abs() < 0.0001 && (maxLng - minLng).abs() < 0.0001) {
      controller.animateCamera(
        maps.CameraUpdate.newLatLngZoom(
          maps.LatLng(minLat, minLng),
          14,
        ),
      );
      return;
    }

    controller.animateCamera(
      maps.CameraUpdate.newLatLngBounds(
        maps.LatLngBounds(
          southwest: maps.LatLng(minLat, minLng),
          northeast: maps.LatLng(maxLat, maxLng),
        ),
        55,
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
      result.add(_MappableStop(stop: stop, latitude: lat, longitude: lng));
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
  final bool isSelected;
  final VoidCallback onEditDay;
  final Future<void> Function(ItineraryStop) onEditStop;
  final Future<void> Function(int, DateTime) onAddPlace;
  final Future<void> Function(int) onAddBookmarks;
  final void Function(ItineraryStop) onStopTap;
  final void Function(int) onTapDay;

  const _DayCard({
    required this.dayIndex,
    required this.dayTitle,
    required this.dayMeta,
    required this.stops,
    required this.dayDate,
    required this.canEdit,
    required this.isSelected,
    required this.onEditDay,
    required this.onEditStop,
    required this.onAddPlace,
    required this.onAddBookmarks,
    required this.onStopTap,
    required this.onTapDay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTapDay(dayIndex),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : AppColors.moduleBorder.withOpacity(0.6),
            width: isSelected ? 2 : 1,
          ),
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
      ],
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: List.generate(stops.length, (index) {
        final stop = stops[index];
        String? conflict;
        if (index > 0 && !isUnscheduledTime(stop.startTime, stop.endTime, status: stop.stopStatus) &&
            !isUnscheduledTime(stops[index - 1].startTime, stops[index - 1].endTime,
                status: stops[index - 1].stopStatus)) {
          final prev = stops[index - 1];
          final travel = stop.travelFromPrevMinutes ?? 15;
          final minStart = prev.endTime.add(Duration(minutes: travel));
          if (stop.startTime.isBefore(prev.endTime)) {
            final diff = prev.endTime.difference(stop.startTime).inMinutes;
            conflict = 'Time overlap: starts ${formatScheduleMinutes(diff)} before previous stop ends';
          } else if (stop.startTime.isBefore(minStart)) {
            final available = stop.startTime.difference(prev.endTime).inMinutes;
            conflict = 'Travel conflict: only ${formatScheduleMinutes(available)} between stops (needs ${formatScheduleMinutes(travel)})';
          }
        }

        return _StopItem(
          stop: stop,
          number: index + 1,
          isFirst: index == 0,
          isLast: index == stops.length - 1,
          canEdit: canEdit,
          conflict: conflict,
          onTap: () => onStopTap(stop),
          onEdit: () => onEditStop(stop),
        );
      }),
    );
  }

  Widget _buildAddActions() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onAddPlace(dayIndex, dayDate),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accent.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_location_alt_outlined, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Add Custom Place',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => onAddBookmarks(dayIndex),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.moduleBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bookmark_outline_rounded, size: 18, color: AppColors.inkSoft),
                  const SizedBox(width: 6),
                  Text(
                    'Bookmarks',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
  final String? conflict;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _StopItem({
    required this.stop,
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.canEdit,
    this.conflict,
    required this.onTap,
    required this.onEdit,
  });

  String _resolveCategory() {
    final p = stop.place;
    if (p == null) return 'ATTRACTION';
    if (p.placeCategory != null && p.placeCategory!.isNotEmpty) {
      return p.placeCategory!.toUpperCase();
    }
    final types = p.placeTypes.map((t) => t.toLowerCase()).toSet();
    if (types.contains('restaurant') || types.contains('food')) return 'RESTAURANT';
    if (types.contains('cafe') || types.contains('bakery')) return 'CAFE';
    if (types.contains('bar') || types.contains('night_club')) return 'NIGHTLIFE';
    if (types.contains('museum')) return 'MUSEUM';
    if (types.contains('park') || types.contains('natural_feature')) return 'NATURE';
    if (types.contains('place_of_worship')) return 'CULTURE';
    return 'ATTRACTION';
  }

  @override
  Widget build(BuildContext context) {
    final place = stop.place;
    final name = place?.placeName ?? stop.placeId;
    final address = place?.placeAddress ?? '';
    final rating = place?.placeRating ?? 0.0;
    final category = _resolveCategory();
    final isUnscheduled = stop.stopStatus == 'UNSCHEDULED' ||
        (stop.startTime.hour == 0 && stop.startTime.minute == 0 && stop.endTime.hour == 0 && stop.endTime.minute == 0);
    final timeStr = isUnscheduled
        ? 'Unscheduled'
        : '${DateFormat('HH:mm').format(stop.startTime)} – ${DateFormat('HH:mm').format(stop.endTime)}';

    final imgUrl = (place?.placeImageUrl != null && place!.placeImageUrl!.isNotEmpty)
        ? place.placeImageUrl!
        : (place?.placePhotoRef != null && place!.placePhotoRef!.isNotEmpty
            ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${place.placePhotoRef}&key=${ApiKeys.googleMapsApiKey}'
            : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Stack(
        children: [
          if (!isLast)
            Positioned(
              top: 32,
              bottom: 0,
              left: 15,
              child: Container(
                width: 2,
                color: AppColors.moduleBorder,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Node
              SizedBox(
                width: 32,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isFirst
                        ? const LinearGradient(
                            colors: [Color(0xFFE65100), Color(0xFFC0392B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Right Card
              Expanded(
                child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.moduleBorder.withOpacity(0.8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      offset: const Offset(0, 4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Tags: Category & Rating
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2F1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category,
                            style: GoogleFonts.nunito(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.teal,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (rating > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFA000)),
                                const SizedBox(width: 2),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF8D6E63),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Place Image + Name + Address
                    InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: imgUrl != null && imgUrl.isNotEmpty
                                  ? Image.network(
                                      imgUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: AppColors.surface2,
                                        child: const Icon(Icons.photo_outlined, color: AppColors.inkFaint),
                                      ),
                                    )
                                  : Container(
                                      color: AppColors.surface2,
                                      child: const Icon(Icons.place_outlined, color: AppColors.inkFaint),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (address.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    address,
                                    style: GoogleFonts.nunito(
                                      fontSize: 12,
                                      color: AppColors.inkSoft,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'View details',
                                      style: GoogleFonts.nunito(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.teal,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.teal),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (conflict != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFB74D), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE65100)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                conflict!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFD84315),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Divider(height: 1, thickness: 0.8, color: AppColors.moduleBorder.withOpacity(0.6)),
                    const SizedBox(height: 10),

                    // Bottom Bar: Time Pill + Edit Button
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isUnscheduled
                                ? const Color(0xFFFFF8E1)
                                : conflict != null
                                    ? const Color(0xFFFFF3E0)
                                    : const Color(0xFFE0F2F1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isUnscheduled
                                  ? const Color(0xFFFFE082)
                                  : conflict != null
                                      ? const Color(0xFFFFB74D)
                                      : AppColors.teal.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isUnscheduled
                                    ? Icons.access_time_rounded
                                    : conflict != null
                                        ? Icons.warning_amber_rounded
                                        : Icons.schedule_rounded,
                                size: 14,
                                color: isUnscheduled
                                    ? const Color(0xFFE65100)
                                    : conflict != null
                                        ? const Color(0xFFD84315)
                                        : AppColors.teal,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isUnscheduled
                                    ? 'Unscheduled • Tap edit'
                                    : (conflict != null ? '$timeStr (Conflict)' : timeStr),
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isUnscheduled
                                      ? const Color(0xFFE65100)
                                      : conflict != null
                                          ? const Color(0xFFD84315)
                                          : AppColors.teal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (canEdit)
                          InkWell(
                            onTap: onEdit,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.moduleBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.edit_outlined, size: 14, color: AppColors.inkSoft),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Edit',
                                    style: GoogleFonts.nunito(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
    ),
  );
}
}
