import 'package:flutter/material.dart';
import 'stop_item.dart';

class DaySection extends StatelessWidget {
  final String dayTitle;
  final String daySubtitle;
  final List<StopItem> stops;

  const DaySection({
    Key? key,
    required this.dayTitle,
    required this.daySubtitle,
    required this.stops,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color brandLine = Color(0xFFE3DECF);
    const Color brandText = Color(0xFF1A201E);
    const Color brandTextMuted = Color(0xFF5A6663);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day Header
        Container(
          padding: const EdgeInsets.only(bottom: 16),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: brandLine)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dayTitle,
                style: const TextStyle(
                  fontFamily: 'Playfair Display',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: brandText,
                ),
              ),
              Text(
                daySubtitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: brandTextMuted,
                ),
              ),
            ],
          ),
        ),
        // Timeline Stops
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Column(
            children: stops,
          ),
        ),
      ],
    );
  }
}