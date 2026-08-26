import 'package:flutter/material.dart';
import 'package:narrate_my/view/Itinerary/itinerary_theme_tokens.dart';

class EditItineraryScreen extends StatelessWidget {
  const EditItineraryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Serene Traveler',
          style: AppTextStyles.pageTitle.copyWith(fontSize: 20), //[cite: 1]
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {},
            child: Text(
              'Done',
              style: AppTextStyles.button.copyWith(
                color: AppColors.accentSoft, //[cite: 1]
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main Scrollable Content
          ListView(
            padding: const EdgeInsets.only(
              left: AppSpacing.screenMargin, //[cite: 1]
              right: AppSpacing.screenMargin,
              top: 16.0,
              bottom: 140.0, // Space for FAB and sticky bottom bar
            ),
            children: [
              _buildHeaderSection(),
              const SizedBox(height: AppSpacing.sectionGap), //[cite: 1]
              _buildMapSection(),
              const SizedBox(height: AppSpacing.sectionGap),
              _buildStopsTimeline(),
            ],
          ),

          // Floating Action Button (FAB)
          Positioned(
            bottom: 100, // Above the sticky bottom bar
            right: AppSpacing.screenMargin, //[cite: 1]
            child: FloatingActionButton(
              onPressed: () {},
              backgroundColor: AppColors.green, //[cite: 1]
              foregroundColor: AppColors.surface, //[cite: 1]
              elevation: 4,
              child: const Icon(Icons.add, size: 28),
            ),
          ),

          // Sticky Bottom Actions
          _buildStickyBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day 1 · 12 Aug · Kuala Lumpur Getaway',
          style: AppTextStyles.button.copyWith(color: AppColors.ink), //[cite: 1]
        ),
        const SizedBox(height: 4.0),
        Text(
          'Reorder, edit or add places to your day.',
          style: AppTextStyles.labelSm, // Inherits muted color from theme[cite: 1]
        ),
      ],
    );
  }

  Widget _buildMapSection() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.surface, //[cite: 1]
        borderRadius: BorderRadius.circular(AppRadius.card), //[cite: 1]
        boxShadow: const [
          BoxShadow(
            color: AppShadows.card, //[cite: 1]
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        image: const DecorationImage(
          image: NetworkImage(
            'https://lh3.googleusercontent.com/aida-public/AB6AXuD2HSadleC5k6pUPBPqzKVm7Uf16oGREsz1gdk72l0niwFPoMS4iOINY_KjgmrD5Dyzgk3fCJVycPuAZ89Ww9J7cJGMK8pSiHL8foPInbRuSX_b58A-esnnQL3sjBEmbQw3c6tNbN0-eDeiARxFYmjsbibDNj0Gc6UV3Z2hrHYA1sywsOvBHJC0rWhbjB64Rt4GyJSwO8l2cimG4WC3xnMVt95zCA_vzemCCZ1dC6htZkfUJBllrabu',
          ),
          fit: BoxFit.cover,
        ),
      ),
      alignment: Alignment.topLeft,
      child: Container(
        margin: const EdgeInsets.all(16.0),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pillPaddingX, //[cite: 1]
          vertical: AppSpacing.pillPaddingY, //[cite: 1]
        ),
        decoration: BoxDecoration(
          color: AppColors.green.withOpacity(0.9), //[cite: 1]
          borderRadius: BorderRadius.circular(AppRadius.pill), //[cite: 1]
        ),
        child: Text(
          'Day 1 route',
          style: AppTextStyles.labelSm.copyWith(color: AppColors.surface), //[cite: 1]
        ),
      ),
    );
  }

  Widget _buildStopsTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STOPS',
          style: AppTextStyles.sectionLabel.copyWith(letterSpacing: 1.5), //[cite: 1]
        ),
        const SizedBox(height: 16.0),

        // Stop 1: Expanded
        _buildTimelineRow(
          number: '1',
          isActive: true,
          isLast: false,
          card: _buildExpandedStopCard(),
        ),

        // Stop 2: Collapsed
        _buildTimelineRow(
          number: '2',
          isActive: false,
          isLast: false,
          card: _buildCollapsedStopCard('Precious Old China', '12:00 – 13:15'),
        ),

        // Stop 3: Collapsed
        _buildTimelineRow(
          number: '3',
          isActive: false,
          isLast: true, // End of the line before "Add place"
          card: _buildCollapsedStopCard('Petronas Towers', '15:00 – 17:00'),
        ),

        // Add another place button
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accentSoft, //[cite: 1]
                  width: 2,
                  style: BorderStyle.none, // Handled by a dash package normally, using solid fallback or simple style
                ),
              ),
              child: const Icon(
                Icons.add,
                size: 20,
                color: AppColors.accentSoft, //[cite: 1]
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Add another place',
              style: AppTextStyles.button.copyWith(
                color: AppColors.accentSoft, //[cite: 1]
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildTimelineRow({
    required String number,
    required bool isActive,
    required bool isLast,
    required Widget card,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch line to content height
        children: [
          // Timeline Indicator Column
          SizedBox(
            width: 36, // Fixed width for alignment
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AppColors.green //[cite: 1]
                        : AppColors.surface2, //[cite: 1]
                    border: isActive
                        ? null
                        : Border.all(color: AppColors.moduleBorder.withOpacity(0.3)), //[cite: 1]
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    number,
                    style: AppTextStyles.button.copyWith(
                      color: isActive ? AppColors.surface : AppColors.inkSoft, //[cite: 1]
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: CustomPaint(
                      painter: _DashedLinePainter(
                        color: AppColors.moduleBorder, //[cite: 1]
                      ),
                    ),
                  ),
                // Give some spacing if it is the last item so the gap remains
                if (isLast) const SizedBox(height: 24),
              ],
            ),
          ),
          const SizedBox(width: 16), // Gap between timeline and card
          // The Content Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sectionGap), //[cite: 1]
              child: card,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedStopCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding), //[cite: 1]
      decoration: BoxDecoration(
        color: AppColors.surface, //[cite: 1]
        borderRadius: BorderRadius.circular(AppRadius.card), //[cite: 1]
        boxShadow: const [
          BoxShadow(
            color: AppShadows.card, //[cite: 1]
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Batu Caves', style: AppTextStyles.button.copyWith(color: AppColors.ink)), //[cite: 1]
                  const SizedBox(height: 4),
                  Text('08:30 – 10:30', style: AppTextStyles.labelSm), //[cite: 1]
                ],
              ),
              Row(
                children: [
                  _buildIconBtn(Icons.edit, AppColors.surface2, AppColors.inkSoft), //[cite: 1]
                  const SizedBox(width: 8),
                  _buildIconBtn(Icons.delete, AppColors.surface2, AppColors.error), //[cite: 1]
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Details
          _buildDetailRow(Icons.location_on, 'Gombak, 68100 Batu Caves'),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.schedule, 'Suggested visit: 2 hours'),
          const SizedBox(height: 20),
          // Travel Context Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg, //[cite: 1]
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.moduleBorder), //[cite: 1]
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TravelContextText(icon: Icons.directions_car, text: 'From prev: 25 min'),
                _TravelContextText(icon: Icons.arrow_downward, text: 'To next: 30 min'),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCollapsedStopCard(String title, String time) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding), //[cite: 1]
      decoration: BoxDecoration(
        color: AppColors.surface, //[cite: 1]
        borderRadius: BorderRadius.circular(AppRadius.card), //[cite: 1]
        boxShadow: const [
          BoxShadow(
            color: AppShadows.card, //[cite: 1]
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.button.copyWith(color: AppColors.ink)), //[cite: 1]
              const SizedBox(height: 4),
              Text(time, style: AppTextStyles.labelSm), //[cite: 1]
            ],
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            color: AppColors.inkSoft, //[cite: 1]
            style: IconButton.styleFrom(backgroundColor: AppColors.bg), //[cite: 1]
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.accentSoft), //[cite: 1]
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: AppTextStyles.bodySm.copyWith(color: AppColors.inkSoft)), //[cite: 1]
        ),
      ],
    );
  }

  Widget _buildIconBtn(IconData icon, Color bgColor, Color iconColor) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, size: 20, color: iconColor),
        onPressed: () {},
      ),
    );
  }

  Widget _buildStickyBottomBar(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: AppSpacing.screenMargin, //[cite: 1]
          right: AppSpacing.screenMargin,
          top: 16.0,
          bottom: MediaQuery.of(context).padding.bottom + 16.0,
        ),
        decoration: BoxDecoration(
          color: AppColors.bg.withOpacity(0.9), //[cite: 1]
          boxShadow: const [
            BoxShadow(
              color: AppShadows.card, //[cite: 1]
              blurRadius: 20,
              offset: Offset(0, -4),
            )
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentSoft, //[cite: 1]
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Review Changes'),
          ),
        ),
      ),
    );
  }
}

class _TravelContextText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TravelContextText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.inkFaint), //[cite: 1]
        const SizedBox(width: 6),
        Text(text, style: AppTextStyles.labelSm), //[cite: 1]
      ],
    );
  }
}

// Custom Painter for the Dashed Timeline Line
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    double dashHeight = 5, dashSpace = 3, startY = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}