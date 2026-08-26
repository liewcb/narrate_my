import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget {
  const CustomAppBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.4),
                child: const Icon(Icons.arrow_back, color: Colors.black)
            ),
            CircleAvatar(
                backgroundColor: const Color(0xFFF9E4E4).withOpacity(0.8), // Replaces AppColors.brandPinkLight
                child: const Icon(Icons.delete_outline, color: Color(0xFF93000A)) // Replaces AppColors.deleteRed
            ),
          ],
        ),
      ),
    );
  }
}

class HeroHeader extends StatelessWidget {
  const HeroHeader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.grey,
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(32),
            bottomRight: Radius.circular(32)
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                "Tell us about your trip",
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)
            ),
            Text(
                "Let's craft the perfect itinerary.",
                style: TextStyle(color: Colors.white70, fontSize: 15)
            ),
          ],
        ),
      ),
    );
  }
}

class StickyFooter extends StatelessWidget {
  const StickyFooter({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9F9F7); // Replaces AppColors.background
    const Color brandTerracotta = Color(0xFFECA48F); // Replaces AppColors.brandTerracotta
    const Color brandCharcoal = Color(0xFF333333); // Replaces AppColors.brandCharcoal

    return Container(
      padding: const EdgeInsets.only(top: 48, bottom: 32, left: 20, right: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            backgroundColor,
            backgroundColor.withOpacity(0.0)
          ],
        ),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandTerracotta,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        ),
        onPressed: () {},
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
                "Next Step",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: brandCharcoal)
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, color: brandCharcoal),
          ],
        ),
      ),
    );
  }
}