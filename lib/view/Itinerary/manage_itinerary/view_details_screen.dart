import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:narrate_my/view/Itinerary/itinerary_theme_tokens.dart';

// ─── Data Models ─────────────────────────────────────────────
class StopData {
  final String time;
  final String duration;
  final String name;
  final String type;
  final String? imageUrl;
  final String? transit;
  final bool isHighlighted;
  final String status; // 'Planned', 'Completed', 'Skipped'
  final String? skipReason; // e.g., "Rainy weather"

  StopData({
    required this.time,
    required this.duration,
    required this.name,
    required this.type,
    this.imageUrl,
    this.transit,
    this.isHighlighted = false,
    this.status = 'Planned',
    this.skipReason,
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

class ItineraryData {
  final String id;
  final String title;
  final String dateRange;
  final int totalPlaces;
  final int totalDays;
  final String status; // "Upcoming", "Ongoing", "Past"
  final List<DayData> days;

  ItineraryData({
    required this.id,
    required this.title,
    required this.dateRange,
    required this.totalPlaces,
    required this.totalDays,
    required this.status,
    required this.days,
  });
}

// ─── Main Screen ──────────────────────────────────────────────

class ItineraryDetailScreen extends StatefulWidget {
  final String itineraryId;

  const ItineraryDetailScreen({
    super.key,
    required this.itineraryId,
  });

  @override
  State<ItineraryDetailScreen> createState() => _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends State<ItineraryDetailScreen> {
  int _selectedDayIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _dayKeys;

  Future<ItineraryData> _fetchItinerary(String id) async {
    await Future.delayed(const Duration(milliseconds: 600));

    return ItineraryData(
      id: id,
      title: 'Penang Heritage Walk',
      dateRange: 'Oct 14-17',
      totalPlaces: 8,
      totalDays: 4,
      status: 'Ongoing',
      days: [
        DayData(
          dayNumber: 1,
          date: 'Mon, Oct 14',
          totalStops: 4,
          timeRange: '9:00 AM - 4:30 PM',
          isSelected: true,
          stops: [
            // 1. Completed Stop
            StopData(
              time: '9:00 AM',
              duration: '1.5 hrs',
              name: 'Pinang Peranakan Mansion',
              type: 'Museum • 4.8 ★',
              imageUrl: 'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=200&q=80',
              transit: '10 min walk',
              status: 'Completed',
            ),
            // 2. Skipped Stop with Reason
            StopData(
              time: '11:00 AM',
              duration: '1 hr',
              name: 'Fort Cornwallis',
              type: 'Historical • 4.2 ★',
              imageUrl: null,
              transit: '15 min walk',
              status: 'Skipped',
              skipReason: 'Raining heavily. Moved to tomorrow.',
            ),
            // 3. Active / Ongoing Stop
            StopData(
              time: '12:30 PM',
              duration: '1.5 hrs',
              name: 'ChinaHouse Restaurant',
              type: 'Restaurant • Lunch',
              imageUrl: 'https://images.unsplash.com/photo-1533105079780-92b9be482077?w=200&q=80',
              transit: '5 min walk',
              isHighlighted: true, // Triggers the Active State
              status: 'Planned',
            ),
            // 4. Upcoming Planned Stop
            StopData(
              time: '2:30 PM',
              duration: '2 hrs',
              name: 'Street Art George Town',
              type: 'Attraction • 4.9 ★',
              imageUrl: 'https://images.unsplash.com/photo-1540541338287-41700207dee6?w=200&q=80',
              transit: null,
              status: 'Planned',
            ),
          ],
        ),
        DayData(
          dayNumber: 2,
          date: 'Tue, Oct 15',
          totalStops: 2,
          isSelected: false,
          stops: [
            StopData(
              time: '10:00 AM',
              duration: '2 hrs',
              name: 'Kek Lok Si Temple',
              type: 'Cultural • 4.7 ★',
              status: 'Planned',
            ),
          ],
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _dayKeys = [];
  }

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
      backgroundColor: AppColors.bg,
      body: FutureBuilder<ItineraryData>(
        future: _fetchItinerary(widget.itineraryId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.green));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading itinerary: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          if (_dayKeys.isEmpty) {
            _dayKeys.addAll(List.generate(data.days.length, (_) => GlobalKey()));
          }
          return _buildContent(data);
        },
      ),
    );
  }

  Widget _buildContent(ItineraryData data) {
    final days = data.days;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: _HeroSection(
            title: data.title,
            dateRange: data.dateRange,
            places: data.totalPlaces.toString(),
            days: data.totalDays.toString(),
            status: data.status,
          ),
        ),
        SliverToBoxAdapter(
          child: _StatsBar(places: data.totalPlaces, transit: '4h', cities: 2),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _DayPillsDelegate(
            days: days,
            selectedIndex: _selectedDayIndex,
            onDaySelected: _selectDay,
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              final day = days[index];
              return Container(
                key: _dayKeys[index],
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _DayCard(
                  day: day,
                  isSelected: index == _selectedDayIndex,
                  onAddPlace: () {},
                  onEditDay: () {},
                  isEditable: true,
                ),
              );
            },
            childCount: days.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}


class _HeroSection extends StatelessWidget {
  final String title, dateRange, places, days, status;

  const _HeroSection({
    required this.title, required this.dateRange, required this.places, required this.days, required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor = status.toLowerCase() == 'ongoing' ? AppColors.accent : AppColors.green;

    return SizedBox(
      height: 380,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network('https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=800&q=80', fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.8)],
              ),
            ),
          ),
          Positioned(
            top: 24, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _roundIconButton(Icons.arrow_back, () => Navigator.pop(context)),
                Row(
                  children: [
                    _roundIconButton(Icons.share, () {}),
                    const SizedBox(width: 8),
                    _roundIconButton(Icons.more_vert, () {}),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 24, left: 24, right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _badge(status, statusColor, Colors.white),
                    const SizedBox(width: 8),
                    _badge('$days Days', AppColors.accent, Colors.white),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.playfairDisplay(fontSize: 32, fontWeight: FontWeight.w700, height: 1.1, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text('$dateRange • $places places', style: const TextStyle(fontSize: 13, color: Colors.white70)),
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
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: textColor)),
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onPressed) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
        child: IconButton(icon: Icon(icon, color: Colors.white, size: 24), onPressed: onPressed),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int places, cities;
  final String transit;

  const _StatsBar({required this.places, required this.transit, required this.cities});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), offset: Offset(0, 8), blurRadius: 24)],
      ),
      child: Row(
        children: [
          _statItem('$places', 'Places'),
          Container(width: 1, height: 32, color: AppColors.moduleBorder),
          _statItem(transit, 'Transit'),
          Container(width: 1, height: 32, color: AppColors.moduleBorder),
          _statItem('$cities', 'Cities'),
        ],
      ),
    );
  }

  Widget _statItem(String number, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(number, style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.inkFaint)),
        ],
      ),
    );
  }
}

class _DayPillsDelegate extends SliverPersistentHeaderDelegate {
  final List<DayData> days;
  final int selectedIndex;
  final ValueChanged<int> onDaySelected;

  _DayPillsDelegate({required this.days, required this.selectedIndex, required this.onDaySelected});

  @override double get minExtent => 60;
  @override double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: minExtent, // must fill the declared extent for a pinned header
      child: Container(
        color: AppColors.bg.withOpacity(0.9),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(days.length, (index) {
              final isSelected = index == selectedIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onDaySelected(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.green : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      'Day ${days[index].dayNumber}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppColors.inkFaint),
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

  @override bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}

class _DayCard extends StatelessWidget {
  final DayData day;
  final bool isSelected, isEditable;
  final VoidCallback onAddPlace, onEditDay;

  const _DayCard({required this.day, required this.isSelected, required this.onAddPlace, required this.onEditDay, this.isEditable = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isSelected ? AppColors.green : Colors.transparent, width: isSelected ? 2 : 0),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), offset: const Offset(0, 4), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Day ${day.dayNumber}', style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700)),
                  Text('${day.date} • ${day.totalStops} stops', style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          ..._buildStops(),
          if (isSelected && isEditable) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onAddPlace,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: AppColors.moduleBorder), borderRadius: BorderRadius.circular(30)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 18, color: AppColors.green),
                    SizedBox(width: 6),
                    Text('Add Place', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.green)),
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
      widgets.add(_StopItem(stop: day.stops[i], isLast: i == day.stops.length - 1));
      if (i < day.stops.length - 1 && day.stops[i].transit != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.directions_walk, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 18),
                Text(day.stops[i].transit!, style: const TextStyle(fontSize: 11, color: AppColors.inkFaint)),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

// ─── Timeline Stop Item (Core Update) ─────────────────────────

class _StopItem extends StatelessWidget {
  final StopData stop;
  final bool isLast;

  const _StopItem({required this.stop, required this.isLast});

  @override
  Widget build(BuildContext context) {
    // Styling logic based on Status & Highlight
    bool isCompleted = stop.status == 'Completed';
    bool isSkipped = stop.status == 'Skipped';
    bool isActive = stop.isHighlighted;

    double cardOpacity = (isCompleted || isSkipped) ? 0.6 : 1.0;
    Color cardBgColor = (isCompleted || isSkipped) ? AppColors.bg : Colors.white;
    Color borderColor = isActive ? AppColors.green : AppColors.moduleBorder.withOpacity(0.6);
    double borderWidth = isActive ? 2.0 : 1.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Node & Line
          Column(
            children: [
              const SizedBox(height: 24), // Center node vertically with the card title
              _buildNode(isCompleted, isSkipped, isActive),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.moduleBorder,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),

          // Stop Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Opacity(
                opacity: cardOpacity,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: borderWidth),
                    boxShadow: isActive ? [BoxShadow(color: AppColors.green.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4))] : [],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Thumbnail
                          if (stop.imageUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(stop.imageUrl!, width: 48, height: 48, fit: BoxFit.cover),
                            )
                          else
                            Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.place, color: AppColors.inkFaint),
                            ),
                          const SizedBox(width: 12),

                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        stop.name,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.ink),
                                      ),
                                    ),
                                    if (!isCompleted && !isSkipped)
                                      const Icon(Icons.more_vert, size: 18, color: AppColors.inkFaint),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${stop.time} (${stop.duration})',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? AppColors.accent : AppColors.inkFaint),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  stop.type,
                                  style: const TextStyle(fontSize: 11, color: AppColors.inkFaint),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Status Badge / Skip Note
                      if (isCompleted || isSkipped) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCompleted ? AppColors.accentSoft : AppColors.bg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isCompleted ? '✓ Completed' : 'Skipped',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCompleted ? AppColors.green : AppColors.inkFaint,
                            ),
                          ),
                        ),
                        if (isSkipped && stop.skipReason != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Reason: ${stop.skipReason}',
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.inkFaint),
                            ),
                          ),
                      ],

                      // Action Buttons (Only for the Active Ongoing Stop)
                      if (isActive && !isCompleted && !isSkipped) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Complete'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.green,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.fast_forward, size: 16),
                                label: const Text('Skip'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.inkSoft,
                                  side: const BorderSide(color: AppColors.moduleBorder),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  // Visual Timeline Node Logic
  Widget _buildNode(bool isCompleted, bool isSkipped, bool isActive) {
    if (isCompleted) {
      return Container(
        width: 20, height: 20,
        decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
        child: const Icon(Icons.check, color: Colors.white, size: 12),
      );
    } else if (isSkipped) {
      return Container(
        width: 20, height: 20,
        decoration: const BoxDecoration(color: AppColors.inkFaint, shape: BoxShape.circle),
        child: const Icon(Icons.fast_forward, color: Colors.white, size: 12),
      );
    } else if (isActive) {
      return Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: AppColors.green,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.green.withOpacity(0.2), width: 4),
        ),
      );
    } else {
      return Container(
        width: 16, height: 16,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.moduleBorder, width: 3),
        ),
      );
    }
  }
}
