import 'package:flutter/material.dart';

class StickyBottomActions extends StatelessWidget {
  final Color bgColor;
  final Color accentColor;
  final Color mutedText;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const StickyBottomActions({
    Key? key,
    required this.bgColor,
    required this.accentColor,
    required this.mutedText,
    required this.onContinue,
    required this.onSkip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [bgColor, bgColor.withOpacity(0.95), bgColor.withOpacity(0.0)],
        ),
      ),
      child: Column(
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              minimumSize: const Size(double.infinity, 54),
              elevation: 8,
              shadowColor: accentColor.withOpacity(0.4),
            ),
            onPressed: onContinue,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text("Continue with 2 Places", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onSkip,
            child: Text(
              "Skip for now",
              style: TextStyle(color: mutedText, fontSize: 14, fontWeight: FontWeight.w500, decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }
}