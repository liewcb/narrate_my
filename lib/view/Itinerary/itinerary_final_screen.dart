// lib/screens/itinerary_final_screen.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import 'add_place_screen.dart';
import '../../core/theme/colors.dart';

class StopData {
  final String time;
  final String duration;
  final String name;
  final String type;
  final String? imageUrl;
  final String? transit;
  final bool isHighlighted;

  StopData({
    required this.time,
    required this.duration,
    required this.name,
    required this.type,
    this.imageUrl,
    this.transit,
    this.isHighlighted = false,
  });
}

class DayData {
  final int dayNumber;
  final String date;
  final int totalStops;
  final String? timeRange;
  final bool isSelected;
  final List<StopData> stops;

  DayData({
    required this.dayNumber,
    required this.date,
    required this.totalStops,
    this.timeRange,
    this.isSelected = false,
    required this.stops,
  });
}

class ItineraryFinalScreen extends StatefulWidget {
  /// The generated itinerary (from the Step 5 pipeline). When null the
  /// screen shows its demo data instead.
  final ItineraryResult? result;

  const ItineraryFinalScreen({super.key, this.result});

  @override
  State<ItineraryFinalScreen> createState() => _ItineraryFinalScreenState();
}

class _ItineraryFinalScreenState extends State<ItineraryFinalScreen> {
  int _selectedDayIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _dayKeys; // âœ… fixed: late final

  // â”€â”€â”€ Data (from the generation result when available) â”€â”€â”€â”€â”€â”€â”€â”€
  late final List<DayData> _days;

  List<DayData> get _finalDays =>
      widget.result?.scheduledDays != null
          ? _fromScheduledDays(widget.result!.scheduledDays!)
          : const [];

  final List<DayData> _mockDays = [
    DayData(
      dayNumber: 1,
      date: 'Mon, Aug 12',
      totalStops: 3,
      timeRange: '9:00 AM - 6:00 PM',
      isSelected: true,
      stops: [
        StopData(
          time: '9:00 AM',
          duration: '2 hrs',
          name: 'Batu Caves',
          type: 'Cultural â€¢ 4.8 â˜… â€¢ Must-go',
          imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=200&q=80',
          transit: '12 min drive â€¢ 8.2 km',
          isHighlighted: true,
        ),
        StopData(
          time: '12:30 PM',
          duration: '1.5 hrs',
          name: 'Precious Old China',
          type: 'Restaurant â€¢ You added',
          imageUrl: null,
          transit: '8 min walk',
          isHighlighted: false,
        ),
        StopData(
          time: '4:00 PM',
          duration: '2 hrs',
          name: 'Petronas Towers',
          type: 'Viewpoint â€¢ Sunset spot',
          imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=200&q=80',
          transit: null,
          isHighlighted: false,
        ),
      ],
    ),
    DayData(
      dayNumber: 2,
      date: 'Tue, Aug 13',
      totalStops: 2,
      timeRange: null,
      isSelected: false,
      stops: [
        StopData(
          time: '10:00 AM',
          duration: '1.5 hrs',
          name: 'Islamic Arts Museum',
          type: 'Museum â€¢ 4.7 â˜…',
          imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=200&q=80',
          transit: null,
          isHighlighted: false,
        ),
        StopData(
          time: '1:00 PM',
          duration: '2 hrs',
          name: 'Central Market',
          type: 'Shopping â€¢ 4.6 â˜…',
          imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=200&q=80',
          transit: null,
          isHighlighted: false,
        ),
      ],
    ),
    DayData(
      dayNumber: 3,
      date: 'Wed, Aug 14',
      totalStops: 2,
      timeRange: null,
      isSelected: false,
      stops: [
        StopData(
          time: '9:30 AM',
          duration: '2 hrs',
          name: 'Batu Caves',
          type: 'Cultural â€¢ 4.8 â˜…',
          imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=200&q=80',
          transit: null,
          isHighlighted: false,
        ),
        StopData(
          time: '2:00 PM',
          duration: '3 hrs',
          name: 'KL Tower',
          type: 'Viewpoint â€¢ 4.5 â˜…',
          imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=200&q=80',
          transit: null,
          isHighlighted: false,
        ),
      ],
    ),
    DayData(
      dayNumber: 4,
      date: 'Thu, Aug 15',
      totalStops: 2,
      timeRange: null,
      isSelected: false,
      stops: [
        StopData(
          time: '8:00 AM',
          duration: '3 hrs',
          name: 'Penang Hill',
          type: 'Nature â€¢ 4.9 â˜…',
          imageUrl:
          'https://images.unsplash.com/photo-1533105079780-92b9be482077?w=200&q=80',
          transit: null,
          isHighlighted: false,
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _days = _finalDays.isNotEmpty ? _finalDays : _mockDays;
    _dayKeys = List.generate(_days.length, (_) => GlobalKey()); // âœ… assigned here
  }

  /// Convert the pipeline's [ScheduledDay] list into the screen's
  /// [DayData] display model.
  List<DayData> _fromScheduledDays(List<ScheduledDay> days) {
    final formatter = DateFormat('EEE, MMM d');
    return days.map((day) {
      final stops = day.stops.map((s) {
        final place = s.attraction.place;
        return StopData(
          time: _fmtTime(s.startTime),
          duration: '${s.durationMinutes} min',
          name: place.placeName,
          type: place.category ?? (place.placeTypes.isNotEmpty ? place.placeTypes.first : 'Attraction'),
          imageUrl: place.placePhotoRef != null
              ? 'https://maps.googleapis.com/maps/api/place/photo'
                  '?maxwidth=200&photoreference=${place.placePhotoRef}'
              : null,
          transit: s.attraction.matchedInterest.isNotEmpty
              ? s.attraction.matchedInterest
              : null,
          isHighlighted: day.stops.isNotEmpty && s == day.stops.first,
        );
      }).toList();

      final first = day.stops.isNotEmpty ? day.stops.first : null;
      final last = day.stops.isNotEmpty ? day.stops.last : null;

      return DayData(
        dayNumber: day.dayIndex + 1,
        date: formatter.format(day.date),
        totalStops: stops.length,
        timeRange: (first != null && last != null)
            ? '${_fmtTime(first.startTime)} - ${_fmtTime(last.endTime)}'
            : null,
        isSelected: day.dayIndex == _selectedDayIndex,
        stops: stops,
      );
    }).toList();
  }

  String _fmtTime(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:$m $ampm';
  }

  /// Derived stats from the generated data.
  String get _title => widget.result?.scheduledDays?.isNotEmpty == true
      ? '${widget.result!.scheduledDays!.length}-Day Trip'
      : 'Kuala Lumpur Getaway';

  String get _dateRange {
    final days = widget.result?.scheduledDays;
    if (days == null || days.isEmpty) return 'Aug 12-15';
    final first = days.first.date;
    final last = days.last.date;
    return '${DateFormat('MMM d').format(first)} â€“ ${DateFormat('MMM d').format(last)}';
  }

  int get _totalStops => widget.result?.scheduledDays?.fold<int>(
          0, (sum, d) => sum + d.stops.length) ??
      0;

  Duration get _totalTravelTime => Duration(
      minutes: widget.result?.scheduledDays?.fold<int>(
              0, (sum, d) => sum + d.totalTravelTime.toInt()) ??
          0);

  int get _cityCount => widget.result?.scheduledDays?.isNotEmpty == true
      ? 1
      : 2;

  void _selectDay(int index) {
    setState(() {
      _selectedDayIndex = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _dayKeys[index];
      if (key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _HeroSection(
              title: _title,
              dateRange: _dateRange,
              places: '${_totalStops}',
              days: '${_days.length}',
            ),
          ),
          SliverToBoxAdapter(
            child: _StatsBar(
              places: _totalStops,
              transit: '${_totalTravelTime.inHours}h',
              cities: _cityCount,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _DayPillsDelegate(
              days: _days,
              selectedIndex: _selectedDayIndex,
              onDaySelected: _selectDay,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final day = _days[index];
                return Container(
                  key: _dayKeys[index],
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: _DayCard(
                    day: day,
                    isSelected: index == _selectedDayIndex,
                    onAddPlace: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddPlaceScreen(
                            itineraryId: 'draft',
                            dayIndex: index,
                          ),
                        ),
                      );
                    },
                    onEditDay: () {
                      // Navigate to edit itinerary screen
                    },
                  ),
                );
              },
              childCount: _days.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      bottomNavigationBar: _BottomActions(),
    );
  }
}

// â”€â”€â”€ Subâ€‘Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _HeroSection extends StatelessWidget {
  final String title;
  final String dateRange;
  final String places;
  final String days;

  const _HeroSection({
    required this.title,
    required this.dateRange,
    required this.places,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=800&q=80',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.3, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _roundIconButton(Icons.arrow_back, () => Navigator.pop(context)),
                Row(
                  children: [
                    _roundIconButton(Icons.share, () {}),
                    const SizedBox(width: 8),
                    _roundIconButton(Icons.more_horiz, () {}),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _badge('Editable', Colors.white.withOpacity(0.2), Colors.white),
                    const SizedBox(width: 8),
                    _badge('$days Days', AppColors.terracotta, Colors.white),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      '$dateRange â€¢ $places places',
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: textColor,
        ),
      ),
    );
  }

  // âœ… Corrected with BackdropFilter
  Widget _roundIconButton(IconData icon, VoidCallback onPressed) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 24),
          onPressed: onPressed,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int places;
  final String transit;
  final int cities;

  const _StatsBar({
    required this.places,
    required this.transit,
    required this.cities,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), offset: Offset(0, 8), blurRadius: 24),
        ],
      ),
      child: Row(
        children: [
          _statItem('$places', 'Places'),
          Container(width: 1, height: 32, color: AppColors.outlineLight),
          _statItem(transit, 'Transit'),
          Container(width: 1, height: 32, color: AppColors.outlineLight),
          _statItem('$cities', 'Cities'),
        ],
      ),
    );
  }

  Widget _statItem(String number, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            number,
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayPillsDelegate extends SliverPersistentHeaderDelegate {
  final List<DayData> days;
  final int selectedIndex;
  final ValueChanged<int> onDaySelected;

  _DayPillsDelegate({
    required this.days,
    required this.selectedIndex,
    required this.onDaySelected,
  });

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: minExtent, // must fill the declared extent for a pinned header
      child: Container(
        color: AppColors.creamBg.withOpacity(0.9),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(days.length, (index) {
              final day = days[index];
              final isSelected = index == selectedIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onDaySelected(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.pineGreen : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: isSelected ? AppColors.pineGreen : AppColors.outlineLight,
                      ),
                    ),
                    child: Text(
                      'Day ${day.dayNumber}${index == 0 ? ' â€¢ ${day.date}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : AppColors.mutedText,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}

class _DayCard extends StatelessWidget {
  final DayData day;
  final bool isSelected;
  final VoidCallback onAddPlace;
  final VoidCallback onEditDay;

  const _DayCard({
    required this.day,
    required this.isSelected,
    required this.onAddPlace,
    required this.onEditDay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected ? AppColors.pineGreen : AppColors.outlineLight.withOpacity(0.6),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, 4), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Day ${day.dayNumber}',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.pineGreen,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Selected',
                              style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      day.date,
                      style: const TextStyle(fontSize: 12, color: AppColors.mutedText),
                    ),
                    if (day.timeRange != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${day.totalStops} stops â€¢ ${day.timeRange}',
                        style: const TextStyle(fontSize: 12, color: AppColors.mutedText),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                GestureDetector(
                  onTap: onEditDay,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.creamBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: AppColors.textPrimary, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Stops
          ..._buildStops(),

          // Add button
          if (isSelected) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onAddPlace,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.outlineLight, width: 1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, size: 16, color: AppColors.mutedText),
                    const SizedBox(width: 6),
                    Text(
                      'Add a place to Day ${day.dayNumber}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildStops() {
    final List<Widget> widgets = [];
    for (int i = 0; i < day.stops.length; i++) {
      final stop = day.stops[i];
      widgets.add(
        _StopItem(
          stop: stop,
          isFirst: i == 0,
          isLast: i == day.stops.length - 1,
          isActive: day.isSelected,
        ),
      );
      if (i < day.stops.length - 1 && stop.transit != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.directions_car, size: 14, color: AppColors.mutedText),
                const SizedBox(width: 6),
                Text(
                  stop.transit!,
                  style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _StopItem extends StatelessWidget {
  final StopData stop;
  final bool isFirst;
  final bool isLast;
  final bool isActive;

  const _StopItem({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFirst ? AppColors.pineGreen : AppColors.outlineLight,
                border: Border.all(color: isFirst ? Colors.transparent : Colors.white, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: AppColors.outlineLight,
              ),
          ],
        ),
        const SizedBox(width: 12),

        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${stop.time} â€¢ ${stop.duration}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isFirst ? AppColors.pineGreen : AppColors.mutedText,
                ),
              ),
              const SizedBox(height: 6),

              // Card
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFirst ? AppColors.creamBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: isFirst ? null : Border.all(color: AppColors.outlineLight.withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    if (stop.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          stop.imageUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.creamBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(child: Text('ðŸœ', style: TextStyle(fontSize: 24))),
                      ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            stop.type,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      const Icon(Icons.drag_indicator, color: AppColors.mutedText, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        border: Border(top: BorderSide(color: AppColors.outlineLight.withOpacity(0.6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.outlineLight),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.refresh, size: 18),
                  const SizedBox(width: 6),
                  const Text('Regenerate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pineGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 8,
                shadowColor: AppColors.pineGreen.withOpacity(0.25),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 18),
                  const SizedBox(width: 6),
                  const Text('Save Itinerary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
