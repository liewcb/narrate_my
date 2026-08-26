// lib/view/Itinerary/manage_itinerary/itinerary_preview_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:narrate_my/view/Itinerary/itinerary_theme_tokens.dart';
import '../../../model/entities/itinerary_stop.dart';

/// Condensed itinerary preview: renders the first stop of each day
/// (smallest [ItineraryStop.stopOrder] within each [ItineraryStop.dayIndex]).
///
/// Intended for a home screen card / summary section.
class ItineraryPreviewCard extends StatelessWidget {
  final List<ItineraryStop> firstStopPerDay;
  final String? itineraryTitle;
  final VoidCallback? onTap;

  const ItineraryPreviewCard({
    Key? key,
    required this.firstStopPerDay,
    this.itineraryTitle,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      elevation: 2,
      shadowColor: AppShadows.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (itineraryTitle != null && itineraryTitle!.isNotEmpty) ...[
              Text(
                itineraryTitle!,
                style: AppTextStyles.pageTitle,
              ),
              const SizedBox(height: 4.0),
            ],
            Text(
              'Day-by-day preview',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
            ),
            const SizedBox(height: 16.0),
            if (firstStopPerDay.isEmpty)
              Text(
                'No stops yet.',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
              )
            else
              ...firstStopPerDay.map((stop) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildPreviewRow(stop),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(ItineraryStop stop) {
    final time = '${DateFormat('HH:mm').format(stop.startTime)} – '
        '${DateFormat('HH:mm').format(stop.endTime)}'; //[cite: 4]
    final weather = stop.weatherNote; //[cite: 4]

    return InkWell(
      onTap: onTap, //[cite: 4]
      borderRadius: BorderRadius.circular(AppRadius.iconSm), //[cite: 4]
      // Added padding inside the InkWell for a better tap target
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start, //[cite: 4]
          children: [
            // Day badge
            Container(
              width: 40, //[cite: 4]
              height: 40, //[cite: 4]
              alignment: Alignment.center, //[cite: 4]
              decoration: const BoxDecoration(
                color: AppColors.accent, //[cite: 4]
                shape: BoxShape.circle, //[cite: 4]
              ),
              child: Text(
                '${stop.dayIndex}', //[cite: 4]
                style: const TextStyle(
                  color: AppColors.surface, //[cite: 4]
                  fontWeight: FontWeight.bold, //[cite: 4]
                ),
              ),
            ),
            const SizedBox(width: 12.0), //[cite: 4]
            // Stop details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, //[cite: 4]
                children: [
                  Text(
                    stop.place?.name ?? stop.placeId, //[cite: 4]
                    style: AppTextStyles.bodyLg.copyWith( //[cite: 4]
                      fontWeight: FontWeight.w600, //[cite: 4]
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  // Added a small clock icon
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: AppColors.inkSoft),
                      const SizedBox(width: 4.0),
                      Text(
                        'Day ${stop.dayIndex} • $time', //[cite: 4]
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.inkSoft, //[cite: 4]
                        ),
                      ),
                    ],
                  ),
                  if (weather != null && weather.isNotEmpty) ...[ //[cite: 4]
                    const SizedBox(height: 4.0),
                    // Added a small weather icon
                    Row(
                      children: [
                        const Icon(Icons.cloud_outlined, size: 14, color: AppColors.inkFaint),
                        const SizedBox(width: 4.0),
                        Text(
                          weather, //[cite: 4]
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.inkFaint, //[cite: 4]
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12.0),
            const Icon(Icons.chevron_right, color: AppColors.inkFaint), //[cite: 4]
          ],
        ),
      ),
    );
  }
}
