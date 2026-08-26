import 'package:flutter/material.dart';

class ScreenHeader extends StatelessWidget {
  final Color primaryColor;

  const ScreenHeader({Key? key, required this.primaryColor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () => Navigator.maybePop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                ),
                child: Icon(Icons.arrow_back, color: primaryColor, size: 20),
              ),
            ),
            const Text(
              "STEP 2 OF 3",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
            ),
            const SizedBox(width: 36),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          "Must-go places",
          style: TextStyle(fontFamily: 'Playfair Display', fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor, height: 1.1),
        ),
      ],
    );
  }
}