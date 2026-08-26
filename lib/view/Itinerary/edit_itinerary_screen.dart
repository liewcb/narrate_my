import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_place_screen.dart';
import '../../core/theme/colors.dart';

class ItineraryStop {
  final String id;
  final String name;
  final String time;
  final String address;
  final String suggestedDuration;
  final String travelFromPrev;
  final String travelToNext;

  ItineraryStop({
    required this.id,
    required this.name,
    required this.time,
    required this.address,
    required this.suggestedDuration,
    this.travelFromPrev = '',
    this.travelToNext = '',
  });
}

class EditItineraryScreen extends StatefulWidget {
  const EditItineraryScreen({super.key});

  @override
  State<EditItineraryScreen> createState() => _EditItineraryScreenState();
}

class _EditItineraryScreenState extends State<EditItineraryScreen> {
  List<ItineraryStop> _stops = [
    ItineraryStop(
      id: '1',
      name: 'Batu Caves',
      time: '08:30 – 10:30',
      address: 'Gombak, 68100 Batu Caves',
      suggestedDuration: '2 hours',
      travelFromPrev: '',
      travelToNext: '30 min',
    ),
    ItineraryStop(
      id: '2',
      name: 'Precious Old China',
      time: '12:00 – 13:15',
      address: 'Central Market, Kuala Lumpur',
      suggestedDuration: '1.5 hours',
      travelFromPrev: '25 min',
      travelToNext: '15 min',
    ),
    ItineraryStop(
      id: '3',
      name: 'Petronas Towers',
      time: '15:00 – 17:00',
      address: 'Kuala Lumpur City Centre',
      suggestedDuration: '2 hours',
      travelFromPrev: '30 min',
      travelToNext: '',
    ),
  ];

  void _addStop() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddPlaceScreen(
          itineraryId: 'draft',
          dayIndex: 0,
        ),
      ),
    );
  }

  void _editStop(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddPlaceScreen(
          itineraryId: 'draft',
          dayIndex: 0,
        ),
      ),
    );
  }

  void _deleteStop(String id) {
    setState(() {
      _stops.removeWhere((stop) => stop.id == id);
    });
  }

  void _onDone() {
    Navigator.pop(context);
  }

  void _reviewChanges() {
    if (_stops.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Add at least one stop before reviewing.')),
        );
      return;
    }
    final names = _stops.map((s) => s.name.toLowerCase()).toList();
    if (names.length != names.toSet().length) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('You have duplicate stops in this day.')),
        );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmBg,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildMapPreview(),
                const SizedBox(height: 24),
                _buildStopsList(),
                const SizedBox(height: 120),
              ],
            ),
          ),
          Positioned(
            bottom: 100,
            right: 20,
            child: _buildFloatingAddButton(),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomButton(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.warmBg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.charcoal),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Serene Traveler',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.charcoal,
          letterSpacing: -0.02,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _onDone,
          child: const Text(
            'Done',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.terracottaDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day 1 · 12 Aug · Kuala Lumpur Getaway',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.charcoal,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Reorder, edit or add places to your day.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.mutedText,
          ),
        ),
      ],
    );
  }

  Widget _buildMapPreview() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=600&q=80',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.grayWarm,
                child: const Icon(Icons.map, color: AppColors.taupe),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.2),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4],
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.pineDark.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'Day 1 route',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STOPS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppColors.mutedText,
          ),
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            Positioned(
              left: 17,
              top: 16,
              bottom: 16,
              child: SizedBox(
                width: 2,
                child: CustomPaint(
                  painter: _DashedLinePainter(),
                ),
              ),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _stops.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _stops.removeAt(oldIndex);
                  _stops.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final stop = _stops[index];
                return _StopItem(
                  key: ValueKey(stop.id),
                  stop: stop,
                  number: index + 1,
                  isFirst: index == 0,
                  isLast: index == _stops.length - 1,
                  onEdit: () => _editStop(stop.id),
                  onDelete: () => _deleteStop(stop.id),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _addStop,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.terracottaDark, width: 2),
                    color: AppColors.warmBg,
                  ),
                  child: const Icon(Icons.add, size: 20, color: AppColors.terracottaDark),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Add another place',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.terracottaDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingAddButton() {
    return FloatingActionButton(
      onPressed: _addStop,
      backgroundColor: AppColors.tealGreen,
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }

  Widget _buildBottomButton() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warmBg.withOpacity(0.9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A004D40),
                offset: Offset(0, -4),
                blurRadius: 20,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _reviewChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.terracottaDark,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Review Changes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StopItem extends StatelessWidget {
  final ItineraryStop stop;
  final int number;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StopItem({
    super.key,
    required this.stop,
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFirst ? AppColors.tealGreen : AppColors.surfaceInactive,
              border: isFirst ? null : Border.all(color: AppColors.taupe.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isFirst ? Colors.white : AppColors.charcoal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    offset: Offset(0, 2),
                    blurRadius: 8,
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
                              stop.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.charcoal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              stop.time,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: onEdit,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceInactive,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit, size: 20, color: AppColors.warmBrown),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: onDelete,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.dangerBg,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.delete_outline, size: 20, color: AppColors.dangerText),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.drag_handle, color: AppColors.taupe),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, size: 20, color: AppColors.terracottaDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stop.address,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.warmBrown,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 20, color: AppColors.terracottaDark),
                      const SizedBox(width: 8),
                      Text(
                        'Suggested visit: ${stop.suggestedDuration}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.warmBrown,
                        ),
                      ),
                    ],
                  ),
                  if (stop.travelFromPrev.isNotEmpty || stop.travelToNext.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warmGrayLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.taupe.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (stop.travelFromPrev.isNotEmpty)
                            Row(
                              children: [
                                const Icon(Icons.directions_car, size: 16, color: AppColors.taupe),
                                const SizedBox(width: 4),
                                Text(
                                  'From prev: ${stop.travelFromPrev}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.taupe,
                                  ),
                                ),
                              ],
                            ),
                          if (stop.travelToNext.isNotEmpty)
                            Row(
                              children: [
                                const Icon(Icons.arrow_downward, size: 16, color: AppColors.taupe),
                                const SizedBox(width: 4),
                                Text(
                                  'To next: ${stop.travelToNext}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.taupe,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.taupe
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