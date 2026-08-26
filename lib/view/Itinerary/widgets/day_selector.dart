import 'package:flutter/material.dart';

class DaySelector extends StatelessWidget {
  const DaySelector({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color tertiaryText = Color(0xFF5F5E58);
    const Color pineGreen = Color(0xFF194D44);
    const Color surfaceInactive = Color(0xFFE6E2D6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            "ADD TO DAY",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: tertiaryText),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDayPill("Day 1", false, surfaceInactive, tertiaryText),
              const SizedBox(width: 12),
              _buildDayPill("Day 2", true, pineGreen, Colors.white),
              const SizedBox(width: 12),
              _buildDayPill("Day 3", false, surfaceInactive, tertiaryText),
              const SizedBox(width: 12),
              _buildDayPill("Day 4", false, surfaceInactive, tertiaryText),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildDayPill(String text, bool isActive, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}