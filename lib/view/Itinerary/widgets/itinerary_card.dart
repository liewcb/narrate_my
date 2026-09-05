// lib/widgets/itinerary_card.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../model/entities/itinerary.dart';
import '../../../core/theme/colors.dart';

class ItineraryCard extends StatelessWidget {
  final Itinerary itinerary;
  final VoidCallback onTap;

  const ItineraryCard({Key? key, required this.itinerary, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color textColor = AppColors.brandCharcoal;
    final Color subtitleColor = AppColors.outline;

    // Date range
    final String dateRange =
        '${_formatDate(itinerary.startDate)} - ${_formatDate(itinerary.endDate)}';

    // Plan summary: total days + number of interests
    final String planSummary =
        '${itinerary.totalDays} days • ${itinerary.interests.length} interests';

    final String status = itinerary.status.toUpperCase();

    final bool isUpcoming = status == 'UPCOMING';
    final bool isOngoing = status == 'ONGOING';
    final bool isPast = status == 'PAST';

    final String imageUrl =
        itinerary.coverImageUrl ??
            'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=800&q=80';

    // ─── Status Colors Configuration ──────────────────────────────────
    Color cardBackgroundColor;
    Color badgeBgColor;
    Color badgeTextColor;
    Color badgeIconColor;

    if (isOngoing) {
      // ✅ ONGOING: Green theme with white text
      cardBackgroundColor = Colors.green.shade50;
      badgeBgColor = Colors.green.shade600; // Strong green background
      badgeTextColor = Colors.white; // White text
      badgeIconColor = Colors.white; // White icon
    } else if (isUpcoming) {
      // ✅ UPCOMING: Yellow theme with red text
      cardBackgroundColor = Colors.yellow.shade50;
      badgeBgColor = Colors.yellow.shade400; // Vibrant yellow background
      badgeTextColor = Colors.red.shade800; // Dark red text for contrast
      badgeIconColor = Colors.red.shade800; // Dark red icon
    } else {
      // ✅ PAST: Orange theme
      cardBackgroundColor = Colors.orange.shade50;
      badgeBgColor = Colors.orange.shade100;
      badgeTextColor = Colors.deepOrange.shade900;
      badgeIconColor = Colors.deepOrange.shade900;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        // Dynamic border that perfectly matches the active status color
        border: Border.all(
          color: badgeBgColor.withOpacity(0.6),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A004D40),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with Status Badge and Gradient
            Stack(
              children: [
                // 1. The Base Image
                SizedBox(
                  height: 136,
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: AppColors.brandGrayLight,
                        child: const Center(
                          child: Icon(
                            Icons.image_not_supported_rounded,
                            color: AppColors.outline,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 2. Subtle Top Gradient for Badge Readability
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 54,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. The Status Badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUpcoming
                              ? Icons.event_rounded
                              : isOngoing
                              ? Icons.play_circle_rounded
                              : Icons.history_rounded,
                          size: 13,
                          color: badgeIconColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          itinerary.status,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: badgeTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Card Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itinerary.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Metadata Row 1: Date Range
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 15,
                        color: subtitleColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dateRange,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: subtitleColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Metadata Row 2: Duration & Interests
                  Row(
                    children: [
                      Icon(Icons.map_rounded, size: 15, color: subtitleColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          planSummary,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: subtitleColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_monthShort(date.month)} ${date.year}';
  }

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}