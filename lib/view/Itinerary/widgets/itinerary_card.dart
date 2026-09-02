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
    const Color primaryColor = AppColors.brandGreen;
    const Color textColor = AppColors.brandCharcoal;
    final Color subtitleColor = AppColors.outline;

    // Date range
    final String dateRange =
        '${_formatDate(itinerary.startDate)} - ${_formatDate(itinerary.endDate)}';

    // Plan summary: total days + number of interests
    final String planSummary =
        '${itinerary.totalDays} days • ${itinerary.interests.length} interests';

    final bool isUpcoming = itinerary.status.toUpperCase() == 'UPCOMING';

    final String imageUrl =
        itinerary.coverImageUrl ??
        'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=800&q=80';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
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
            // Image with Status Badge
            Stack(
              children: [
                SizedBox(
                  height: 136,
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    color: isUpcoming ? null : Colors.grey,
                    colorBlendMode: isUpcoming ? null : BlendMode.saturation,
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
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUpcoming
                              ? Icons.event_rounded
                              : Icons.history_rounded,
                          size: 13,
                          color: isUpcoming ? primaryColor : subtitleColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          itinerary.status,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isUpcoming ? primaryColor : subtitleColor,
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
